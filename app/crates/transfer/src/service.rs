use std::collections::{HashMap, HashSet};
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Weak};
use std::time::Duration;

use dapper_api::SubsonicApi;
use dapper_device::{ManifestSong, ManifestWriter};
use dapper_domain::{DeviceSettings, Playlist, Song, TransferStatus, TransferTask};
use dapper_store::Store;
use parking_lot::Mutex;
use serde::Serialize;
use tokio::sync::{Notify, Semaphore, watch};
use tokio_util::sync::CancellationToken;
use tokio_util::task::TaskTracker;

use crate::engine;
use crate::fsops;
use crate::index::{TaskIndex, Transition, is_terminal};

/// Max files post-processing (FLAC tag clean / cover shrink) at once,
/// independent of download concurrency so it never steals a download slot.
pub(crate) const POST_PROCESS_CONCURRENCY: usize = 3;
/// Task-list emissions are coalesced so a burst of completions costs one
/// snapshot rebuild.
const TASKS_COALESCE: Duration = Duration::from_millis(100);
const MANIFEST_DEBOUNCE: Duration = Duration::from_millis(300);

pub struct TransferDeps {
    pub support_dir: PathBuf,
    pub store: Arc<Store>,
    pub http: reqwest::Client,
}

/// Transfer state of an album or song across the queue. `queued` is false
/// once any of its tasks is active.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct QueueItemStatus {
    pub active: bool,
    pub queued: bool,
}

pub(crate) struct EngineHandle {
    /// Wakes the downloader loop (new ready work, staged unit drained).
    pub wake: Arc<Notify>,
    /// Wakes a writer parked on pause.
    pub resume: Arc<Notify>,
}

struct PendingPlaylist {
    playlist: Playlist,
    device: String,
    remaining: usize,
}

pub(crate) struct State {
    pub idx: TaskIndex,
    pub api: Option<Arc<SubsonicApi>>,
    pub engines: HashMap<String, EngineHandle>,
    pub paused: HashSet<String>,
    pub tokens: HashMap<String, CancellationToken>,
    expected_song_counts: HashMap<String, i64>,
    task_playlist_group: HashMap<String, String>,
    pending_playlists: HashMap<String, PendingPlaylist>,
    finished_playlists: Vec<PendingPlaylist>,
    tasks_dirty: bool,
}

impl State {
    pub fn push(&mut self, task: TransferTask) {
        self.idx.push(task);
        self.tasks_dirty = true;
    }

    /// Mutates one task; ids/status changes mark the list for emission and
    /// persistence, and a first terminal status counts towards its playlist.
    pub fn update(&mut self, id: &str, f: impl FnOnce(&mut TransferTask)) -> Option<Transition> {
        let tr = self.idx.update(id, f)?;
        if tr.from != tr.to {
            self.tasks_dirty = true;
            if is_terminal(tr.to) && !is_terminal(tr.from) {
                self.on_playlist_task_done(id);
            }
        }
        Some(tr)
    }

    pub fn set_status(&mut self, id: &str, status: TransferStatus) {
        self.update(id, |t| t.status = status);
    }

    // Decrements the playlist counter for this task; once every song in the
    // group has finished (completed, failed or cancelled) its M3U is due.
    fn on_playlist_task_done(&mut self, id: &str) {
        let Some(group) = self.task_playlist_group.remove(id) else {
            return;
        };
        let Some(entry) = self.pending_playlists.get_mut(&group) else {
            return;
        };
        entry.remaining -= 1;
        if entry.remaining == 0
            && let Some(done) = self.pending_playlists.remove(&group)
        {
            self.finished_playlists.push(done);
        }
    }

    pub fn expected_count(&self, folder: &str) -> Option<i64> {
        self.expected_song_counts.get(folder).copied()
    }

    pub fn is_live(&self, id: &str) -> bool {
        self.idx.status(id) == Some(TransferStatus::InProgress)
    }

    pub fn has_work(&self, device: &str) -> bool {
        self.api.is_some() && self.idx.has_ready(device)
    }
}

