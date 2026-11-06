//! Two-stage pipeline per device. Downloads run in parallel into an internal
//! staging dir (bounded by `transferConcurrency`), are post-processed there by
//! a shared pool, and a single sequential writer copies each file onto the
//! (slow) device exactly once, so concurrent writes never thrash the flash.

use std::collections::{HashMap, HashSet};
use std::path::{Path, PathBuf};
use std::sync::Arc;
use std::sync::atomic::Ordering;
use std::time::Instant;

use dapper_api::SubsonicApi;
use dapper_device::{FlacCleanOptions, ManifestSong};
use dapper_domain::{AppError, DeviceSettings, TransferStatus, TransferTask};
use futures::StreamExt;
use indexmap::IndexMap;
use tokio::sync::{Notify, mpsc};
use tokio::task::JoinSet;
use tokio_stream::wrappers::ReceiverStream;
use tokio_util::sync::CancellationToken;

use crate::fsops::{self, Extracted, PROGRESS_INTERVAL};
use crate::service::{Inner, POST_PROCESS_CONCURRENCY};

/// Downloaded-but-unwritten units allowed to wait for the writer before the
/// downloader stops pulling new work; bounds staging disk use when the
/// network outruns the device.
const STAGED_AHEAD: usize = 3;

/// A unit for the device writer: one staged song, or a downloaded album zip
/// awaiting sequential extraction onto the device.
pub(crate) enum Staged {
    Song {
        task: Box<TransferTask>,
        staging: PathBuf,
        target: String,
        folder: String,
        clean: FlacCleanOptions,
    },
    Zip {
        group_id: String,
        zip_path: PathBuf,
        members: Vec<TransferTask>,
    },
}

fn parent_str(path: &str) -> String {
    Path::new(path)
        .parent()
        .map(|p| p.to_string_lossy().into_owned())
        .unwrap_or_default()
}

fn clean_options(s: &DeviceSettings) -> FlacCleanOptions {
    FlacCleanOptions::new(s.auto_clean_metadata, s.auto_shrink_cover_art)
}

/// Waits until `notify` fires unless `ready()` already holds. The permit
/// semantics of `notify_one` make the check-then-wait race-free.
async fn wait_until(notify: &Notify, ready: impl Fn() -> bool) {
    while !ready() {
        notify.notified().await;
    }
}

/// Takes the first ready task for `device`, marks it in progress and
/// registers its cancel token, atomically with respect to `cancel`.
fn pick_next(
    inner: &Arc<Inner>,
    device: &str,
) -> Option<(TransferTask, Arc<SubsonicApi>, CancellationToken)> {
    if inner.shutting_down.load(Ordering::Acquire) {
        return None;
    }
    inner.mutate(|st| {
        if st.paused.contains(device) {
            return None;
        }
        let api = st.api.clone()?;
        let id = st.idx.first_ready(device)?.to_string();
        st.set_status(&id, TransferStatus::InProgress);
        let token = CancellationToken::new();
        st.tokens.insert(id.clone(), token.clone());
        Some((st.idx.get(&id)?.clone(), api, token))
    })
}

