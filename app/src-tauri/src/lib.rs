mod commands;
mod cover;
#[cfg(debug_assertions)]
mod e2e;
mod events;
mod session;
mod state;

use std::path::PathBuf;
use std::sync::Arc;

use dapper_store::{CredentialStore, Store};
use tauri::{AppHandle, Manager, RunEvent};
use tracing_subscriber::EnvFilter;

pub use state::AppState;

use crate::commands::transfer::{QueueStatus, TransferPausedState};

/// Overrides the app data directory (smoke runs, tests).
const ENV_DATA_DIR: &str = "DAPPER_DATA_DIR";
/// Overrides the Flutter data directory to import from; empty skips the import.
const ENV_LEGACY_DIR: &str = "DAPPER_LEGACY_DIR";

pub fn run() {
    // stream-download logs request URLs, which carry Subsonic auth tokens.
    let filter = EnvFilter::try_from_default_env()
        .unwrap_or_else(|_| EnvFilter::new("info"))
        .add_directive("stream_download=off".parse().expect("static directive"));
    tracing_subscriber::fmt().with_env_filter(filter).init();

    let builder = tauri::Builder::default();
    #[cfg(debug_assertions)]
    let builder = e2e::install(builder);
    builder
        .register_asynchronous_uri_scheme_protocol("cover", |ctx, request, responder| {
            cover::handle(ctx.app_handle(), request, responder);
        })
        .invoke_handler(commands::handler())
        .setup(|app| {
            setup(app.handle())?;
            Ok(())
        })
        .build(tauri::generate_context!())
        .expect("error while building Dapper")
        .run(|app, event| {
            if let RunEvent::Exit = event
                && let Some(state) = app.try_state::<AppState>()
            {
                tauri::async_runtime::block_on(state.transfer.shutdown());
            }
        });
}

/// Where the Flutter app kept its data.
fn default_legacy_dir(support_dir: &std::path::Path) -> Option<PathBuf> {
    if cfg!(target_os = "macos") {
        // Same bundle identifier, so the same Application Support folder.
        Some(support_dir.to_path_buf())
    } else if cfg!(windows) {
        std::env::var_os("APPDATA").map(|d| PathBuf::from(d).join("com.dapper").join("dapper"))
    } else {
        None
    }
}

fn setup(app: &AppHandle) -> Result<(), Box<dyn std::error::Error>> {
    let support_dir = match std::env::var_os(ENV_DATA_DIR) {
        Some(d) if !d.is_empty() => PathBuf::from(d),
        _ => app.path().app_data_dir()?,
    };
    let legacy_dir = match std::env::var_os(ENV_LEGACY_DIR) {
        Some(d) if d.is_empty() => None,
        Some(d) => Some(PathBuf::from(d)),
        None => default_legacy_dir(&support_dir),
    };
    tracing::info!(support_dir = %support_dir.display(), "starting");

    let store = Arc::new(Store::open(&support_dir)?);
    let creds: Arc<dyn CredentialStore> = Arc::new(dapper_store::build_default_credential_store(&support_dir)?);
    // Before the transfer service restores queue.json.
    if let Some(dir) = legacy_dir {
        match dapper_store::import_legacy(&dir, &store, creds.as_ref()) {
            Ok(report) if !report.already_imported => tracing::info!(?report, "legacy Flutter data import"),
            Ok(_) => {}
            Err(e) => tracing::warn!(error = %e, "legacy Flutter data import failed"),
        }
    }

    let _runtime = tauri::async_runtime::handle().inner().enter();
    let state = AppState::new(app, &support_dir, store, creds)?;
    if let Err(e) = state.servers.load_migrating() {
        tracing::warn!(error = %e, "server list migration failed");
    }
    if let Err(e) = state.lidarr_repo.load_migrating() {
        tracing::warn!(error = %e, "Lidarr list migration failed");
    }
    app.manage(state);
    forward_events(app);

    let app = app.clone();
    tauri::async_runtime::spawn(async move {
        let state = app.state::<AppState>();
        if let Err(e) = state.reload_session().await {
            events::action_error(&app, format!("Could not open the server: {e}"));
        }
        if let Err(e) = state.reload_lidarr().await {
            events::action_error(&app, format!("Could not open Lidarr: {e}"));
        }
    });
    Ok(())
}

fn forward_events(app: &AppHandle) {
    let state = app.state::<AppState>();
    let player = state.player.subscribe();
    let durations = player.clone();
    events::forward(app, events::PLAYER_STATE, player, |s| events::PlayerState::from(s));
    events::forward(app, events::PLAYER_POSITION, state.player.subscribe_position(), move |p| {
        events::PlayerPosition {
            position_ms: events::millis(*p),
            duration_ms: events::millis(durations.borrow().duration),
        }
    });
    events::forward(app, events::TRANSFER_TASKS, state.transfer.subscribe_tasks(), Arc::clone);
    let transfer = state.transfer.clone();
    events::forward(app, events::QUEUE_STATUS, state.transfer.subscribe_tasks(), move |_| {
        QueueStatus::of(&transfer)
    });
    events::forward(app, events::TRANSFER_PROGRESS, state.transfer.subscribe_progress(), Arc::clone);
    events::forward(app, events::MANIFEST_REVISION, state.transfer.subscribe_manifest_revision(), |r| *r);
    events::forward(app, events::TRANSFER_PAUSED, state.transfer.subscribe_paused(), |d| {
        TransferPausedState::new(d.to_vec())
    });
    events::forward(app, events::IMPORT_STATE, state.import.subscribe(), Clone::clone);
    events::forward(app, events::LIBRARY_SYNC, state.sync.subscribe(), Clone::clone);

    // The first watch() scans the drives (blocking).
    let app = app.clone();
    tauri::async_runtime::spawn(async move {
        let watch_app = app.clone();
        let rx = tauri::async_runtime::spawn_blocking(move || {
            watch_app.state::<AppState>().drives.as_ref().map(|d| d.watch())
        })
        .await;
        let Ok(Some(mut rx)) = rx else {
            return;
        };
        loop {
            let devices = rx.borrow_and_update().clone();
            app.state::<AppState>().on_devices_changed(&devices);
            events::emit(&app, events::DEVICES, devices);
            if rx.changed().await.is_err() {
                break;
            }
        }
    });
}