pub(crate) struct Inner {
    pub support: PathBuf,
    pub store: Arc<Store>,
    pub http: reqwest::Client,
    pub state: Mutex<State>,
    pub post_sem: Semaphore,
    pub manifest_writer: ManifestWriter,
    tasks_tx: watch::Sender<Arc<Vec<TransferTask>>>,
    tasks_changed: Arc<Notify>,
    progress: Mutex<HashMap<String, (i64, i64)>>,
    progress_tx: watch::Sender<Arc<HashMap<String, (i64, i64)>>>,
    progress_changed: Arc<Notify>,
    manifest_rev_tx: watch::Sender<u64>,
    manifest_bump_pending: AtomicBool,
    persist_lock: tokio::sync::Mutex<()>,
    /// Manifest and M3U writes that outlive their tasks.
    effects: TaskTracker,
    /// Engine actors, awaited by shutdown.
    engine_tasks: TaskTracker,
    paused_tx: watch::Sender<Arc<Vec<String>>>,
    /// Set by [`TransferService::shutdown`]: nothing new starts and
    /// cancellations leave task statuses alone (restored as queued later).
    pub shutting_down: AtomicBool,
    #[cfg(test)]
    pub test_hooks: crate::tests::Hooks,
}

impl Drop for Inner {
    fn drop(&mut self) {
        // Lets the publisher loops observe the drop and exit.
        self.tasks_changed.notify_one();
        self.progress_changed.notify_one();
    }
}

impl Inner {
    /// Runs `f` under the state lock, then performs its side effects outside
    /// it: list emission/persistence and due playlist M3U writes.
    pub fn mutate<R>(self: &Arc<Self>, f: impl FnOnce(&mut State) -> R) -> R {
        let (r, dirty, playlists) = {
            let mut st = self.state.lock();
            let r = f(&mut st);
            (
                r,
                std::mem::take(&mut st.tasks_dirty),
                std::mem::take(&mut st.finished_playlists),
            )
        };
        if dirty {
            self.tasks_changed.notify_one();
        }
        for p in playlists {
            self.spawn_playlist_write(p);
        }
        r
    }

    fn spawn_playlist_write(self: &Arc<Self>, p: PendingPlaylist) {
        let inner = self.clone();
        self.effects.spawn(async move {
            let settings = inner.device_settings(&p.device).await;
            let name = p.playlist.name.clone();
            let res = tokio::task::spawn_blocking(move || {
                let written = dapper_device::write_playlist_m3u(&p.playlist, &settings)?;
                // write_playlist_m3u cleans the .m3u only; the playlist folder
                // it may have created gets a sidecar on FAT32/exFAT too.
                let playlist_path = dapper_paths::build_playlist_path(&p.playlist, &settings);
                if written && let Some(dir) = Path::new(&playlist_path).parent() {
                    dapper_platform::remove_macos_sidecar(dir);
                }
                Ok::<_, std::io::Error>(written)
            })
            .await;
            match res {
                Ok(Ok(_)) => {}
                Ok(Err(e)) => tracing::warn!("M3U write failed for playlist \"{name}\": {e}"),
                Err(e) => tracing::warn!("M3U write task failed for playlist \"{name}\": {e}"),
            }
        });
    }

    /// Starts the engine for `device` or wakes the running one.
    pub fn start_engine(self: &Arc<Self>, st: &mut State, device: &str) {
        if let Some(h) = st.engines.get(device) {
            h.wake.notify_one();
            return;
        }
        let handle = EngineHandle {
            wake: Arc::new(Notify::new()),
            resume: Arc::new(Notify::new()),
        };
        let (wake, resume) = (handle.wake.clone(), handle.resume.clone());
        st.engines.insert(device.to_string(), handle);
        self.engine_tasks.spawn(engine::run_engine(
            self.clone(),
            device.to_string(),
            wake,
            resume,
        ));
    }

    pub async fn device_settings(&self, device: &str) -> DeviceSettings {
        let store = self.store.clone();
        let d = device.to_string();
        tokio::task::spawn_blocking(move || match store.device_settings(&d) {
            Ok(Some(s)) => s,
            Ok(None) => DeviceSettings::new(d),
            Err(e) => {
                tracing::warn!("device settings unavailable for {d}: {e}");
                DeviceSettings::new(d)
            }
        })
        .await
        .unwrap_or_else(|_| DeviceSettings::new(device))
    }

