//! Dev-only CLI: composes the backend crates the way the app does (minus
//! Tauri), with every piece of state under `--data-dir`. Credentials go to a
//! plain `FileCredentialStore` there, never the OS keychain.

use std::collections::{HashMap, HashSet};
use std::path::{Path, PathBuf};
use std::sync::Arc;
use std::time::{Duration, Instant};

use anyhow::{Context, Result, bail};
use async_trait::async_trait;
use clap::{Args, Parser, Subcommand};
use dapper_api::{SubsonicApi, SubsonicClient};
use dapper_audio::{Player, StreamResolver};
use dapper_device::{Progress, build_library_sync_plan, prune_device, sanitize_device_tags, scan_device};
use dapper_domain::{DeviceSettings, NavidromeServer, ScrobbleSink, Song, TransferStatus, TransferTask};
use dapper_library::{AlbumSort, Library, SearchLimits, SortDir};
use dapper_platform::DriveDetector;
use dapper_store::{CREDENTIALS_FILE, CredentialStore, FileCredentialStore, ServerRepository, Store};
use dapper_transfer::{TransferDeps, TransferService};
use serde::Serialize;
use url::Url;

#[derive(Parser)]
#[command(name = "dapper-devcli", about = "Dapper backend dev CLI (no Tauri)")]
struct Cli {
    /// Holds app.db, settings.json, credentials, library caches and the transfer queue.
    #[arg(long)]
    data_dir: PathBuf,
    #[command(subcommand)]
    cmd: Cmd,
}

#[derive(Subcommand)]
enum Cmd {
    /// Manage Navidrome servers.
    Server {
        #[command(subcommand)]
        cmd: ServerCmd,
    },
    /// Sync the selected server's library cache.
    Sync {
        #[arg(long)]
        force: bool,
    },
    /// Search the library cache.
    Search { query: String },
    /// List albums (name order).
    Albums {
        #[arg(long, default_value_t = 20)]
        limit: i64,
    },
    /// Transfer to a device directory and wait for completion.
    Transfer {
        #[command(subcommand)]
        cmd: TransferCmd,
    },
    /// Rebuild manifests and report duplicates; optionally prune orphans and clean FLAC tags.
    Scan {
        #[arg(long)]
        device: PathBuf,
        #[arg(long)]
        prune: bool,
        #[arg(long)]
        clean: bool,
    },
    /// Library albums missing from or partial on the device.
    SyncPlan {
        #[arg(long)]
        device: PathBuf,
    },
    /// Play one song, printing position ticks and scrobble calls.
    Play {
        song_id: String,
        #[arg(long, default_value_t = 3)]
        seconds: u64,
        #[arg(long, default_value_t = 0.0)]
        volume: f32,
    },
    /// List removable drives.
    Drives,
}

#[derive(Subcommand)]
enum ServerCmd {
    /// Ping, store and select a server.
    Add {
        #[arg(long)]
        url: String,
        #[arg(long)]
        user: String,
        #[arg(long)]
        pass: String,
        #[arg(long)]
        name: Option<String>,
    },
}

#[derive(Subcommand)]
enum TransferCmd {
    Album {
        album_id: String,
        #[command(flatten)]
        opts: AlbumOpts,
    },
    Playlist {
        playlist_id: String,
        #[arg(long)]
        device: PathBuf,
    },
}

#[derive(Args)]
struct AlbumOpts {
    #[arg(long)]
    device: PathBuf,
    /// One zip per album (stored as the device's setting).
    #[arg(long, conflicts_with = "per_song")]
    zip: bool,
    /// One download per song (stored as the device's setting).
    #[arg(long)]
    per_song: bool,
    /// Sanitize FLAC tags after transfer (stored; absent = off).
    #[arg(long)]
    clean: bool,
    /// Shrink embedded FLAC cover art after transfer (stored; absent = off).
    #[arg(long)]
    shrink: bool,
}

