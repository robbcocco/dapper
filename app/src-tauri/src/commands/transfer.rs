use std::collections::HashMap;
use std::sync::Arc;

use dapper_domain::{Album, DeviceSettings, Result, Song, TransferTask};
use dapper_library::Library;
use dapper_transfer::{QueueItemStatus, TransferService};
use futures::{StreamExt, TryStreamExt};
use serde::Serialize;
use tauri::State;

use crate::state::{AppState, blocking};

/// Concurrent album reads while expanding artist / library-sync requests.
const ALBUM_FETCH_CONCURRENCY: usize = 8;

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct TransferPausedState {
    pub any_paused: bool,
    pub devices: Vec<String>,
}

impl TransferPausedState {
    pub fn new(devices: Vec<String>) -> Self {
        Self { any_paused: !devices.is_empty(), devices }
    }
}

#[derive(Debug, Clone, Serialize)]
pub struct QueueStatus {
    pub albums: HashMap<String, QueueItemStatus>,
    pub songs: HashMap<String, QueueItemStatus>,
}

impl QueueStatus {
    pub fn of(transfer: &TransferService) -> Self {
        Self { albums: transfer.queue_album_status(), songs: transfer.queue_song_status() }
    }
}

pub(crate) async fn device_settings(state: &AppState, device_path: &str) -> Result<DeviceSettings> {
    let (store, path) = (state.store.clone(), device_path.to_string());
    blocking(move || Ok(store.device_settings(&path)?.unwrap_or_else(|| DeviceSettings::new(path))))
        .await
}

/// One album as a zip group (originals only) or per-song with its expected
/// song count, so the manifest knows when the folder is complete.
fn enqueue_album(transfer: &TransferService, album: Album, device_path: &str, settings: &DeviceSettings, zip: bool) {
    if album.songs.is_empty() {
        return;
    }
    if zip {
        transfer.enqueue_zip_group(&album.id, album.songs, device_path);
        return;
    }
    let expected = dapper_paths::build_album_folder(album.artist.as_deref(), &album.name, album.year, settings)
        .map(|folder| HashMap::from([(folder, album.song_count)]));
    transfer.enqueue(album.songs, device_path, expected);
}

/// Full albums (with songs) for `ids`, in order.
async fn full_albums(library: &Library, ids: Vec<String>) -> Result<Vec<Album>> {
    futures::stream::iter(ids)
        .map(|id| {
            let library = library.clone();
            async move { library.album(&id).await }
        })
        .buffered(ALBUM_FETCH_CONCURRENCY)
        .try_collect()
        .await
}

#[tauri::command]
pub fn transfer_enqueue_songs(state: State<'_, AppState>, device_path: String, songs: Vec<Song>) {
    state.transfer.enqueue(songs, &device_path, None);
}

#[tauri::command]
pub async fn transfer_enqueue_album(state: State<'_, AppState>, device_path: String, album_id: String) -> Result<()> {
    let album = state.session()?.library.album(&album_id).await?;
    let settings = device_settings(&state, &device_path).await?;
    let zip = settings.use_zip_download && !settings.is_transcoding();
    enqueue_album(&state.transfer, album, &device_path, &settings, zip);
    Ok(())
}

/// Every album of the artist, skipping albums whose files are all on the
/// device already unless the device overwrites existing files.
#[tauri::command]
pub async fn transfer_enqueue_artist(state: State<'_, AppState>, device_path: String, artist_id: String) -> Result<()> {
    let library = state.session()?.library.clone();
    let ids = library.artist_albums(&artist_id).await?.into_iter().map(|a| a.id).collect();
    let albums = full_albums(&library, ids).await?;
    let settings = device_settings(&state, &device_path).await?;
    let zip = settings.use_zip_download && !settings.is_transcoding();
    let (albums, settings) = if settings.overwrite_existing {
        (albums, settings)
    } else {
        // Direct file checks so a stale manifest entry can't hide deleted files.
        blocking(move || {
            let missing = albums
                .into_iter()
                .filter(|a| !a.songs.iter().all(|s| dapper_device::song_file_exists_on_device(s, &settings)))
                .collect();
            Ok((missing, settings))
        })
        .await?
    };
    for album in albums {
        enqueue_album(&state.transfer, album, &device_path, &settings, zip);
    }
    Ok(())
}

#[tauri::command]
pub async fn transfer_enqueue_playlist(
    state: State<'_, AppState>,
    device_path: String,
    playlist_id: String,
) -> Result<()> {
    let playlist = state.session()?.library.playlist(&playlist_id).await?;
    state.transfer.enqueue_playlist(playlist, &device_path);
    Ok(())
}

/// Library sync: each album as its own zip group or per-song batch.
#[tauri::command]
pub async fn transfer_enqueue_albums(
    state: State<'_, AppState>,
    device_path: String,
    album_ids: Vec<String>,
    use_zip: bool,
) -> Result<()> {
    let library = state.session()?.library.clone();
    let settings = device_settings(&state, &device_path).await?;
    let zip = use_zip && !settings.is_transcoding();
    let albums = full_albums(&library, album_ids).await?;
    for album in albums {
        enqueue_album(&state.transfer, album, &device_path, &settings, zip);
    }
    Ok(())
}

#[tauri::command]
pub fn transfer_cancel(state: State<'_, AppState>, task_id: String) {
    state.transfer.cancel(&task_id);
}

#[tauri::command]
pub fn transfer_cancel_all(state: State<'_, AppState>, device_path: Option<String>) {
    state.transfer.cancel_all(device_path.as_deref());
}

#[tauri::command]
pub fn transfer_retry(state: State<'_, AppState>, task_id: String) {
    state.transfer.retry(&task_id);
}

#[tauri::command]
pub fn transfer_retry_failed(state: State<'_, AppState>, device_path: Option<String>) {
    state.transfer.retry_all_failed(device_path.as_deref());
}

#[tauri::command]
pub fn transfer_pause(state: State<'_, AppState>, device_path: Option<String>) {
    state.transfer.pause(device_path.as_deref());
}

#[tauri::command]
pub fn transfer_resume(state: State<'_, AppState>, device_path: Option<String>) {
    state.transfer.resume(device_path.as_deref());
}

#[tauri::command]
pub fn transfer_clear_completed(state: State<'_, AppState>) {
    state.transfer.clear_completed();
}

#[tauri::command]
pub fn transfer_tasks(state: State<'_, AppState>) -> Arc<Vec<TransferTask>> {
    state.transfer.tasks()
}

#[tauri::command]
pub fn transfer_paused(state: State<'_, AppState>) -> TransferPausedState {
    TransferPausedState::new(state.transfer.paused_devices())
}

#[tauri::command]
pub fn queue_album_status(state: State<'_, AppState>) -> HashMap<String, QueueItemStatus> {
    state.transfer.queue_album_status()
}

#[tauri::command]
pub fn queue_song_status(state: State<'_, AppState>) -> HashMap<String, QueueItemStatus> {
    state.transfer.queue_song_status()
}
