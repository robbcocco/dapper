//! Backend services shared by every command, built once in `setup`.

use std::collections::HashSet;
use std::path::{Path, PathBuf};
use std::sync::Arc;

use dapper_api::{LidarrClient, MusicBrainzClient};
use dapper_audio::Player;
use dapper_domain::{AppError, ConnectedDevice, Result};
use dapper_import::ImportSession;
use dapper_platform::DriveDetector;
use dapper_store::{CredentialStore, LidarrRepository, ServerRepository, Store};
use dapper_transfer::{TransferDeps, TransferService};
use parking_lot::{Mutex, RwLock};
use serde::Serialize;
use tauri::{AppHandle, Manager};
use tokio::sync::watch;

use crate::cover::CoverCache;
use crate::events;
use crate::session::{CurrentServer, LibraryPlaylistSink, Scrapers, Session, SessionSlot};

/// Runs blocking work (SQLite, keychain, file system) off the async workers.
pub async fn blocking<T: Send + 'static>(f: impl FnOnce() -> Result<T> + Send + 'static) -> Result<T> {
    tauri::async_runtime::spawn_blocking(f)
        .await
        .map_err(|e| AppError::Other(format!("background task failed: {e}")))?
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Serialize)]
#[serde(rename_all = "camelCase")]
pub enum SyncPhase {
    #[default]
    Idle,
    Checking,
    Artists,
    Albums,
    Songs,
    Starred,
    Genres,
    Playlists,
    Done,
}

impl From<dapper_library::SyncPhase> for SyncPhase {
    fn from(p: dapper_library::SyncPhase) -> Self {
        use dapper_library::SyncPhase as L;
        match p {
            L::ScanStatus => Self::Checking,
            L::Artists => Self::Artists,
            L::Albums => Self::Albums,
            L::Songs => Self::Songs,
            L::Starred => Self::Starred,
            L::Genres => Self::Genres,
            // The sweep closes out the pass; the UI has no separate step for it.
            L::Playlists | L::Sweep => Self::Playlists,
            L::Done => Self::Done,
        }
    }
}

/// `SyncProgress` in types.ts.
#[derive(Debug, Clone, PartialEq, Eq, Default, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct SyncStatus {
    pub running: bool,
    pub phase: SyncPhase,
    pub done: i64,
    pub total: Option<i64>,
    pub last_synced_at: Option<String>,
    pub error: Option<String>,
}

pub struct AppState {
    pub app: AppHandle,
    pub support_dir: PathBuf,
    pub store: Arc<Store>,
    pub creds: Arc<dyn CredentialStore>,
    pub servers: ServerRepository,
    pub lidarr_repo: LidarrRepository,
    pub session: Arc<SessionSlot>,
    /// Serialises session swaps so concurrent selections apply in order.
    session_swap: tokio::sync::Mutex<()>,
    pub sync: watch::Sender<SyncStatus>,
    pub player: Player,
    pub transfer: Arc<TransferService>,
    pub drives: Option<DriveDetector>,
    pub import: Arc<ImportSession>,
    pub lidarr: RwLock<Option<Arc<LidarrClient>>>,
    pub mb: MusicBrainzClient,
    pub covers: CoverCache,
    /// Latest drive list, so a session opened later can import their logs.
    devices: Mutex<Vec<ConnectedDevice>>,
    /// Device paths whose scrobbler log was already imported this session.
    scrobble_imported: Mutex<HashSet<String>>,
    /// The running library sync, cancelled before the session is replaced.
    sync_task: Mutex<Option<tauri::async_runtime::JoinHandle<()>>>,
}

impl AppState {
    /// Blocking: spawns the audio engine, restores the transfer queue. Must
    /// run inside the Tauri tokio runtime context.
    pub fn new(
        app: &AppHandle,
        support_dir: &Path,
        store: Arc<Store>,
        creds: Arc<dyn CredentialStore>,
    ) -> Result<Self> {
        let session = Arc::new(SessionSlot::default());
        let current = Arc::new(CurrentServer(session.clone()));
        let player = Player::new(
            tauri::async_runtime::handle().inner().clone(),
            current.clone(),
            current.clone(),
        )?;
        let import = Arc::new(ImportSession::new(
            current,
            Arc::new(Scrapers),
            Arc::new(LibraryPlaylistSink { slot: session.clone(), app: app.clone() }),
        ));
        let drives = DriveDetector::new()
            .inspect_err(|e| tracing::warn!(error = %e, "drive detection unavailable"))
            .ok();
        let transfer = Arc::new(TransferService::new(TransferDeps {
            support_dir: support_dir.to_path_buf(),
            store: store.clone(),
            http: reqwest::Client::new(),
        }));
        Ok(Self {
            app: app.clone(),
            support_dir: support_dir.to_path_buf(),
            servers: ServerRepository::new(creds.clone()),
            lidarr_repo: LidarrRepository::new(creds.clone()),
            store,
            creds,
            session,
            session_swap: tokio::sync::Mutex::new(()),
            sync: watch::Sender::new(SyncStatus::default()),
            player,
            transfer,
            drives,
            import,
            lidarr: RwLock::new(None),
            mb: MusicBrainzClient::new(),
            covers: CoverCache::new(support_dir.join("covers")),
            devices: Mutex::new(Vec::new()),
            scrobble_imported: Mutex::new(HashSet::new()),
            sync_task: Mutex::new(None),
        })
    }

    pub fn library_dir(&self) -> PathBuf {
        self.support_dir.join("library")
    }

    pub fn session(&self) -> Result<Arc<Session>> {
        self.session.require()
    }

    pub fn lidarr(&self) -> Result<Arc<LidarrClient>> {
        self.lidarr
            .read()
            .clone()
            .ok_or_else(|| AppError::Other("No Lidarr instance selected".into()))
    }