#[tokio::main]
async fn main() -> Result<()> {
    tracing_subscriber::fmt()
        .with_env_filter(tracing_subscriber::EnvFilter::from_default_env())
        .with_writer(std::io::stderr)
        .init();
    let cli = Cli::parse();
    let ctx = Ctx::open(&cli.data_dir)?;
    match cli.cmd {
        Cmd::Server { cmd: ServerCmd::Add { url, user, pass, name } } => server_add(&ctx, url, user, pass, name).await,
        Cmd::Sync { force } => sync(&ctx, force).await,
        Cmd::Search { query } => search(&ctx, &query).await,
        Cmd::Albums { limit } => albums(&ctx, limit).await,
        Cmd::Transfer { cmd: TransferCmd::Album { album_id, opts } } => transfer_album(&ctx, &album_id, opts).await,
        Cmd::Transfer { cmd: TransferCmd::Playlist { playlist_id, device } } => {
            transfer_playlist(&ctx, &playlist_id, &device).await
        }
        Cmd::Scan { device, prune, clean } => scan(&ctx, &device, prune, clean).await,
        Cmd::SyncPlan { device } => sync_plan(&ctx, &device).await,
        Cmd::Play { song_id, seconds, volume } => play(&ctx, &song_id, seconds, volume).await,
        Cmd::Drives => drives().await,
    }
}

struct Ctx {
    data_dir: PathBuf,
    store: Arc<Store>,
    servers: ServerRepository,
}

struct Session {
    server: NavidromeServer,
    api: Arc<SubsonicApi>,
    library: Library,
}

impl Ctx {
    fn open(data_dir: &Path) -> Result<Self> {
        std::fs::create_dir_all(data_dir).with_context(|| format!("creating {}", data_dir.display()))?;
        let store = Arc::new(Store::open(data_dir)?);
        let creds: Arc<dyn CredentialStore> = Arc::new(FileCredentialStore::open(data_dir.join(CREDENTIALS_FILE))?);
        Ok(Self { data_dir: data_dir.to_path_buf(), store, servers: ServerRepository::new(creds) })
    }

    /// Same construction as the app's `Session::open`.
    fn session(&self) -> Result<Session> {
        let server = self.servers.selected()?.context("no server selected; run `server add` first")?;
        let creds = self.servers.credentials()?.context("selected server has no stored password")?;
        let api = Arc::new(SubsonicApi::new(SubsonicClient::new(&creds.url, &creds.username, &creds.password)?));
        let library = Library::open(&Library::db_path(&self.data_dir, &server.id), server.id.clone(), api.clone())?;
        Ok(Session { server, api, library })
    }

    fn transfer(&self, api: Arc<SubsonicApi>) -> TransferService {
        let svc = TransferService::new(TransferDeps {
            support_dir: self.data_dir.clone(),
            store: self.store.clone(),
            http: reqwest::Client::new(),
        });
        svc.set_api(Some(api));
        svc
    }

    fn device_settings(&self, device: &str) -> Result<DeviceSettings> {
        Ok(self.store.device_settings(device)?.unwrap_or_else(|| DeviceSettings::new(device)))
    }
}

fn print_json(value: &impl Serialize) -> Result<()> {
    println!("{}", serde_json::to_string_pretty(value)?);
    Ok(())
}

/// Device key as the app uses it: the mount path without a trailing separator.
fn device_key(dir: &Path) -> Result<String> {
    if !dir.is_dir() {
        bail!("device directory {} does not exist", dir.display());
    }
    let s = dir.to_string_lossy();
    let trimmed = s.trim_end_matches(['/', '\\']);
    Ok(if trimmed.is_empty() { s.into_owned() } else { trimmed.to_string() })
}

fn progress_printer(start: Instant) -> impl FnMut(Progress) {
    let mut last = String::new();
    move |p: Progress| {
        if p.phase != last {
            println!("  [{:>7.2}s] {} ({}/{:?})", start.elapsed().as_secs_f64(), p.phase, p.done, p.total);
            last = p.phase;
        }
    }
}

async fn server_add(ctx: &Ctx, url: String, user: String, pass: String, name: Option<String>) -> Result<()> {
    let url = url.trim().trim_end_matches('/').to_string();
    let user = user.trim().to_string();
    let t = Instant::now();
    let api = SubsonicApi::new(SubsonicClient::new(&url, &user, &pass)?);
    if !api.ping().await? {
        bail!("server returned non-ok status");
    }
    println!("ping ok in {:?}", t.elapsed());
    let name = name.map(|n| n.trim().to_string()).filter(|n| !n.is_empty()).unwrap_or_else(|| url.clone());
    let server = NavidromeServer { id: dapper_store::new_id(), name, url, username: user };
    ctx.servers.add(&server, &pass)?;
    ctx.servers.save_selected_id(Some(&server.id))?;
    println!("added and selected server {} ({})", server.id, server.url);
    Ok(())
}