    /// `AppSettings.transferConcurrency`, re-read on every acquire so a
    /// settings change applies to the next download.
    pub async fn transfer_concurrency(&self) -> usize {
        let store = self.store.clone();
        let n = tokio::task::spawn_blocking(move || store.load_app_settings().transfer_concurrency)
            .await
            .unwrap_or(4);
        n.clamp(1, 4) as usize
    }

    // ── status helpers ───────────────────────────────────────────────────────

    /// Flips `id` to completed only if still in progress, so a cancel that
    /// landed meanwhile is never clobbered.
    pub fn mark_completed(self: &Arc<Self>, id: &str) {
        self.mutate(|st| {
            if st.is_live(id) {
                st.set_status(id, TransferStatus::Completed);
            }
        });
    }

    pub fn fail(self: &Arc<Self>, id: &str, message: String) {
        self.mutate(|st| {
            if matches!(
                st.idx.status(id),
                Some(TransferStatus::Queued | TransferStatus::InProgress)
            ) {
                st.update(id, |t| {
                    t.status = TransferStatus::Failed;
                    t.error_message = Some(message);
                });
            }
        });
    }

    pub fn fail_group(self: &Arc<Self>, group: &str, message: &str) {
        self.mutate(|st| {
            for id in st.idx.group_members(group) {
                if matches!(
                    st.idx.status(&id),
                    Some(TransferStatus::Queued | TransferStatus::InProgress)
                ) {
                    st.update(&id, |t| {
                        t.status = TransferStatus::Failed;
                        t.error_message = Some(message.to_string());
                    });
                }
            }
        });
    }

    pub fn cancel_group_in_flight(self: &Arc<Self>, group: &str) {
        self.mutate(|st| {
            for id in st.idx.group_members(group) {
                if matches!(
                    st.idx.status(&id),
                    Some(TransferStatus::Queued | TransferStatus::InProgress)
                ) {
                    st.set_status(&id, TransferStatus::Cancelled);
                }
            }
        });
    }

    pub fn is_live(&self, id: &str) -> bool {
        self.state.lock().is_live(id)
    }

    pub fn is_paused(&self, device: &str) -> bool {
        self.state.lock().paused.contains(device)
    }

    pub fn remove_tokens<'a>(&self, ids: impl IntoIterator<Item = &'a String>) {
        let mut st = self.state.lock();
        for id in ids {
            st.tokens.remove(id);
        }
    }

    // ── progress ────────────────────────────────────────────────────────────

    pub fn set_progress<'a>(&self, ids: impl IntoIterator<Item = &'a String>, value: (i64, i64)) {
        let mut p = self.progress.lock();
        for id in ids {
            p.insert(id.clone(), value);
        }
        drop(p);
        self.progress_changed.notify_one();
    }

    pub fn clear_progress<'a>(&self, ids: impl IntoIterator<Item = &'a String>) {
        let mut p = self.progress.lock();
        let mut changed = false;
        for id in ids {
            changed |= p.remove(id).is_some();
        }
        drop(p);
        if changed {
            self.progress_changed.notify_one();
        }
    }

    // ── manifest ────────────────────────────────────────────────────────────

    /// Appends to `folder`'s manifest, serialised per folder by the writer;
    /// the device page's "on device" state follows via the revision bump.
    pub fn append_manifest(
        self: &Arc<Self>,
        folder: String,
        entries: Vec<ManifestSong>,
        expected: Option<i64>,
    ) {
        if entries.is_empty() {
            return;
        }
        let inner = self.clone();
        self.effects.spawn(async move {
            let path = PathBuf::from(&folder);
            match inner
                .manifest_writer
                .add_songs(path.clone(), entries, expected)
                .await
            {
                // The manifest is written via tmp + rename, so its sidecar
                // is stripped here rather than by the device crate.
                Ok(()) => {
                    let manifest = path.join(dapper_device::MANIFEST_FILENAME);
                    let _ = tokio::task::spawn_blocking(move || {
                        dapper_platform::remove_macos_sidecar(&manifest)
                    })
                    .await;
                }
                Err(e) => tracing::warn!("manifest update failed for {folder}: {e}"),
            }
            inner.bump_manifest_revision();
        });
    }

    // Trailing debounce: the first bump schedules one notification 300 ms
    // out and later bumps in that window fold into it, so a bulk transfer
    // refreshes "on device" indicators at ~3 Hz instead of once per song.
    fn bump_manifest_revision(self: &Arc<Self>) {
        if self.manifest_bump_pending.swap(true, Ordering::AcqRel) {
            return;
        }
        let weak = Arc::downgrade(self);
        tokio::spawn(async move {
            tokio::time::sleep(MANIFEST_DEBOUNCE).await;
            if let Some(inner) = weak.upgrade() {
                inner.manifest_bump_pending.store(false, Ordering::Release);
                inner.manifest_rev_tx.send_modify(|v| *v += 1);
            }
        });
    }

    // ── persistence ─────────────────────────────────────────────────────────

    async fn persist(&self) {
        let _guard = self.persist_lock.lock().await;
        let snapshot = self.state.lock().idx.snapshot();
        let store = self.store.clone();
        match tokio::task::spawn_blocking(move || store.save_queue(&snapshot)).await {
            Ok(Ok(())) => {}
            Ok(Err(e)) => tracing::warn!("saving transfer queue failed: {e}"),
            Err(e) => tracing::warn!("saving transfer queue panicked: {e}"),
        }
    }
}