pub(crate) async fn run_engine(
    inner: Arc<Inner>,
    device: String,
    wake: Arc<Notify>,
    resume: Arc<Notify>,
) {
    loop {
        let (tx, rx) = mpsc::channel::<Staged>(STAGED_AHEAD);
        let writer = tokio::spawn(run_writer(
            inner.clone(),
            device.clone(),
            rx,
            wake.clone(),
            resume.clone(),
        ));
        let mut downloads: JoinSet<Option<Staged>> = JoinSet::new();
        let mut stages: JoinSet<()> = JoinSet::new();
        loop {
            let paused = inner.is_paused(&device);
            let has_work = inner.state.lock().has_work(&device)
                && !inner.shutting_down.load(Ordering::Acquire);
            if has_work
                && !paused
                && tx.capacity() > 0
                && downloads.len() < inner.transfer_concurrency().await
                && let Some((task, api, token)) = pick_next(&inner, &device)
            {
                let i = inner.clone();
                downloads.spawn(async move {
                    if task.is_zip_leader() {
                        download_zip(i, task, api, token).await
                    } else {
                        download_song(i, task, api, token).await
                    }
                });
                #[cfg(test)]
                inner.test_hooks.record_downloads(downloads.len());
                continue;
            }
            let idle =
                downloads.is_empty() && stages.is_empty() && tx.capacity() == tx.max_capacity();
            let stopping = inner.shutting_down.load(Ordering::Acquire);
            if idle && (stopping || (!paused && !has_work)) {
                break;
            }
            tokio::select! {
                Some(r) = downloads.join_next(), if !downloads.is_empty() => match r {
                    Ok(Some(staged)) => { stages.spawn(stage(inner.clone(), staged, tx.clone())); }
                    Ok(None) => {}
                    Err(e) => tracing::error!("transfer download task failed: {e}"),
                },
                Some(r) = stages.join_next(), if !stages.is_empty() => {
                    if let Err(e) = r {
                        tracing::error!("transfer staging task failed: {e}");
                    }
                }
                _ = wake.notified() => {}
            }
        }
        // The writer drains what is staged; only then may another writer for
        // this device exist, so the device never sees two writers.
        drop(tx);
        if let Err(e) = writer.await {
            tracing::error!("transfer writer failed for {device}: {e}");
        }
        let mut st = inner.state.lock();
        if inner.shutting_down.load(Ordering::Acquire) || !st.has_work(&device) {
            st.engines.remove(&device);
            return;
        }
    }
}

async fn run_writer(
    inner: Arc<Inner>,
    device: String,
    mut rx: mpsc::Receiver<Staged>,
    wake: Arc<Notify>,
    resume: Arc<Notify>,
) {
    while let Some(unit) = rx.recv().await {
        // Backlog shrank: the downloader may stage more.
        wake.notify_one();
        wait_until(&resume, || {
            !inner.is_paused(&device) || inner.shutting_down.load(Ordering::Acquire)
        })
        .await;
        if inner.shutting_down.load(Ordering::Acquire) {
            // Their tasks stay in progress and restore as queued next launch.
            discard(&unit);
            if let Staged::Zip { members, .. } = &unit {
                inner.clear_progress(members.iter().map(|t| &t.id));
            }
            continue;
        }
        match unit {
            Staged::Song {
                task,
                staging,
                target,
                folder,
                clean: _,
            } => write_song(&inner, &task, &staging, &target, folder).await,
            Staged::Zip {
                group_id,
                zip_path,
                members,
            } => write_zip(&inner, &group_id, &zip_path, &members).await,
        }
        wake.notify_one();
    }
}

// ── Stage 1: per-song download ──────────────────────────────────────────────