    /// Rebuilds the session for the persisted selection and announces it.
    /// Switching servers stops playback, resets the import flow and starts a
    /// library sync for the new server.
    pub async fn reload_session(&self) -> Result<()> {
        let _swap = self.session_swap.lock().await;
        self.cancel_sync().await;
        let servers = self.servers.clone();
        let support = self.support_dir.clone();
        let opened = blocking(move || {
            let (Some(server), Some(creds)) = (servers.selected()?, servers.credentials()?) else {
                return Ok(None);
            };
            Session::open(&support, server, &creds).map(Some)
        })
        .await;
        let session = match opened {
            Ok(s) => s.map(Arc::new),
            Err(e) => {
                self.session.replace(None);
                self.transfer.set_api(None);
                events::server_changed(&self.app, None);
                return Err(e);
            }
        };
        let previous = self.session.selected_id();
        let next = session.as_ref().map(|s| s.server.id.clone());
        self.session.replace(session.clone());
        self.transfer.set_api(session.as_ref().map(|s| s.api.clone()));
        if previous != next {
            self.player.stop();
            self.import.reset();
        }
        let last_synced_at = match &session {
            Some(s) => s.library.status().await.ok().and_then(|st| st.completed_at),
            None => None,
        };
        self.sync.send_replace(SyncStatus { last_synced_at, ..SyncStatus::default() });
        events::server_changed(&self.app, next);
        if session.is_some() {
            self.start_sync(false);
            let devices = self.devices.lock().clone();
            self.on_devices_changed(&devices);
        }
        Ok(())
    }

    pub async fn reload_lidarr(&self) -> Result<()> {
        let repo = self.lidarr_repo.clone();
        let creds = blocking(move || repo.credentials()).await?;
        let client = creds
            .map(|c| LidarrClient::new(&c.url, &c.api_key).map(Arc::new))
            .transpose()?;
        *self.lidarr.write() = client;
        events::lidarr_changed(&self.app);
        Ok(())
    }

    /// Starts a background library sync unless one is already running for
    /// the current server. Progress is published on `sync`.
    pub fn start_sync(&self, force: bool) {
        let Some(session) = self.session.get() else {
            return;
        };
        let started = self.sync.send_if_modified(|s| {
            if s.running {
                return false;
            }
            *s = SyncStatus {
                running: true,
                phase: SyncPhase::Checking,
                last_synced_at: s.last_synced_at.clone(),
                ..SyncStatus::default()
            };
            true
        });
        if !started {
            return;
        }
        let app = self.app.clone();
        let task = tauri::async_runtime::spawn(async move {
            let state = app.state::<AppState>();
            let server_id = session.server.id.clone();
            let is_current = || state.session.selected_id().as_deref() == Some(server_id.as_str());
            let result = session
                .library
                .sync(force, |p| {
                    if is_current() {
                        state.sync.send_modify(|s| {
                            s.phase = p.phase.into();
                            s.done = p.done;
                            s.total = p.total;
                        });
                    }
                })
                .await;
            if !is_current() {
                return;
            }
            let last_synced_at = session.library.status().await.ok().and_then(|st| st.completed_at);
            let ok = result.is_ok();
            state.sync.send_modify(|s| {
                s.running = false;
                s.last_synced_at = last_synced_at;
                match &result {
                    Ok(_) => {
                        s.phase = SyncPhase::Done;
                        s.error = None;
                    }
                    Err(e) => {
                        s.phase = SyncPhase::Idle;
                        s.error = Some(e.to_string());
                    }
                }
            });
            match result {
                Ok(report) => tracing::info!(?report, "library sync finished"),
                Err(e) => tracing::warn!(error = %e, "library sync failed"),
            }
            if ok {
                events::library_changed(&app);
            }
        });
        *self.sync_task.lock() = Some(task);
    }

    /// Stops the background sync and waits until it has unwound, so a new
    /// `Library` never opens the same database mid-pass. An interrupted pass
    /// keeps the previous cache contents.
    async fn cancel_sync(&self) {
        let task = self.sync_task.lock().take();
        if let Some(task) = task {
            task.abort();
            let _ = task.await;
        }
    }

    /// Drive-list change: forgets departed devices and imports the scrobbler
    /// log of each newly seen one (once per path per app session).
    pub fn on_devices_changed(&self, devices: &[ConnectedDevice]) {
        *self.devices.lock() = devices.to_vec();
        let fresh: Vec<String> = {
            let mut seen = self.scrobble_imported.lock();
            seen.retain(|p| devices.iter().any(|d| &d.path == p));
            if self.session.get().is_none() {
                return;
            }
            devices
                .iter()
                .filter(|d| seen.insert(d.path.clone()))
                .map(|d| d.path.clone())
                .collect()
        };
        for path in fresh {
            let app = self.app.clone();
            tauri::async_runtime::spawn(async move {
                let state = app.state::<AppState>();
                match crate::commands::devices::import_scrobbles(&state, &path).await {
                    Ok(Some(result)) => events::emit(&app, events::SCROBBLE_IMPORT, result),
                    Ok(None) => {}
                    Err(e) => tracing::warn!(device = %path, error = %e, "scrobble import failed"),
                }
            });
        }
    }

    /// Drops the server session, Lidarr client and per-session memory (app reset).
    pub async fn clear_session(&self) {
        let _swap = self.session_swap.lock().await;
        self.cancel_sync().await;
        self.session.replace(None);
        self.transfer.set_api(None);
        self.player.stop();
        self.import.reset();
        self.sync.send_replace(SyncStatus::default());
        *self.lidarr.write() = None;
        self.scrobble_imported.lock().clear();
    }
}