async fn publish_tasks(weak: Weak<Inner>, changed: Arc<Notify>) {
    loop {
        changed.notified().await;
        let Some(inner) = weak.upgrade() else { return };
        let snapshot = Arc::new(inner.state.lock().idx.snapshot());
        inner.tasks_tx.send_replace(snapshot);
        // Only id/status changes notify, which is exactly when Dart persisted.
        inner.persist().await;
        drop(inner);
        tokio::time::sleep(TASKS_COALESCE).await;
    }
}

async fn publish_progress(weak: Weak<Inner>, changed: Arc<Notify>) {
    loop {
        changed.notified().await;
        let Some(inner) = weak.upgrade() else { return };
        let snapshot = Arc::new(inner.progress.lock().clone());
        inner.progress_tx.send_replace(snapshot);
        drop(inner);
        tokio::time::sleep(fsops::PROGRESS_INTERVAL).await;
    }
}

/// Per-device transfer queue: one downloader actor and one sequential device
/// writer per device. Must be created inside a Tokio runtime.
pub struct TransferService {
    inner: Arc<Inner>,
}

impl TransferService {
    /// Cleans stale zip temps and staged files, then restores the persisted
    /// queue with in-progress tasks reset to queued. Engines stay idle until
    /// [`TransferService::set_api`] provides a server.
    pub fn new(deps: TransferDeps) -> Self {
        fsops::clean_leftovers(&deps.support_dir);
        let restored: Vec<TransferTask> = deps
            .store
            .load_queue()
            .into_iter()
            .map(|mut t| {
                if t.status == TransferStatus::InProgress {
                    t.status = TransferStatus::Queued;
                    t.bytes_received = 0;
                    t.total_bytes = 0;
                }
                t
            })
            .collect();
        let tasks_changed = Arc::new(Notify::new());
        let progress_changed = Arc::new(Notify::new());
        let inner = Arc::new(Inner {
            support: deps.support_dir,
            store: deps.store,
            http: deps.http,
            tasks_tx: watch::Sender::new(Arc::new(restored.clone())),
            state: Mutex::new(State {
                idx: TaskIndex::from_tasks(restored),
                api: None,
                engines: HashMap::new(),
                paused: HashSet::new(),
                tokens: HashMap::new(),
                expected_song_counts: HashMap::new(),
                task_playlist_group: HashMap::new(),
                pending_playlists: HashMap::new(),
                finished_playlists: Vec::new(),
                tasks_dirty: false,
            }),
            post_sem: Semaphore::new(POST_PROCESS_CONCURRENCY),
            manifest_writer: ManifestWriter::new(),
            tasks_changed: tasks_changed.clone(),
            progress: Mutex::new(HashMap::new()),
            progress_tx: watch::Sender::new(Arc::new(HashMap::new())),
            progress_changed: progress_changed.clone(),
            paused_tx: watch::Sender::new(Arc::new(Vec::new())),
            shutting_down: AtomicBool::new(false),
            manifest_rev_tx: watch::Sender::new(0),
            manifest_bump_pending: AtomicBool::new(false),
            persist_lock: tokio::sync::Mutex::new(()),
            effects: TaskTracker::new(),
            engine_tasks: TaskTracker::new(),
            #[cfg(test)]
            test_hooks: Default::default(),
        });
        tokio::spawn(publish_tasks(Arc::downgrade(&inner), tasks_changed));
        tokio::spawn(publish_progress(Arc::downgrade(&inner), progress_changed));
        Self { inner }
    }

