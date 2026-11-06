use std::collections::HashMap;
use std::path::{Path, PathBuf};

use dapper_device::{DeviceEntry, LibrarySyncPlan, Progress, ScanReport, ScrobbleImportResult};
use dapper_domain::{
    AlbumSyncStatus, AppError, ArtistSyncStatus, ConnectedDevice, DeviceSettings, EjectResult, LibraryReader,
    Result,
};
use serde::Serialize;
use tauri::State;
use tauri::ipc::Channel;

use super::transfer::device_settings;
use crate::session::CurrentServer;
use crate::state::{AppState, blocking};

#[derive(Clone, Serialize)]
pub struct SyncPlanProgress {
    scanned: usize,
}

/// Imports the device's scrobbler log; `None` when there was nothing to do.
pub async fn import_scrobbles(state: &AppState, device_path: &str) -> Result<Option<ScrobbleImportResult>> {
    let settings = device_settings(state, device_path).await?;
    let sink = CurrentServer(state.session.clone());
    let result = dapper_device::import_scrobbles(device_path, &settings, &sink).await;
    Ok(result.has_work().then_some(result))
}

/// `device_path/rel_path`, refusing anything that resolves outside the device.
fn resolve_under(device_path: &str, rel_path: &str) -> Result<PathBuf> {
    let root = Path::new(device_path).canonicalize()?;
    let target = root.join(rel_path.trim_start_matches(['/', '\\'])).canonicalize()?;
    if !target.starts_with(&root) {
        return Err(AppError::Other(format!("{rel_path} is outside the device")));
    }
    Ok(target)
}

#[tauri::command]
pub async fn devices_list(state: State<'_, AppState>) -> Result<Vec<ConnectedDevice>> {
    let app = state.app.clone();
    blocking(move || {
        use tauri::Manager;
        let state = app.state::<AppState>();
        Ok(state.drives.as_ref().map(|d| d.list()).unwrap_or_default())
    })
    .await
}

#[tauri::command]
pub async fn device_eject(state: State<'_, AppState>, path: String) -> Result<EjectResult> {
    Ok(match &state.drives {
        Some(d) => d.eject(&path).await,
        None => EjectResult::failed("Drive detection is not available on this platform"),
    })
}

#[tauri::command]
pub async fn device_settings_get(state: State<'_, AppState>, device_path: String) -> Result<DeviceSettings> {
    device_settings(&state, &device_path).await
}

#[tauri::command]
pub async fn device_settings_save(state: State<'_, AppState>, settings: DeviceSettings) -> Result<()> {
    if let Some(msg) = dapper_domain::validate_music_root_path(&settings.music_root_folder) {
        return Err(AppError::Other(msg.into()));
    }
    let store = state.store.clone();
    blocking(move || store.upsert_device_settings(&settings)).await
}

#[tauri::command]
pub async fn device_settings_all(state: State<'_, AppState>) -> Result<Vec<DeviceSettings>> {
    let store = state.store.clone();
    blocking(move || store.all_device_settings()).await
}

/// Scan (manifest backfill + duplicate report), then the optional prune and
/// tag clean, in the order the Flutter scan dialog offered them.
#[tauri::command]
pub async fn device_scan(
    state: State<'_, AppState>,
    device_path: String,
    prune: bool,
    clean_tags: bool,
    on_progress: Channel<Progress>,
) -> Result<ScanReport> {
    let library = state.session()?.library.clone();
    let settings = device_settings(&state, &device_path).await?;
    let send = |p: Progress| {
        let _ = on_progress.send(p);
    };
    let mut report = dapper_device::scan_device(&settings, &library, send).await?;
    if prune {
        report.prune = Some(dapper_device::prune_device(&settings, &library, send).await?);
    }
    if clean_tags {
        report.clean = Some(dapper_device::sanitize_device_tags(&settings, send).await);
    }
    dapper_device::clear_device_caches();
    Ok(report)
}

