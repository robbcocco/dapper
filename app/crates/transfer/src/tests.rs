use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::sync::Arc;
use std::sync::atomic::{AtomicU64, AtomicUsize, Ordering};
use std::time::Duration;

use dapper_api::{SubsonicApi, SubsonicClient};
use dapper_device::AlbumManifest;
use dapper_domain::{AppSettings, DeviceSettings, Playlist, Song, TransferStatus, TransferTask};
use dapper_store::Store;
use tempfile::TempDir;
use wiremock::matchers::{method, path, query_param};
use wiremock::{Mock, MockServer, ResponseTemplate};

use crate::fsops::DEVICE_WRITES;
use crate::{TransferDeps, TransferService};

/// Test-only instrumentation inside the engine.
#[derive(Default)]
pub(crate) struct Hooks {
    max_downloads: AtomicUsize,
    write_delay_ms: AtomicU64,
}

impl Hooks {
    pub fn record_downloads(&self, n: usize) {
        self.max_downloads.fetch_max(n, Ordering::Relaxed);
    }

    pub async fn write_delay(&self) {
        let ms = self.write_delay_ms.load(Ordering::Relaxed);
        if ms > 0 {
            tokio::time::sleep(Duration::from_millis(ms)).await;
        }
    }
}

struct Env {
    _dir: TempDir,
    support: PathBuf,
    device: String,
    store: Arc<Store>,
    server: MockServer,
    svc: TransferService,
}

impl Env {
    async fn new() -> Self {
        let dir = tempfile::tempdir().unwrap();
        let support = dir.path().join("support");
        let device = dir.path().join("device");
        std::fs::create_dir_all(&device).unwrap();
        let store = Arc::new(Store::open(&support).unwrap());
        let server = MockServer::start().await;
        let svc = service(&support, &store);
        Env {
            _dir: dir,
            support,
            device: device.to_string_lossy().into_owned(),
            store,
            server,
            svc,
        }
    }

    fn api(&self) -> Arc<SubsonicApi> {
        Arc::new(SubsonicApi::new(
            SubsonicClient::new(&self.server.uri(), "u", "p").unwrap(),
        ))
    }

    fn connect(&self) {
        self.svc.set_api(Some(self.api()));
    }

    fn settings(&self) -> DeviceSettings {
        DeviceSettings::new(self.device.clone())
    }

    fn target(&self, song: &Song) -> PathBuf {
        PathBuf::from(dapper_paths::build_song_path(song, &self.settings()))
    }

    async fn mount_song(&self, song: &Song, body: &[u8], delay_ms: u64) {
        Mock::given(method("GET"))
            .and(path("/rest/download"))
            .and(query_param("id", song.id.as_str()))
            .respond_with(
                ResponseTemplate::new(200)
                    .set_body_bytes(body.to_vec())
                    .set_delay(Duration::from_millis(delay_ms)),
            )
            .mount(&self.server)
            .await;
    }

    async fn requests_for(&self, id: &str) -> usize {
        let needle = format!("id={id}&");
        self.server
            .received_requests()
            .await
            .unwrap_or_default()
            .iter()
            .filter(|r| {
                r.url
                    .query()
                    .is_some_and(|q| format!("{q}&").contains(&needle))
            })
            .count()
    }

    async fn wait_tasks(
        &self,
        what: &str,
        pred: impl Fn(&[TransferTask]) -> bool,
    ) -> Arc<Vec<TransferTask>> {
        for _ in 0..500 {
            let tasks = self.svc.tasks();
            if pred(&tasks) {
                return tasks;
            }
            tokio::time::sleep(Duration::from_millis(20)).await;
        }
        panic!("timed out waiting for {what}: {:#?}", self.svc.tasks());
    }

    async fn wait_all(&self, status: TransferStatus) -> Arc<Vec<TransferTask>> {
        self.wait_tasks(&format!("all {status:?}"), |ts| {
            !ts.is_empty() && ts.iter().all(|t| t.status == status)
        })
        .await
    }
}

fn service(support: &Path, store: &Arc<Store>) -> TransferService {
    TransferService::new(TransferDeps {
        support_dir: support.to_path_buf(),
        store: store.clone(),
        http: reqwest::Client::new(),
    })
}