    #[cfg(test)]
    pub(crate) fn inner(&self) -> &Arc<Inner> {
        &self.inner
    }

    /// Sets the active server. With a server, engines start for every device
    /// with queued work; without one, engines pick up nothing new.
    pub fn set_api(&self, api: Option<Arc<SubsonicApi>>) {
        let inner = &self.inner;
        inner.mutate(|st| {
            st.api = api;
            if st.api.is_some() {
                for d in st.idx.ready_devices() {
                    inner.start_engine(st, &d);
                }
            }
        });
    }

    /// Queues one task per song. `expected_album_song_counts` maps album
    /// folder → expected song count, recorded in the folder's manifest.
    pub fn enqueue(
        &self,
        songs: Vec<Song>,
        device_path: &str,
        expected_album_song_counts: Option<HashMap<String, i64>>,
    ) {
        let inner = &self.inner;
        inner.mutate(|st| {
            if let Some(counts) = expected_album_song_counts {
                st.expected_song_counts.extend(counts);
            }
            for s in songs {
                st.push(TransferTask::new(new_id(), s, device_path));
            }
            inner.start_engine(st, device_path);
        });
    }

    /// Queues the playlist's songs; its M3U is written once every one of them
    /// has finished, listing only the songs present on the device.
    pub fn enqueue_playlist(&self, playlist: Playlist, device_path: &str) {
        if playlist.songs.is_empty() {
            return;
        }
        let inner = &self.inner;
        inner.mutate(|st| {
            let group = new_id();
            for s in &playlist.songs {
                let id = new_id();
                st.task_playlist_group.insert(id.clone(), group.clone());
                st.push(TransferTask::new(id, s.clone(), device_path));
            }
            let remaining = playlist.songs.len();
            st.pending_playlists.insert(
                group,
                PendingPlaylist {
                    playlist,
                    device: device_path.to_string(),
                    remaining,
                },
            );
            inner.start_engine(st, device_path);
        });
    }

    /// Queues a bulk zip download of an album/artist: one task per song for
    /// per-row status, all tagged with one group; the first carries
    /// `zip_source_id` and downloads the zip for the whole group. No-op while
    /// the same source is already queued or in progress on this device.
    pub fn enqueue_zip_group(&self, source_id: &str, songs: Vec<Song>, device_path: &str) {
        if songs.is_empty() {
            return;
        }
        let inner = &self.inner;
        inner.mutate(|st| {
            let in_flight = st.idx.iter().any(|t| {
                t.device_path == device_path
                    && t.zip_source_id.as_deref() == Some(source_id)
                    && matches!(
                        t.status,
                        TransferStatus::Queued | TransferStatus::InProgress
                    )
            });
            if in_flight {
                return;
            }
            let group = new_id();
            for (i, s) in songs.into_iter().enumerate() {
                let mut t = TransferTask::new(new_id(), s, device_path);
                t.zip_group_id = Some(group.clone());
                t.zip_source_id = (i == 0).then(|| source_id.to_string());
                st.push(t);
            }
            inner.start_engine(st, device_path);
        });
    }

    /// Cancels a task. Cancelling any zip-group member cancels the whole
    /// group: the bulk download is one request.
    pub fn cancel(&self, id: &str) {
        self.inner.mutate(|st| {
            let Some(task) = st.idx.get(id) else { return };
            if let Some(group) = task.zip_group_id.clone() {
                for m in st.idx.group_members(&group) {
                    if let Some(tok) = st.tokens.get(&m) {
                        tok.cancel();
                    }
                    if st.idx.status(&m) != Some(TransferStatus::Completed) {
                        st.set_status(&m, TransferStatus::Cancelled);
                    }
                }
                return;
            }
            if let Some(tok) = st.tokens.get(id) {
                tok.cancel();
            }
            st.set_status(id, TransferStatus::Cancelled);
        });
    }