async fn download_song(
    inner: Arc<Inner>,
    task: TransferTask,
    api: Arc<SubsonicApi>,
    token: CancellationToken,
) -> Option<Staged> {
    let id = task.id.clone();
    let settings = inner.device_settings(&task.device_path).await;
    let target = dapper_paths::build_song_path(&task.song, &settings);
    let folder = parent_str(&target);

    if !settings.overwrite_existing && tokio::fs::try_exists(&target).await.unwrap_or(false) {
        // Already on device: record it and finish without a download.
        inner.remove_tokens([&id]);
        let expected = inner.state.lock().expected_count(&folder);
        let entry = ManifestSong::for_song(&task.song, Some(dapper_paths::basename(&target)));
        inner.append_manifest(folder, vec![entry], expected);
        inner.mark_completed(&id);
        return None;
    }

    let staging = fsops::staging_path_for(&inner.support, &id, &target);
    let result = async {
        tokio::fs::create_dir_all(fsops::staging_dir(&inner.support)).await?;
        // Built at execution time so transcoding changes made after enqueue
        // apply to later tasks.
        let url = api.transfer_uri(
            &task.song.id,
            settings.transcode_format.api_name(),
            settings.transcode_max_bit_rate.map(|b| b as i32),
        );
        // Transcoded responses often lack Content-Length; the estimate keeps
        // the bar moving.
        let estimated = dapper_paths::estimate_total_bytes(&task.song, &settings);
        let mut last: Option<Instant> = None;
        let ids = [id.clone()];
        let on_progress = |received: u64, total: Option<u64>| {
            let total = total.filter(|t| *t > 0).map_or(estimated, |t| t as i64);
            if total <= 0 || last.is_some_and(|l| l.elapsed() < PROGRESS_INTERVAL) {
                return;
            }
            last = Some(Instant::now());
            inner.set_progress(&ids, ((received as i64).min(total), total));
        };
        dapper_api::download_to_file(&inner.http, url.as_str(), &staging, on_progress, token).await
    }
    .await;
    inner.remove_tokens([&id]);
    inner.clear_progress([&id]);
    match result {
        Ok(_) => Some(Staged::Song {
            task: Box::new(task),
            staging,
            target,
            folder,
            clean: clean_options(&settings),
        }),
        Err(e) => {
            fsops::remove_quietly(&staging);
            if e != AppError::Cancelled {
                inner.fail(&id, fsops::failure_message(e.to_string()));
            }
            None
        }
    }
}

/// Post-processes a staged song on the internal disk (bounded pool), then
/// queues it for the writer; waits while the writer backlog is full.
async fn stage(inner: Arc<Inner>, staged: Staged, tx: mpsc::Sender<Staged>) {
    if let Staged::Song {
        task,
        staging,
        clean,
        ..
    } = &staged
    {
        let opts = *clean;
        if opts.sanitize_tags || opts.shrink_picture {
            let _permit = inner.post_sem.acquire().await;
            let path = staging.clone();
            match tokio::task::spawn_blocking(move || dapper_device::clean_flac_file(&path, &opts))
                .await
            {
                Ok(Ok(_)) => {}
                Ok(Err(e)) => {
                    tracing::warn!("staging post-process failed for {}: {e}", staging.display())
                }
                Err(e) => tracing::warn!(
                    "staging post-process panicked for {}: {e}",
                    staging.display()
                ),
            }
        }
        if !inner.is_live(&task.id) {
            fsops::remove_quietly(staging);
            return;
        }
    }
    if let Err(mpsc::error::SendError(unit)) = tx.send(staged).await {
        discard(&unit);
    }
}

fn discard(unit: &Staged) {
    match unit {
        Staged::Song { staging, .. } => fsops::remove_quietly(staging),
        Staged::Zip { zip_path, .. } => fsops::remove_quietly(zip_path),
    }
}

// ── Stage 2: per-song device write ──────────────────────────────────────────

async fn write_song(
    inner: &Arc<Inner>,
    task: &TransferTask,
    staging: &Path,
    target: &str,
    folder: String,
) {
    let id = task.id.clone();
    if !inner.is_live(&id) {
        fsops::remove_quietly(staging);
        return;
    }
    #[cfg(test)]
    inner.test_hooks.write_delay().await;
    let (src, dst) = (staging.to_path_buf(), PathBuf::from(target));
    let progress_inner = inner.clone();
    let ids = [id.clone()];
    let res = tokio::task::spawn_blocking(move || {
        let r = fsops::copy_to_device(&src, &dst, |done, total| {
            progress_inner.set_progress(&ids, (done, total))
        });
        if r.is_err() {
            // Leave no half-written file on the device.
            fsops::remove_quietly(&dst);
        }
        r
    })
    .await
    .unwrap_or_else(|e| Err(std::io::Error::other(e)));
    match res {
        Ok(()) => {
            let expected = inner.state.lock().expected_count(&folder);
            let entry = ManifestSong::for_song(&task.song, Some(dapper_paths::basename(target)));
            inner.append_manifest(folder, vec![entry], expected);
            inner.mark_completed(&id);
        }
        Err(e) => {
            let msg = if fsops::is_permission_error(&e) {
                "permission_denied".to_string()
            } else {
                e.to_string()
            };
            inner.fail(&id, msg);
        }
    }
    fsops::remove_quietly(staging);
    inner.clear_progress([&id]);
}