fn song(id: &str, track: i32, title: &str) -> Song {
    Song {
        id: id.into(),
        title: title.into(),
        album_id: Some("al1".into()),
        album: Some("Album".into()),
        artist: Some("Artist".into()),
        album_artist: Some("Artist".into()),
        track: Some(track),
        suffix: Some("mp3".into()),
        size: Some(1000),
        duration: Some(120),
        ..Default::default()
    }
}

fn body(seed: u8, len: usize) -> Vec<u8> {
    (0..len)
        .map(|i| (i as u8).wrapping_mul(31).wrapping_add(seed))
        .collect()
}

async fn wait_for(what: &str, cond: impl Fn() -> bool) {
    for _ in 0..500 {
        if cond() {
            return;
        }
        tokio::time::sleep(Duration::from_millis(20)).await;
    }
    panic!("timed out waiting for {what}");
}

fn manifest(folder: &Path) -> Option<AlbumManifest> {
    AlbumManifest::parse(&std::fs::read(folder.join(dapper_device::MANIFEST_FILENAME)).ok()?)
}

fn writes(p: &Path) -> u32 {
    DEVICE_WRITES.lock().get(p).copied().unwrap_or(0)
}

fn dir_files(dir: &Path) -> Vec<String> {
    std::fs::read_dir(dir)
        .map(|rd| {
            rd.flatten()
                .map(|e| e.file_name().to_string_lossy().into_owned())
                .collect()
        })
        .unwrap_or_default()
}

fn crc32(data: &[u8]) -> u32 {
    let mut crc = !0u32;
    for &b in data {
        crc ^= u32::from(b);
        for _ in 0..8 {
            crc = if crc & 1 != 0 {
                (crc >> 1) ^ 0xEDB8_8320
            } else {
                crc >> 1
            };
        }
    }
    !crc
}

/// A zip shaped like Navidrome's: STORED entries with general-purpose flag
/// bit 3, zero sizes/CRC in the local headers and trailing data descriptors.
fn navidrome_zip(entries: &[(&str, &[u8])]) -> Vec<u8> {
    let mut out = Vec::new();
    let mut central = Vec::new();
    for (name, data) in entries {
        let offset = out.len() as u32;
        let (crc, len) = (crc32(data), data.len() as u32);
        out.extend_from_slice(&0x0403_4b50u32.to_le_bytes());
        for v in [20u16, 0x0008, 0, 0, 0x21] {
            out.extend_from_slice(&v.to_le_bytes());
        }
        out.extend_from_slice(&[0u8; 12]);
        out.extend_from_slice(&(name.len() as u16).to_le_bytes());
        out.extend_from_slice(&0u16.to_le_bytes());
        out.extend_from_slice(name.as_bytes());
        out.extend_from_slice(data);
        for v in [0x0807_4b50u32, crc, len, len] {
            out.extend_from_slice(&v.to_le_bytes());
        }

        central.extend_from_slice(&0x0201_4b50u32.to_le_bytes());
        for v in [20u16, 20, 0x0008, 0, 0, 0x21] {
            central.extend_from_slice(&v.to_le_bytes());
        }
        for v in [crc, len, len] {
            central.extend_from_slice(&v.to_le_bytes());
        }
        for v in [name.len() as u16, 0, 0, 0, 0] {
            central.extend_from_slice(&v.to_le_bytes());
        }
        central.extend_from_slice(&0u32.to_le_bytes());
        central.extend_from_slice(&offset.to_le_bytes());
        central.extend_from_slice(name.as_bytes());
    }
    let cd_offset = out.len() as u32;
    let cd_size = central.len() as u32;
    out.extend_from_slice(&central);
    out.extend_from_slice(&0x0605_4b50u32.to_le_bytes());
    for v in [0u16, 0, entries.len() as u16, entries.len() as u16] {
        out.extend_from_slice(&v.to_le_bytes());
    }
    out.extend_from_slice(&cd_size.to_le_bytes());
    out.extend_from_slice(&cd_offset.to_le_bytes());
    out.extend_from_slice(&0u16.to_le_bytes());
    out
}

async fn mount_zip(env: &Env, source: &str, zip: Vec<u8>, delay_ms: u64) {
    Mock::given(method("GET"))
        .and(path("/rest/download"))
        .and(query_param("id", source))
        .respond_with(
            ResponseTemplate::new(200)
                .set_body_bytes(zip)
                .set_delay(Duration::from_millis(delay_ms)),
        )
        .mount(&env.server)
        .await;
}