    /// Cancels every queued and in-progress task, optionally on one device.
    pub fn cancel_all(&self, device_path: Option<&str>) {
        self.inner.mutate(|st| {
            for status in [TransferStatus::InProgress, TransferStatus::Queued] {
                for id in st.idx.ids_with_status(status) {
                    if device_path
                        .is_some_and(|d| st.idx.get(&id).is_some_and(|t| t.device_path != d))
                    {
                        continue;
                    }
                    if let Some(tok) = st.tokens.get(&id) {
                        tok.cancel();
                    }
                    st.set_status(&id, TransferStatus::Cancelled);
                }
            }
        });
    }

    /// Re-queues a failed task as a plain per-song download (zip tags are
    /// stripped, or a follower would never be picked).
    pub fn retry(&self, id: &str) {
        let inner = &self.inner;
        inner.mutate(|st| {
            let Some(device) = st
                .idx
                .get(id)
                .filter(|t| t.status == TransferStatus::Failed)
                .map(|t| t.device_path.clone())
            else {
                return;
            };
            st.update(id, requeue);
            inner.start_engine(st, &device);
        });
    }

    /// [`TransferService::retry`] for every failed task, optionally on one device.
    pub fn retry_all_failed(&self, device_path: Option<&str>) {
        let inner = &self.inner;
        inner.mutate(|st| {
            let mut devices = HashSet::new();
            for id in st.idx.ids_with_status(TransferStatus::Failed) {
                let Some(dev) = st.idx.get(&id).map(|t| t.device_path.clone()) else {
                    continue;
                };
                if device_path.is_some_and(|d| d != dev) {
                    continue;
                }
                st.update(&id, requeue);
                devices.insert(dev);
            }
            for d in devices {
                inner.start_engine(st, &d);
            }
        });
    }

    /// Pauses one device (or every device in the queue). In-flight downloads
    /// and the current device write finish; nothing new starts. In memory only.
    pub fn pause(&self, device_path: Option<&str>) {
        let mut st = self.inner.state.lock();
        match device_path {
            Some(d) => {
                st.paused.insert(d.to_string());
            }
            None => {
                let devices: Vec<String> = st.idx.iter().map(|t| t.device_path.clone()).collect();
                st.paused.extend(devices);
            }
        }
        drop(st);
        self.publish_paused();
    }

    /// Resumes one device (or every paused device).
    pub fn resume(&self, device_path: Option<&str>) {
        let inner = &self.inner;
        inner.mutate(|st| {
            let targets: Vec<String> = match device_path {
                Some(d) => vec![d.to_string()],
                None => st.paused.iter().cloned().collect(),
            };
            for d in targets {
                st.paused.remove(&d);
                if let Some(h) = st.engines.get(&d) {
                    h.resume.notify_one();
                }
                inner.start_engine(st, &d);
            }
        });
        self.publish_paused();
    }

    pub fn is_paused(&self, device_path: &str) -> bool {
        self.inner.is_paused(device_path)
    }

    pub fn paused_devices(&self) -> Vec<String> {
        let mut v: Vec<String> = self.inner.state.lock().paused.iter().cloned().collect();
        v.sort();
        v
    }

    /// Sorted paused device paths, re-emitted on every pause/resume.
    pub fn subscribe_paused(&self) -> watch::Receiver<Arc<Vec<String>>> {
        self.inner.paused_tx.subscribe()
    }

    fn publish_paused(&self) {
        self.inner
            .paused_tx
            .send_replace(Arc::new(self.paused_devices()));
    }

    /// Drops completed, cancelled and failed tasks.
    pub fn clear_completed(&self) {
        self.inner.mutate(|st| {
            for status in [
                TransferStatus::Completed,
                TransferStatus::Cancelled,
                TransferStatus::Failed,
            ] {
                for id in st.idx.ids_with_status(status) {
                    st.idx.remove(&id);
                    st.tasks_dirty = true;
                }
            }
        });
    }