// ── Zip groups ──────────────────────────────────────────────────────────────

/// Stage 1 for a zip group: transcoding fallback, all-present short-circuit,
/// free-space precheck, then downloads the album zip into `<support>/tmp`.
/// Every member's progress mirrors the leader's download.
async fn download_zip(
    inner: Arc<Inner>,
    leader: TransferTask,
    api: Arc<SubsonicApi>,
    token: CancellationToken,
) -> Option<Staged> {
    let group_id = leader.zip_group_id.clone()?;
    let source_id = leader.zip_source_id.clone()?;
    let device = leader.device_path.clone();
    let settings = inner.device_settings(&device).await;

    // The zip endpoint only serves originals: transcoded modes fall back to
    // per-song tasks, which the engine picks up next.
    if settings.is_transcoding() {
        inner.mutate(|st| {
            st.tokens.remove(&leader.id);
            for id in st.idx.group_members(&group_id) {
                st.update(&id, |t| {
                    t.zip_group_id = None;
                    t.zip_source_id = None;
                    if t.status == TransferStatus::InProgress {
                        t.status = TransferStatus::Queued;
                    }
                });
            }
        });
        return None;
    }

    let members: Vec<TransferTask> = {
        let st = inner.state.lock();
        st.idx
            .group_members(&group_id)
            .iter()
            .filter_map(|id| st.idx.get(id).cloned())
            .collect()
    };
    let member_ids: Vec<String> = members.iter().map(|t| t.id.clone()).collect();

    // Every file already at its path: skip the download entirely. Checks the
    // files themselves so a stale manifest can't fake it.
    let all_present = !settings.overwrite_existing && !members.is_empty() && {
        let (songs, s) = (
            members.iter().map(|t| t.song.clone()).collect::<Vec<_>>(),
            settings.clone(),
        );
        tokio::task::spawn_blocking(move || {
            songs
                .iter()
                .all(|song| dapper_device::song_file_exists_on_device(song, &s))
        })
        .await
        .unwrap_or(false)
    };
    if all_present {
        inner.mutate(|st| {
            st.tokens.remove(&leader.id);
            for id in &member_ids {
                if st.idx.status(id) != Some(TransferStatus::Completed) {
                    st.set_status(id, TransferStatus::Completed);
                }
            }
        });
        return None;
    }

    inner.mutate(|st| {
        for id in &member_ids {
            if st.idx.status(id) == Some(TransferStatus::Queued) {
                st.set_status(id, TransferStatus::InProgress);
            }
        }
    });

    let tmp_zip = fsops::tmp_dir(&inner.support).join(format!("zip_{group_id}.zip"));
    let estimated: i64 = members.iter().map(|t| t.song.size.unwrap_or(0)).sum();
    let result: Result<(), String> = async {
        tokio::fs::create_dir_all(fsops::tmp_dir(&inner.support))
            .await
            .map_err(|e| e.to_string())?;
        // Needs room for the zip in app data AND the extracted files on the
        // device: require ~1.1× the summed sizes on each volume up front.
        // Unknown free space skips the check.
        if estimated > 0 {
            let (support, dev) = (inner.support.clone(), PathBuf::from(&device));
            let (tmp_free, dev_free) = tokio::task::spawn_blocking(move || {
                (
                    dapper_platform::free_bytes_at(&support),
                    dapper_platform::free_bytes_at(&dev),
                )
            })
            .await
            .unwrap_or((None, None));
            if token.is_cancelled() {
                return Err(AppError::Cancelled.to_string());
            }
            let required = estimated * 11 / 10;
            let fmt = dapper_paths::format_bytes;
            if let Some(free) = tmp_free.map(|f| f as i64).filter(|f| *f < required) {
                return Err(format!(
                    "Not enough free space in app data for {} zip ({} available)",
                    fmt(required),
                    fmt(free)
                ));
            }
            if let Some(free) = dev_free.map(|f| f as i64).filter(|f| *f < required) {
                return Err(format!(
                    "Not enough free space on device for {} ({} available)",
                    fmt(required),
                    fmt(free)
                ));
            }
        }
        let url = api.zip_uri(&source_id);
        let mut last: Option<Instant> = None;
        let on_progress = |received: u64, total: Option<u64>| {
            let total = total.filter(|t| *t > 0).map_or(estimated, |t| t as i64);
            if total <= 0 || last.is_some_and(|l| l.elapsed() < PROGRESS_INTERVAL) {
                return;
            }
            last = Some(Instant::now());
            inner.set_progress(&member_ids, ((received as i64).min(total), total));
        };
        dapper_api::download_to_file(
            &inner.http,
            url.as_str(),
            &tmp_zip,
            on_progress,
            token.clone(),
        )
        .await
        .map(drop)
        .map_err(|e| {
            if e == AppError::Cancelled {
                e.to_string()
            } else {
                e.message()
            }
        })
    }
    .await;
    inner.remove_tokens([&leader.id]);

    match result {
        Ok(()) => Some(Staged::Zip {
            group_id,
            zip_path: tmp_zip,
            members,
        }),
        Err(msg) => {
            if token.is_cancelled() {
                if !inner.shutting_down.load(Ordering::Acquire) {
                    inner.cancel_group_in_flight(&group_id);
                }
            } else {
                inner.fail_group(&group_id, &msg);
            }
            inner.clear_progress(&member_ids);
            fsops::remove_quietly(&tmp_zip);
            None
        }
    }
}