#[tokio::test]
async fn per_song_happy_path_writes_once_and_records_manifest() {
    let env = Env::new().await;
    let songs = vec![song("s1", 1, "One"), song("s2", 2, "Two")];
    let bodies = [body(1, 300_000), body(2, 150_000)];
    for (s, b) in songs.iter().zip(&bodies) {
        env.mount_song(s, b, 0).await;
    }
    let folder = env.target(&songs[0]).parent().unwrap().to_path_buf();
    let mut rev = env.svc.subscribe_manifest_revision();
    env.connect();
    env.svc.enqueue(
        songs.clone(),
        &env.device,
        Some(HashMap::from([(folder.to_string_lossy().into_owned(), 12)])),
    );

    env.wait_all(TransferStatus::Completed).await;
    for (s, b) in songs.iter().zip(&bodies) {
        let target = env.target(s);
        assert_eq!(&std::fs::read(&target).unwrap(), b);
        assert_eq!(
            writes(&target),
            1,
            "one device write for {}",
            target.display()
        );
    }
    wait_for("manifest", || {
        manifest(&folder).is_some_and(|m| m.songs.len() == 2)
    })
    .await;
    let m = manifest(&folder).unwrap();
    assert_eq!(m.expected_song_count, Some(12));
    let s1 = m.songs.iter().find(|s| s.id == "s1").unwrap();
    assert_eq!(
        s1.filename.as_deref(),
        Some(dapper_paths::basename(&env.target(&songs[0]).to_string_lossy()).as_str())
    );
    assert_eq!(s1.artist.as_deref(), Some("Artist"));
    assert_eq!(s1.album.as_deref(), Some("Album"));
    tokio::time::timeout(Duration::from_secs(5), rev.changed())
        .await
        .unwrap()
        .unwrap();
    assert!(dir_files(&env.support.join("staging")).is_empty());
    assert!(env.svc.queue_song_status().is_empty());
}

#[tokio::test]
async fn zip_group_completes_members_progressively() {
    let env = Env::new().await;
    let songs = vec![
        song("z1", 1, "One"),
        song("z2", 2, "Two"),
        song("z3", 3, "Three"),
    ];
    let datas = [body(10, 4000), body(11, 5000), body(12, 6000)];
    let zip = navidrome_zip(&[
        ("Artist/Album/01 - One.mp3", &datas[0]),
        ("Artist/Album/02 - Two.mp3", &datas[1]),
        ("Artist/Album/03 - Three.mp3", &datas[2]),
    ]);
    mount_zip(&env, "al1", zip, 0).await;
    env.svc
        .inner()
        .test_hooks
        .write_delay_ms
        .store(250, Ordering::Relaxed);

    let mut rx = env.svc.subscribe_tasks();
    env.connect();
    env.svc.enqueue_zip_group("al1", songs.clone(), &env.device);
    // Duplicate clicks while in flight are ignored.
    env.svc.enqueue_zip_group("al1", songs.clone(), &env.device);
    assert_eq!(env.svc.tasks().len(), 3);

    let mut saw_partial = false;
    tokio::time::timeout(Duration::from_secs(10), async {
        loop {
            rx.changed().await.unwrap();
            let snap = rx.borrow_and_update().clone();
            let done = snap
                .iter()
                .filter(|t| t.status == TransferStatus::Completed)
                .count();
            if done > 0 && done < 3 && snap.iter().any(|t| t.status == TransferStatus::InProgress) {
                saw_partial = true;
            }
            if done == 3 {
                break;
            }
        }
    })
    .await
    .expect("zip group completes");
    assert!(
        saw_partial,
        "members should flip to completed as their files land"
    );

    for (s, d) in songs.iter().zip(&datas) {
        let target = env.target(s);
        assert_eq!(&std::fs::read(&target).unwrap(), d);
        assert_eq!(writes(&target), 1);
    }
    assert_eq!(env.requests_for("al1").await, 1);
    let folder = env.target(&songs[0]).parent().unwrap().to_path_buf();
    wait_for("zip manifest", || {
        manifest(&folder).is_some_and(|m| m.songs.len() == 3)
    })
    .await;
    assert_eq!(manifest(&folder).unwrap().expected_song_count, Some(3));
    wait_for("tmp cleanup", || {
        dir_files(&env.support.join("tmp")).is_empty()
    })
    .await;
    assert!(dir_files(&env.support.join("staging")).is_empty());
}

