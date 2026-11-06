use std::path::PathBuf;

use dapper_domain::{AppSettings, Result};
use serde::Serialize;
use tauri::State;

use crate::cover::remove_files;
use crate::events;
use crate::state::{AppState, blocking};

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CacheCleanResult {
    /// Leftover transfer staging files removed (cover art not counted, as in
    /// the Flutter "Clean cache" message).
    files_removed: u64,
    bytes_freed: u64,
    skipped_staging: bool,
}

fn staging_dirs(state: &AppState) -> Vec<PathBuf> {
    let tmp = state.support_dir.join("tmp");
    let staging = state.transfer.staging_dir();
    if staging == tmp { vec![tmp] } else { vec![tmp, staging] }
}

#[tauri::command]
pub async fn app_settings_get(state: State<'_, AppState>) -> Result<AppSettings> {
    let store = state.store.clone();
    blocking(move || Ok(store.load_app_settings())).await
}

/// The transfer engine re-reads the concurrency from the store per slot.
#[tauri::command]
pub async fn app_settings_set_transfer_concurrency(state: State<'_, AppState>, n: i64) -> Result<AppSettings> {
    let store = state.store.clone();
    blocking(move || {
        let settings = dapper_store::with_transfer_concurrency(store.load_app_settings(), n);
        store.save_app_settings(&settings)?;
        Ok(settings)
    })
    .await
}

/// Cover-art cache plus transfer staging; staging holds in-flight zip
/// downloads, so it is left alone while any transfer is active.
#[tauri::command]
pub async fn cache_clean(state: State<'_, AppState>) -> Result<CacheCleanResult> {
    let skipped_staging = state.transfer.active_count() > 0;
    let dirs = if skipped_staging { Vec::new() } else { staging_dirs(&state) };
    let (files_removed, bytes_freed) = blocking(move || {
        Ok(dirs.iter().map(|d| remove_files(d)).fold((0, 0), |(f, b), (df, db)| (f + df, b + db)))
    })
    .await?;
    state.covers.clear().await?;
    Ok(CacheCleanResult { files_removed, bytes_freed, skipped_staging })
}

#[tauri::command]
pub async fn cover_cache_size(state: State<'_, AppState>) -> Result<u64> {
    state.covers.size().await
}

/// Settings "Reset all data": stops transfers and playback, wipes app.db
/// device settings, settings/queue files, every credential, library caches
/// and cover art, then announces that no server is selected.
#[tauri::command]
pub async fn app_reset(state: State<'_, AppState>) -> Result<()> {
    state.transfer.shutdown().await;
    state.transfer.cancel_all(None);
    state.transfer.clear_completed();
    state.clear_session().await;
    let (store, creds) = (state.store.clone(), state.creds.clone());
    let library_dir = state.library_dir();
    let covers = state.covers.dir().to_path_buf();
    let staging = staging_dirs(&state);
    // Every step runs even when an earlier one fails; the first error is
    // reported once the wipe has gone as far as it can.
    let outcome = blocking(move || {
        let wiped = store.wipe_user_data();
        let creds_cleared = creds.delete_all();
        for dir in [library_dir, covers] {
            if let Err(e) = std::fs::remove_dir_all(&dir)
                && e.kind() != std::io::ErrorKind::NotFound
            {
                tracing::warn!(dir = %dir.display(), error = %e, "reset: could not remove directory");
            }
        }
        for dir in &staging {
            remove_files(dir);
        }
        wiped.and(creds_cleared)
    })
    .await;
    dapper_device::clear_device_caches();
    events::server_changed(&state.app, None);
    events::lidarr_changed(&state.app);
    outcome
}