#[tauri::command]
pub async fn device_album_sync(
    state: State<'_, AppState>,
    device_path: String,
) -> Result<HashMap<String, AlbumSyncStatus>> {
    let library = state.session()?.library.clone();
    let settings = device_settings(&state, &device_path).await?;
    let albums = library.all_albums().await?;
    blocking(move || Ok(dapper_device::album_sync_statuses(&settings, &albums))).await
}

#[tauri::command]
pub async fn device_artist_sync(
    state: State<'_, AppState>,
    device_path: String,
) -> Result<HashMap<String, ArtistSyncStatus>> {
    let library = state.session()?.library.clone();
    let settings = device_settings(&state, &device_path).await?;
    let (artists, albums) = tokio::try_join!(LibraryReader::artists(&library), library.all_albums())?;
    blocking(move || Ok(dapper_device::artist_sync_statuses(&settings, &artists, &albums))).await
}

/// Presence of each song on the device; ids missing from the library cache
/// report `false`.
#[tauri::command]
pub async fn device_song_presence(
    state: State<'_, AppState>,
    device_path: String,
    song_ids: Vec<String>,
) -> Result<HashMap<String, bool>> {
    let db = state.session()?.library.db().clone();
    let settings = device_settings(&state, &device_path).await?;
    blocking(move || {
        let mut songs = Vec::with_capacity(song_ids.len());
        let mut out = HashMap::with_capacity(song_ids.len());
        for id in song_ids {
            match db.song(&id)? {
                Some(s) => songs.push(s),
                None => {
                    out.insert(id, false);
                }
            }
        }
        out.extend(dapper_device::song_presence(&settings, &songs));
        Ok(out)
    })
    .await
}

#[tauri::command]
pub async fn device_sync_plan(
    state: State<'_, AppState>,
    device_path: String,
    on_progress: Channel<SyncPlanProgress>,
) -> Result<LibrarySyncPlan> {
    let library = state.session()?.library.clone();
    let settings = device_settings(&state, &device_path).await?;
    dapper_device::build_library_sync_plan(&library, &settings, |scanned| {
        let _ = on_progress.send(SyncPlanProgress { scanned });
    })
    .await
}

#[tauri::command]
pub async fn device_browse(device_path: String, rel_path: String) -> Result<Vec<DeviceEntry>> {
    blocking(move || Ok(dapper_device::list_device_dir(&resolve_under(&device_path, &rel_path)?)?)).await
}

#[tauri::command]
pub async fn device_list_dirs(device_path: String, rel_path: String) -> Result<Vec<DeviceEntry>> {
    blocking(move || Ok(dapper_device::list_device_folders(&resolve_under(&device_path, &rel_path)?)?)).await
}

/// Only for connected devices; every path must be a file under the device.
#[tauri::command]
pub async fn device_delete_files(state: State<'_, AppState>, device_path: String, paths: Vec<String>) -> Result<()> {
    let app = state.app.clone();
    blocking(move || {
        use tauri::Manager;
        let state = app.state::<AppState>();
        let connected = state.drives.as_ref().is_some_and(|d| d.list().iter().any(|c| c.path == device_path));
        if !connected {
            return Err(AppError::NotFound(format!("{device_path} is not a connected device")));
        }
        dapper_device::delete_files(Path::new(&device_path), &paths)?;
        dapper_device::clear_device_caches();
        Ok(())
    })
    .await
}

#[tauri::command]
pub async fn open_full_disk_access_settings() -> Result<()> {
    #[cfg(target_os = "macos")]
    {
        let status = tokio::process::Command::new("open")
            .arg("x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")
            .status()
            .await?;
        if status.success() {
            Ok(())
        } else {
            Err(AppError::Other(format!("Could not open System Settings ({status})")))
        }
    }
    #[cfg(not(target_os = "macos"))]
    Err(AppError::Other("Full Disk Access is a macOS setting".into()))
}