#[tokio::test]
async fn zip_member_without_entry_fails() {
    let env = Env::new().await;
    let songs = vec![
        song("u1", 1, "One"),
        song("u2", 2, "Two"),
        song("u3", 3, "Three"),
    ];
    let zip = navidrome_zip(&[
        ("Artist/Album/01 - One.mp3", b"one"),
        ("Artist/Album/02 - Two.mp3", b"two"),
        ("Artist/Album/cover.jpg", b"jpeg"),
    ]);
    mount_zip(&env, "al1", zip, 0).await;
    env.connect();
    env.svc.enqueue_zip_group("al1", songs.clone(), &env.device);

    let tasks = env
        .wait_tasks("zip settled", |ts| {
            ts.iter()
                .all(|t| matches!(t.status, TransferStatus::Completed | TransferStatus::Failed))
        })
        .await;
    let by_song: HashMap<&str, &TransferTask> =
        tasks.iter().map(|t| (t.song.id.as_str(), t)).collect();
    assert_eq!(by_song["u1"].status, TransferStatus::Completed);
    assert_eq!(by_song["u2"].status, TransferStatus::Completed);
    assert_eq!(by_song["u3"].status, TransferStatus::Failed);
    assert_eq!(
        by_song["u3"].error_message.as_deref(),
        Some("Not found in album zip")
    );
    assert!(!env.target(&songs[2]).exists());

    // Retry strips the zip tagging so the member runs as a per-song task.
    env.mount_song(&songs[2], b"three", 0).await;
    env.svc.retry(&by_song["u3"].id);
    env.wait_all(TransferStatus::Completed).await;
    let retried = env
        .svc
        .tasks()
        .iter()
        .find(|t| t.song.id == "u3")
        .cloned()
        .unwrap();
    assert_eq!(retried.zip_group_id, None);
    assert_eq!(std::fs::read(env.target(&songs[2])).unwrap(), b"three");
}

#[tokio::test]
async fn existing_files_are_skipped_but_recorded() {
    let env = Env::new().await;
    let s = song("e1", 1, "One");
    let target = env.target(&s);
    std::fs::create_dir_all(target.parent().unwrap()).unwrap();
    std::fs::write(&target, b"old").unwrap();
    env.mount_song(&s, b"new", 0).await;
    env.connect();
    env.svc.enqueue(vec![s.clone()], &env.device, None);
    env.wait_all(TransferStatus::Completed).await;
    assert_eq!(std::fs::read(&target).unwrap(), b"old");
    assert_eq!(env.requests_for("e1").await, 0);
    let folder = target.parent().unwrap().to_path_buf();
    wait_for("manifest", || {
        manifest(&folder).is_some_and(|m| m.songs.iter().any(|x| x.id == "e1"))
    })
    .await;

    // A zip group whose files are all present short-circuits too.
    env.svc.clear_completed();
    assert!(env.svc.tasks().is_empty());
    env.svc
        .enqueue_zip_group("al1", vec![s.clone()], &env.device);
    env.wait_all(TransferStatus::Completed).await;
    assert_eq!(env.requests_for("al1").await, 0);
}

#[tokio::test]
async fn cancelling_a_member_cancels_the_zip_download() {
    let env = Env::new().await;
    let songs = vec![song("c1", 1, "One"), song("c2", 2, "Two")];
    let zip = navidrome_zip(&[("01 - One.mp3", b"1"), ("02 - Two.mp3", b"2")]);
    mount_zip(&env, "al1", zip, 5_000).await;
    env.connect();
    env.svc.enqueue_zip_group("al1", songs.clone(), &env.device);
    let tasks = env.wait_all(TransferStatus::InProgress).await;
    for _ in 0..250 {
        if env.requests_for("al1").await > 0 {
            break;
        }
        tokio::time::sleep(Duration::from_millis(20)).await;
    }
    env.svc.cancel(&tasks[1].id);
    env.wait_all(TransferStatus::Cancelled).await;
    wait_for("engine idle", || {
        env.svc.inner().state.lock().engines.is_empty()
    })
    .await;
    assert!(dir_files(&env.support.join("tmp")).is_empty());
    assert!(songs.iter().all(|s| !env.target(s).exists()));
    assert!(env.svc.subscribe_progress().borrow().is_empty());
}