    /// Current queue. Emits on id/status changes only (byte progress lives in
    /// [`TransferService::subscribe_progress`]).
    pub fn subscribe_tasks(&self) -> watch::Receiver<Arc<Vec<TransferTask>>> {
        self.inner.tasks_tx.subscribe()
    }

    /// task id → (bytes done, total), updated at most every 200 ms.
    pub fn subscribe_progress(&self) -> watch::Receiver<Arc<HashMap<String, (i64, i64)>>> {
        self.inner.progress_tx.subscribe()
    }

    /// Bumped (debounced 300 ms) after `.dapper.json` manifests are written.
    pub fn subscribe_manifest_revision(&self) -> watch::Receiver<u64> {
        self.inner.manifest_rev_tx.subscribe()
    }

    /// album id → status.
    pub fn queue_album_status(&self) -> HashMap<String, QueueItemStatus> {
        queue_status(&self.inner.state.lock().idx, |t| t.song.album_id.as_deref())
    }

    /// song id → status.
    pub fn queue_song_status(&self) -> HashMap<String, QueueItemStatus> {
        queue_status(&self.inner.state.lock().idx, |t| Some(t.song.id.as_str()))
    }

    /// Writes the queue file now; normally it is saved shortly after every
    /// id/status change.
    pub async fn flush(&self) {
        self.inner.persist().await;
    }

    /// Waits for pending `.dapper.json` manifest and playlist M3U writes,
    /// which complete after their tasks turn terminal.
    pub async fn idle(&self) {
        wait_tracker(&self.inner.effects).await;
    }

    /// App exit / reset: aborts all in-flight work without touching task
    /// statuses (in-progress tasks restore as queued next launch), waits for
    /// engines to stop and pending manifest/M3U writes, then saves the queue.
    pub async fn shutdown(&self) {
        self.inner.shutting_down.store(true, Ordering::Release);
        {
            let st = self.inner.state.lock();
            for tok in st.tokens.values() {
                tok.cancel();
            }
            for h in st.engines.values() {
                h.wake.notify_one();
                h.resume.notify_one();
            }
        }
        wait_tracker(&self.inner.engine_tasks).await;
        wait_tracker(&self.inner.effects).await;
        self.inner.persist().await;
    }

    /// Current queue (fresh, not throttled).
    pub fn tasks(&self) -> Arc<Vec<TransferTask>> {
        Arc::new(self.inner.state.lock().idx.snapshot())
    }

    /// Queued + in-progress tasks across all devices.
    pub fn active_count(&self) -> usize {
        let st = self.inner.state.lock();
        st.idx.ids_with_status(TransferStatus::Queued).len()
            + st.idx.ids_with_status(TransferStatus::InProgress).len()
    }

    /// Where downloads are staged before the single device write.
    pub fn staging_dir(&self) -> PathBuf {
        fsops::staging_dir(&self.inner.support)
    }
}

// Close-wait-reopen: `wait` only resolves on a closed tracker, and tasks
// spawned meanwhile are still tracked.
async fn wait_tracker(t: &TaskTracker) {
    t.close();
    t.wait().await;
    t.reopen();
}

fn requeue(t: &mut TransferTask) {
    t.status = TransferStatus::Queued;
    t.error_message = None;
    t.bytes_received = 0;
    t.total_bytes = 0;
    t.zip_group_id = None;
    t.zip_source_id = None;
}

fn queue_status<'a>(
    idx: &'a TaskIndex,
    key: impl Fn(&'a TransferTask) -> Option<&'a str>,
) -> HashMap<String, QueueItemStatus> {
    let mut out: HashMap<String, QueueItemStatus> = HashMap::new();
    for t in idx.iter() {
        let Some(id) = key(t) else { continue };
        match t.status {
            TransferStatus::InProgress => {
                out.insert(
                    id.to_string(),
                    QueueItemStatus {
                        active: true,
                        queued: false,
                    },
                );
            }
            TransferStatus::Queued => {
                out.entry(id.to_string()).or_insert(QueueItemStatus {
                    active: false,
                    queued: true,
                });
            }
            _ => {}
        }
    }
    out
}

fn new_id() -> String {
    uuid::Uuid::new_v4().to_string()
}