async fn sync(ctx: &Ctx, force: bool) -> Result<()> {
    let s = ctx.session()?;
    println!("syncing {} ({})", s.server.name, s.server.id);
    let start = Instant::now();
    let mut last = None;
    let report = s
        .library
        .sync(force, |p| {
            if last != Some(p.phase) {
                println!("  [{:>7.2}s] {:?} {}/{:?}", start.elapsed().as_secs_f64(), p.phase, p.done, p.total);
                last = Some(p.phase);
            }
        })
        .await?;
    println!("sync finished in {:?}", start.elapsed());
    print_json(&report)?;
    print_json(&s.library.status().await?)
}

async fn search(ctx: &Ctx, query: &str) -> Result<()> {
    let s = ctx.session()?;
    let t = Instant::now();
    let r = s.library.search(query, SearchLimits::default()).await?;
    println!(
        "search {query:?}: {} artists, {} albums, {} songs in {:?}",
        r.artists.len(),
        r.albums.len(),
        r.songs.len(),
        t.elapsed()
    );
    for a in r.artists.iter().take(10) {
        println!("  artist {}  {}", a.id, a.name);
    }
    for a in r.albums.iter().take(10) {
        println!("  album  {}  {} – {}", a.id, a.artist.as_deref().unwrap_or("?"), a.name);
    }
    for so in r.songs.iter().take(10) {
        println!("  song   {}  {} – {}", so.id, so.artist.as_deref().unwrap_or("?"), so.title);
    }
    Ok(())
}

async fn albums(ctx: &Ctx, limit: i64) -> Result<()> {
    let s = ctx.session()?;
    let t = Instant::now();
    let page = s.library.albums_page(0, limit, AlbumSort::Name, SortDir::Asc).await?;
    println!("{} albums (total {:?}) in {:?}", page.items.len(), page.total, t.elapsed());
    for a in &page.items {
        println!(
            "  {}  {} – {} ({}) {} songs",
            a.id,
            a.artist.as_deref().unwrap_or("?"),
            a.name,
            a.year.map_or_else(|| "-".into(), |y| y.to_string()),
            a.song_count
        );
    }
    Ok(())
}

async fn transfer_album(ctx: &Ctx, album_id: &str, opts: AlbumOpts) -> Result<()> {
    let s = ctx.session()?;
    let device = device_key(&opts.device)?;
    let mut settings = ctx.device_settings(&device)?;
    if opts.zip {
        settings.use_zip_download = true;
    }
    if opts.per_song {
        settings.use_zip_download = false;
    }
    settings.auto_clean_metadata = opts.clean;
    settings.auto_shrink_cover_art = opts.shrink;
    ctx.store.upsert_device_settings(&settings)?;

    let album = s.library.album(album_id).await?;
    let zip = settings.use_zip_download && !settings.is_transcoding();
    println!(
        "album {} – {} ({} songs) → {device} via {} [clean={} shrink={}]",
        album.artist.as_deref().unwrap_or("?"),
        album.name,
        album.songs.len(),
        if zip { "zip" } else { "per-song" },
        settings.auto_clean_metadata,
        settings.auto_shrink_cover_art
    );
    let svc = ctx.transfer(s.api.clone());
    let before = task_ids(&svc);
    // Same dispatch as the album page's "transfer all".
    if zip {
        svc.enqueue_zip_group(&album.id, album.songs.clone(), &device);
    } else {
        let folder = dapper_paths::build_album_folder(album.artist.as_deref(), &album.name, album.year, &settings);
        let counts = folder.map(|f| HashMap::from([(f, album.song_count)]));
        svc.enqueue(album.songs.clone(), &device, counts);
    }
    wait_for_transfer(&svc, &before, &settings).await
}

async fn transfer_playlist(ctx: &Ctx, playlist_id: &str, device: &Path) -> Result<()> {
    let s = ctx.session()?;
    let device = device_key(device)?;
    let playlist = s.library.playlist(playlist_id).await?;
    println!("playlist {} ({} songs) → {device}", playlist.name, playlist.songs.len());
    let svc = ctx.transfer(s.api.clone());
    let before = task_ids(&svc);
    svc.enqueue_playlist(playlist, &device);
    wait_for_transfer(&svc, &before, &ctx.device_settings(&device)?).await
}

fn task_ids(svc: &TransferService) -> HashSet<String> {
    svc.tasks().iter().map(|t| t.id.clone()).collect()
}