#[tokio::test]
async fn failed_task_can_be_retried() {
    let env = Env::new().await;
    let s = song("r1", 1, "One");
    Mock::given(method("GET"))
        .and(path("/rest/download"))
        .and(query_param("id", "r1"))
        .respond_with(ResponseTemplate::new(500))
        .up_to_n_times(1)
        .with_priority(1)
        .mount(&env.server)
        .await;
    env.mount_song(&s, b"payload", 0).await;
    env.connect();
    env.svc.enqueue(vec![s.clone()], &env.device, None);
    let tasks = env.wait_all(TransferStatus::Failed).await;
    assert_eq!(
        tasks[0].error_message.as_deref(),
        Some("Download failed: HTTP 500")
    );
    assert!(dir_files(&env.support.join("staging")).is_empty());

    env.svc.retry_all_failed(Some(&env.device));
    let tasks = env.wait_all(TransferStatus::Completed).await;
    assert_eq!(tasks[0].error_message, None);
    assert_eq!(std::fs::read(env.target(&s)).unwrap(), b"payload");
}

#[tokio::test]
async fn pause_holds_new_work_until_resume() {
    let env = Env::new().await;
    let songs = vec![song("p1", 1, "One"), song("p2", 2, "Two")];
    for s in &songs {
        env.mount_song(s, s.id.as_bytes(), 0).await;
    }
    let mut paused_rx = env.svc.subscribe_paused();
    env.svc.pause(Some(&env.device));
    assert!(env.svc.is_paused(&env.device));
    assert_eq!(
        *paused_rx.borrow_and_update().clone(),
        vec![env.device.clone()]
    );
    env.connect();
    env.svc.enqueue(songs.clone(), &env.device, None);
    tokio::time::sleep(Duration::from_millis(400)).await;
    assert!(
        env.svc
            .tasks()
            .iter()
            .all(|t| t.status == TransferStatus::Queued)
    );
    assert_eq!(
        env.svc.queue_album_status()["al1"],
        crate::QueueItemStatus {
            active: false,
            queued: true
        }
    );

    env.svc.resume(None);
    assert!(env.svc.paused_devices().is_empty());
    assert!(paused_rx.borrow_and_update().is_empty());
    env.wait_all(TransferStatus::Completed).await;
    assert!(songs.iter().all(|s| env.target(s).exists()));
}

#[cfg(unix)]
#[tokio::test]
async fn read_only_device_maps_to_permission_denied() {
    use std::os::unix::fs::PermissionsExt;
    let env = Env::new().await;
    let s = song("ro1", 1, "One");
    env.mount_song(&s, b"data", 0).await;
    std::fs::set_permissions(&env.device, std::fs::Permissions::from_mode(0o555)).unwrap();
    env.connect();
    env.svc.enqueue(vec![s.clone()], &env.device, None);
    let tasks = env.wait_all(TransferStatus::Failed).await;
    std::fs::set_permissions(&env.device, std::fs::Permissions::from_mode(0o755)).unwrap();
    assert_eq!(tasks[0].error_message.as_deref(), Some("permission_denied"));
    assert!(!env.target(&s).exists());
    assert!(dir_files(&env.support.join("staging")).is_empty());
}

#[tokio::test]
async fn playlist_m3u_is_written_after_the_whole_group() {
    let env = Env::new().await;
    let a = song("m1", 1, "One");
    let b = song("m2", 2, "Two");
    env.mount_song(&a, b"aaa", 0).await;
    env.mount_song(&b, b"bbb", 1_000).await;
    let playlist = Playlist {
        id: "pl".into(),
        name: "Road Trip".into(),
        songs: vec![a.clone(), b.clone()],
        ..Default::default()
    };
    let m3u = PathBuf::from(dapper_paths::build_playlist_path(
        &playlist,
        &env.settings(),
    ));
    env.connect();
    env.svc.enqueue_playlist(playlist.clone(), &env.device);

    env.wait_tasks("first song", |ts| {
        ts.iter()
            .any(|t| t.song.id == "m1" && t.status == TransferStatus::Completed)
    })
    .await;
    assert!(
        !m3u.exists(),
        "M3U must wait for every song in the playlist"
    );
    env.wait_all(TransferStatus::Completed).await;
    wait_for("m3u", || m3u.exists()).await;
    let text = std::fs::read_to_string(&m3u).unwrap();
    let first = text.find("01 - One").or_else(|| text.find("One")).unwrap();
    let second = text.find("Two").unwrap();
    assert!(text.starts_with("#EXTM3U\n"));
    assert!(first < second);
}