/// Post-processes one staged zip entry under the shared pool.
async fn post_process_extracted(
    inner: Arc<Inner>,
    item: Extracted,
    opts: FlacCleanOptions,
) -> Extracted {
    if let Extracted::Staged { staging, .. } = &item
        && (opts.sanitize_tags || opts.shrink_picture)
    {
        let _permit = inner.post_sem.acquire().await;
        let path = staging.clone();
        match tokio::task::spawn_blocking(move || dapper_device::clean_flac_file(&path, &opts))
            .await
        {
            Ok(Ok(_)) => {}
            Ok(Err(e)) => tracing::warn!("zip post-process failed for {}: {e}", staging.display()),
            Err(e) => tracing::warn!("zip post-process panicked for {}: {e}", staging.display()),
        }
    }
    item
}

/// Stage 2 for a zip group: entries are streamed from the zip to local
/// staging files (blocking thread), post-processed there, then copied onto
/// the device one at a time. Members flip to completed as their files land;
/// members without a usable entry fail. Always scrubs mirrored progress and
/// deletes the zip.
async fn write_zip(inner: &Arc<Inner>, group_id: &str, zip_path: &Path, members: &[TransferTask]) {
    let ids: Vec<String> = members.iter().map(|t| t.id.clone()).collect();
    if !ids.iter().any(|id| inner.is_live(id)) {
        inner.clear_progress(&ids);
        fsops::remove_quietly(zip_path);
        return;
    }
    let Some(device) = members.first().map(|t| t.device_path.clone()) else {
        return;
    };
    let settings = inner.device_settings(&device).await;
    let token = CancellationToken::new();
    {
        let mut st = inner.state.lock();
        for id in &ids {
            st.tokens.insert(id.clone(), token.clone());
        }
    }

    let (etx, erx) = mpsc::channel::<Extracted>(STAGED_AHEAD);
    let extractor = {
        let (zip, songs, task_ids) = (
            zip_path.to_path_buf(),
            members.iter().map(|t| t.song.clone()).collect::<Vec<_>>(),
            ids.clone(),
        );
        let (s, support, tok) = (settings.clone(), inner.support.clone(), token.clone());
        tokio::task::spawn_blocking(move || {
            fsops::extract_zip_entries(&zip, &songs, &task_ids, &s, &support, etx, tok)
        })
    };

    let opts = clean_options(&settings);
    let pp_inner = inner.clone();
    let mut processed = ReceiverStream::new(erx)
        .map(move |item| post_process_extracted(pp_inner.clone(), item, opts))
        .buffered(POST_PROCESS_CONCURRENCY);

    let mut landed: HashSet<usize> = HashSet::new();
    let mut failures: HashMap<usize, String> = HashMap::new();
    let mut by_folder: IndexMap<String, (Vec<ManifestSong>, Option<i64>)> = IndexMap::new();
    let mut record = |idx: usize, target: &str, expected: Option<i64>| {
        landed.insert(idx);
        let folder = by_folder.entry(parent_str(target)).or_default();
        folder.0.push(ManifestSong::for_song(
            &members[idx].song,
            Some(dapper_paths::basename(target)),
        ));
        folder.1 = expected;
        inner.mark_completed(&ids[idx]);
        inner.clear_progress([&ids[idx]]);
    };

    while let Some(item) = processed.next().await {
        match item {
            Extracted::Staged {
                song,
                entry,
                staging,
                target,
                expected,
            } => {
                if token.is_cancelled() {
                    fsops::remove_quietly(&staging);
                    continue;
                }
                #[cfg(test)]
                inner.test_hooks.write_delay().await;
                let (src, dst) = (staging.clone(), PathBuf::from(&target));
                let res = tokio::task::spawn_blocking(move || {
                    let r = fsops::copy_to_device(&src, &dst, |_, _| {});
                    if r.is_err() {
                        fsops::remove_quietly(&dst);
                    }
                    r
                })
                .await
                .unwrap_or_else(|e| Err(std::io::Error::other(e)));
                fsops::remove_quietly(&staging);
                match res {
                    Ok(()) => record(song, &target, expected),
                    Err(e) => {
                        failures.insert(song, format!("write failed for {entry}: {e}"));
                    }
                }
            }
            Extracted::Existing {
                song,
                target,
                expected,
            } => record(song, &target, expected),
            Extracted::Failed { song, reason } => {
                failures.insert(song, reason);
            }
        }
    }
    drop(processed);
    let extract_result = extractor.await.unwrap_or_else(|e| Err(e.to_string()));
    inner.remove_tokens(&ids);

    // Manifests cover every file that landed, even if the group was then
    // cancelled or the archive failed part-way: those rows are completed.
    for (folder, (entries, expected)) in by_folder {
        inner.append_manifest(folder, entries, expected);
    }

    let cancelled = ids
        .iter()
        .any(|id| inner.state.lock().idx.status(id) == Some(TransferStatus::Cancelled));
    if inner.shutting_down.load(Ordering::Acquire) {
        // Statuses stay as they are; unfinished members restore as queued.
    } else if cancelled {
        inner.cancel_group_in_flight(group_id);
    } else if let Err(msg) = extract_result {
        inner.fail_group(group_id, &msg);
    } else {
        inner.mutate(|st| {
            for (i, id) in ids.iter().enumerate() {
                if landed.contains(&i) || !st.is_live(id) {
                    continue;
                }
                let msg = failures
                    .remove(&i)
                    .unwrap_or_else(|| "Not found in album zip".into());
                st.update(id, |t| {
                    t.status = TransferStatus::Failed;
                    t.error_message = Some(msg);
                });
            }
        });
    }
    inner.clear_progress(&ids);
    fsops::remove_quietly(zip_path);
}