fn is_terminal(s: TransferStatus) -> bool {
    matches!(s, TransferStatus::Completed | TransferStatus::Failed | TransferStatus::Cancelled)
}

/// Waits until every task enqueued after `before` is terminal, printing a
/// status line per second, then lets the service finish its manifest/M3U
/// writes, persist and stop. Tasks carry no byte counts (the service keeps
/// live progress in a separate map, cleared when a task finishes), so the
/// summary reports each song's file size at its resolved device path.
async fn wait_for_transfer(svc: &TransferService, before: &HashSet<String>, settings: &DeviceSettings) -> Result<()> {
    let start = Instant::now();
    let mut tasks_rx = svc.subscribe_tasks();
    let progress_rx = svc.subscribe_progress();
    let mut tick = tokio::time::interval(Duration::from_secs(1));
    let ours = |all: &[TransferTask]| -> Vec<TransferTask> {
        all.iter().filter(|t| !before.contains(&t.id)).cloned().collect()
    };
    loop {
        let mine = ours(&svc.tasks());
        if mine.is_empty() {
            println!("nothing enqueued (already queued or empty)");
            break;
        }
        if mine.iter().all(|t| is_terminal(t.status)) {
            break;
        }
        tokio::select! {
            _ = tick.tick() => {
                let count = |st| mine.iter().filter(|t| t.status == st).count();
                // Zip members all report the one shared download; count it once.
                let progress = progress_rx.borrow().clone();
                let mut zip_groups = HashSet::new();
                let in_flight: i64 = mine
                    .iter()
                    .filter(|t| t.zip_group_id.as_ref().is_none_or(|g| zip_groups.insert(g.clone())))
                    .filter_map(|t| progress.get(&t.id))
                    .map(|p| p.0)
                    .sum();
                println!(
                    "  [{:>7.2}s] queued {} in-progress {} completed {} failed {} cancelled {} | in-flight bytes {}",
                    start.elapsed().as_secs_f64(),
                    count(TransferStatus::Queued),
                    count(TransferStatus::InProgress),
                    count(TransferStatus::Completed),
                    count(TransferStatus::Failed),
                    count(TransferStatus::Cancelled),
                    in_flight
                );
            }
            changed = tasks_rx.changed() => changed?,
        }
    }
    // Manifest appends and the playlist M3U land after the task statuses flip.
    svc.idle().await;
    let elapsed = start.elapsed();
    svc.shutdown().await;
    let mine = ours(&svc.tasks());
    let mut on_device_total = 0;
    for t in &mine {
        let path = dapper_paths::build_song_path(&t.song, settings);
        let on_device = std::fs::metadata(&path).map(|m| m.len()).unwrap_or(0);
        on_device_total += on_device;
        println!(
            "  {:<10} {:>10} B on device (server {:>10} B)  {}{}",
            format!("{:?}", t.status),
            on_device,
            t.song.size.unwrap_or(0),
            path,
            t.error_message.as_deref().map(|e| format!("  ERROR: {e}")).unwrap_or_default()
        );
    }
    let ok = mine.iter().filter(|t| t.status == TransferStatus::Completed).count();
    let secs = elapsed.as_secs_f64();
    println!(
        "transfer done: {ok}/{} completed in {elapsed:?}; {on_device_total} B on device ({:.2} MB/s)",
        mine.len(),
        if secs > 0.0 { on_device_total as f64 / 1e6 / secs } else { 0.0 }
    );
    if ok != mine.len() {
        bail!("{} task(s) did not complete", mine.len() - ok);
    }
    Ok(())
}

async fn scan(ctx: &Ctx, device: &Path, prune: bool, clean: bool) -> Result<()> {
    let s = ctx.session()?;
    let settings = ctx.device_settings(&device_key(device)?)?;
    let start = Instant::now();
    let mut report = scan_device(&settings, &s.library, progress_printer(start)).await?;
    println!("scan finished in {:?}", start.elapsed());
    if prune {
        let t = Instant::now();
        report.prune = Some(prune_device(&settings, &s.library, progress_printer(t)).await?);
        println!("prune finished in {:?}", t.elapsed());
    }
    if clean {
        let t = Instant::now();
        report.clean = Some(sanitize_device_tags(&settings, progress_printer(t)).await);
        println!("tag clean finished in {:?}", t.elapsed());
    }
    print_json(&report)
}