#[tokio::test]
async fn restart_restores_queue_and_cleans_leftovers() {
    let dir = tempfile::tempdir().unwrap();
    let support = dir.path().to_path_buf();
    let store = Arc::new(Store::open(&support).unwrap());
    let mut t = TransferTask::new("t1", song("x1", 1, "One"), "/dev/x");
    t.status = TransferStatus::InProgress;
    t.bytes_received = 50;
    t.total_bytes = 100;
    let mut failed = TransferTask::new("t2", song("x2", 2, "Two"), "/dev/x");
    failed.status = TransferStatus::Failed;
    failed.error_message = Some("boom".into());
    store.save_queue(&[t, failed]).unwrap();
    std::fs::create_dir_all(support.join("staging")).unwrap();
    std::fs::create_dir_all(support.join("tmp")).unwrap();
    std::fs::write(support.join("staging/t1.mp3"), b"partial").unwrap();
    std::fs::write(support.join("tmp/zip_g.zip"), b"zip").unwrap();
    std::fs::write(support.join("tmp/keep.txt"), b"x").unwrap();

    let svc = service(&support, &store);
    let tasks = svc.tasks();
    assert_eq!(tasks[0].status, TransferStatus::Queued);
    assert_eq!((tasks[0].bytes_received, tasks[0].total_bytes), (0, 0));
    assert_eq!(tasks[1].status, TransferStatus::Failed);
    assert!(dir_files(&support.join("staging")).is_empty());
    assert_eq!(
        dir_files(&support.join("tmp")),
        vec!["keep.txt".to_string()]
    );

    // Status changes are persisted without an explicit flush (cancelled
    // tasks are not part of the persisted queue).
    svc.enqueue(vec![song("x3", 3, "Three")], "/dev/x", None);
    wait_for("queue saved", || store.load_queue().len() == 3).await;
    svc.cancel_all(Some("/dev/x"));
    wait_for("cancel saved", || {
        store.load_queue().iter().map(|t| t.id.as_str()).eq(["t2"])
    })
    .await;
}

#[tokio::test]
async fn download_concurrency_follows_app_settings() {
    let env = Env::new().await;
    env.store
        .save_app_settings(&AppSettings {
            transfer_concurrency: 2,
        })
        .unwrap();
    let songs: Vec<Song> = (1..=6)
        .map(|i| song(&format!("k{i}"), i, &format!("T{i}")))
        .collect();
    for s in &songs {
        env.mount_song(s, &body(s.track.unwrap() as u8, 2000), 200)
            .await;
    }
    env.connect();
    env.svc.enqueue(songs.clone(), &env.device, None);
    env.wait_all(TransferStatus::Completed).await;
    assert_eq!(
        env.svc
            .inner()
            .test_hooks
            .max_downloads
            .load(Ordering::Relaxed),
        2
    );
    for s in &songs {
        assert_eq!(writes(&env.target(s)), 1);
    }
}

#[tokio::test]
async fn no_server_keeps_engines_idle() {
    let env = Env::new().await;
    let s = song("n1", 1, "One");
    env.mount_song(&s, b"x", 0).await;
    env.svc.enqueue(vec![s.clone()], &env.device, None);
    tokio::time::sleep(Duration::from_millis(200)).await;
    assert_eq!(env.svc.tasks()[0].status, TransferStatus::Queued);
    assert_eq!(env.svc.active_count(), 1);
    env.connect();
    env.wait_all(TransferStatus::Completed).await;
    assert_eq!(env.svc.active_count(), 0);
}

#[tokio::test]
async fn shutdown_aborts_without_touching_statuses() {
    let env = Env::new().await;
    let s = song("q1", 1, "One");
    env.mount_song(&s, b"slow", 5_000).await;
    env.connect();
    env.svc.enqueue(vec![s.clone()], &env.device, None);
    env.wait_all(TransferStatus::InProgress).await;
    tokio::time::timeout(Duration::from_secs(3), env.svc.shutdown())
        .await
        .expect("shutdown is prompt");
    assert!(env.svc.inner().state.lock().engines.is_empty());
    assert_eq!(env.svc.tasks()[0].status, TransferStatus::InProgress);
    // Persisted as in progress; loading resets it to queued.
    assert_eq!(env.store.load_queue()[0].status, TransferStatus::Queued);
    assert!(dir_files(&env.support.join("staging")).is_empty());
    assert!(!env.target(&s).exists());
    env.svc.idle().await;

    let restarted = service(&env.support, &env.store);
    assert_eq!(restarted.tasks()[0].status, TransferStatus::Queued);
}