async fn sync_plan(ctx: &Ctx, device: &Path) -> Result<()> {
    let s = ctx.session()?;
    let settings = ctx.device_settings(&device_key(device)?)?;
    let t = Instant::now();
    let plan = build_library_sync_plan(&s.library, &settings, |_| {}).await?;
    println!(
        "sync plan in {:?}: {} albums scanned, {} albums / {} songs missing",
        t.elapsed(),
        plan.albums_scanned,
        plan.missing_albums,
        plan.missing_songs
    );
    for a in plan.unsynced.iter().take(15) {
        println!("  {}  {} – {} ({} songs)", a.id, a.artist.as_deref().unwrap_or("?"), a.name, a.song_count);
    }
    if plan.unsynced.len() > 15 {
        println!("  … {} more", plan.unsynced.len() - 15);
    }
    Ok(())
}

/// Stream URLs exactly like the app's `CurrentServer` resolver.
struct Resolver(Arc<SubsonicApi>);

impl StreamResolver for Resolver {
    fn stream_url(&self, song: &Song, transcode: bool) -> Url {
        if transcode { self.0.stream_uri(&song.id, Some("mp3"), Some(320)) } else { self.0.stream_uri(&song.id, None, None) }
    }
}

/// Forwards to the server and logs each call.
struct LoggingScrobbler {
    api: Arc<SubsonicApi>,
    start: Instant,
}

#[async_trait]
impl ScrobbleSink for LoggingScrobbler {
    async fn scrobble(&self, song_id: &str, submission: bool, time_ms: Option<i64>) -> dapper_domain::Result<()> {
        let result = self.api.scrobble(song_id, submission, time_ms).await;
        println!(
            "  [{:>7.2}s] scrobble id={song_id} submission={submission} time={time_ms:?} -> {}",
            self.start.elapsed().as_secs_f64(),
            match &result {
                Ok(()) => "ok".to_string(),
                Err(e) => format!("error: {e}"),
            }
        );
        result
    }
}

async fn play(ctx: &Ctx, song_id: &str, seconds: u64, volume: f32) -> Result<()> {
    let s = ctx.session()?;
    let db = s.library.db().clone();
    let id = song_id.to_string();
    let song = tokio::task::spawn_blocking(move || db.song(&id))
        .await??
        .context("song not in library cache; run `sync` first")?;
    println!("playing {} – {} ({:?}s) at volume {volume}", song.artist.as_deref().unwrap_or("?"), song.title, song.duration);
    let start = Instant::now();
    let player = Player::new(
        tokio::runtime::Handle::current(),
        Arc::new(Resolver(s.api.clone())),
        Arc::new(LoggingScrobbler { api: s.api.clone(), start }),
    )?;
    player.set_volume(volume);
    player.play_song(song);
    let mut state_rx = player.subscribe();
    let mut tick = tokio::time::interval(Duration::from_millis(500));
    let deadline = tokio::time::sleep(Duration::from_secs(seconds));
    tokio::pin!(deadline);
    let mut last_state = None;
    loop {
        tokio::select! {
            _ = &mut deadline => break,
            _ = tick.tick() => {
                println!("  [{:>7.2}s] position {:?}", start.elapsed().as_secs_f64(), player.position());
            }
            changed = state_rx.changed() => {
                changed?;
                let st = state_rx.borrow_and_update().clone();
                let summary = (st.is_playing, st.is_buffering, st.duration, st.error_message.clone());
                if last_state.as_ref() != Some(&summary) {
                    println!(
                        "  [{:>7.2}s] state playing={} buffering={} duration={:?} volume={} error={:?}",
                        start.elapsed().as_secs_f64(), st.is_playing, st.is_buffering, st.duration, st.volume, st.error_message
                    );
                    last_state = Some(summary);
                }
            }
        }
    }
    player.stop();
    // Let a stop-triggered scrobble reach the server before the runtime exits.
    tokio::time::sleep(Duration::from_millis(500)).await;
    println!("final position {:?}", player.position());
    Ok(())
}

async fn drives() -> Result<()> {
    let devices = tokio::task::spawn_blocking(|| DriveDetector::new().map(|d| d.list())).await??;
    println!("{} removable drive(s)", devices.len());
    for d in &devices {
        println!("  {}  {:?}  {} free of {}", d.path, d.label, d.available_formatted(), d.total_formatted());
    }
    Ok(())
}
