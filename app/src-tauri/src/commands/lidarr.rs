use std::collections::HashSet;
use std::time::Duration;

use dapper_api::LidarrClient;
use dapper_domain::{
    AppError, LidarrAlbum, LidarrAlbumLookup, LidarrArtist, LidarrCustomFilter, LidarrInstance,
    LidarrQualityProfile, LidarrRelease, LidarrRootFolder, Result,
};
use serde::Serialize;
use tauri::State;

use super::servers::normalize_url;
use crate::events;
use crate::state::{AppState, blocking};

const TEST_TIMEOUT: Duration = Duration::from_secs(15);

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct LidarrInstancesState {
    instances: Vec<LidarrInstance>,
    selected_id: Option<String>,
}

async fn test(url: &str, api_key: &str) -> Result<()> {
    let client = LidarrClient::new(url, api_key)?;
    let ok = tokio::time::timeout(TEST_TIMEOUT, client.test_connection())
        .await
        .map_err(|_| AppError::Network("Connection timed out".into()))??;
    if ok {
        Ok(())
    } else {
        Err(AppError::Other("Server returned non-ok status".into()))
    }
}

/// Rebuilds the client when `id` is the selection, otherwise just announces
/// the list change.
async fn after_change(state: &AppState, selected: Option<String>, id: &str) -> Result<()> {
    if selected.as_deref() == Some(id) {
        state.reload_lidarr().await
    } else {
        events::lidarr_changed(&state.app);
        Ok(())
    }
}

#[tauri::command]
pub async fn lidarr_instances(state: State<'_, AppState>) -> Result<LidarrInstancesState> {
    let repo = state.lidarr_repo.clone();
    blocking(move || {
        Ok(LidarrInstancesState {
            instances: repo.load_all()?,
            selected_id: repo.load_selected_id()?,
        })
    })
    .await
}

#[tauri::command]
pub async fn lidarr_test(url: String, api_key: String) -> Result<()> {
    test(&normalize_url(&url), api_key.trim()).await
}

#[tauri::command]
pub async fn lidarr_add(
    state: State<'_, AppState>,
    name: String,
    url: String,
    api_key: String,
) -> Result<LidarrInstance> {
    let url = normalize_url(&url);
    let api_key = api_key.trim().to_string();
    test(&url, &api_key).await?;
    let name = name.trim();
    let instance = LidarrInstance {
        id: dapper_store::new_id(),
        name: if name.is_empty() { url.clone() } else { name.to_string() },
        url,
        ..LidarrInstance::default()
    };
    let repo = state.lidarr_repo.clone();
    let saved = instance.clone();
    let selected = blocking(move || {
        repo.add(&saved, &api_key)?;
        repo.load_selected_id()
    })
    .await?;
    after_change(&state, selected, &instance.id).await?;
    Ok(instance)
}

#[tauri::command]
pub async fn lidarr_update(
    state: State<'_, AppState>,
    instance: LidarrInstance,
    api_key: Option<String>,
) -> Result<()> {
    let instance = LidarrInstance {
        url: normalize_url(&instance.url),
        name: instance.name.trim().to_string(),
        ..instance
    };
    let new_key = api_key.map(|k| k.trim().to_string()).filter(|k| !k.is_empty());
    let resolved = match &new_key {
        Some(k) => k.clone(),
        None => {
            let (repo, id) = (state.lidarr_repo.clone(), instance.id.clone());
            blocking(move || repo.load_api_key(&id)).await?.unwrap_or_default()
        }
    };
    test(&instance.url, &resolved).await?;
    let repo = state.lidarr_repo.clone();
    let saved = instance.clone();
    let selected = blocking(move || {
        repo.update(&saved, new_key.as_deref())?;
        repo.load_selected_id()
    })
    .await?;
    after_change(&state, selected, &instance.id).await
}

#[tauri::command]
pub async fn lidarr_remove(state: State<'_, AppState>, id: String) -> Result<()> {
    let repo = state.lidarr_repo.clone();
    blocking(move || repo.remove(&id)).await?;
    state.reload_lidarr().await
}

#[tauri::command]
pub async fn lidarr_select(state: State<'_, AppState>, id: String) -> Result<()> {
    let repo = state.lidarr_repo.clone();
    blocking(move || {
        if !repo.load_all()?.iter().any(|i| i.id == id) {
            return Err(AppError::NotFound("Lidarr instance not found".into()));
        }
        repo.save_selected_id(Some(&id))
    })
    .await?;
    state.reload_lidarr().await
}

#[tauri::command]
pub async fn lidarr_root_folders(state: State<'_, AppState>) -> Result<Vec<LidarrRootFolder>> {
    state.lidarr()?.get_root_folders().await
}

#[tauri::command]
pub async fn lidarr_quality_profiles(state: State<'_, AppState>) -> Result<Vec<LidarrQualityProfile>> {
    state.lidarr()?.get_quality_profiles().await
}

#[tauri::command]
pub async fn lidarr_custom_filters(state: State<'_, AppState>) -> Result<Vec<LidarrCustomFilter>> {
    state.lidarr()?.get_custom_filters().await
}

async fn sorted_artists(state: &AppState) -> Result<Vec<LidarrArtist>> {
    let mut artists = state.lidarr()?.get_artists().await?;
    artists.sort_by(|a, b| a.name.cmp(&b.name));
    Ok(artists)
}

#[tauri::command]
pub async fn lidarr_artists(state: State<'_, AppState>) -> Result<Vec<LidarrArtist>> {
    sorted_artists(&state).await
}

/// Lidarr artists with no Navidrome artist of the same MusicBrainz id.
#[tauri::command]
pub async fn lidarr_only_artists(state: State<'_, AppState>) -> Result<Vec<LidarrArtist>> {
    let artists = sorted_artists(&state).await?;
    let navidrome: HashSet<String> = match state.session.get() {
        Some(s) => s.library.artists().await?.into_iter().filter_map(|a| a.music_brainz_id).collect(),
        None => HashSet::new(),
    };
    Ok(artists
        .into_iter()
        .filter(|a| a.is_in_lidarr() && !navidrome.contains(&a.mbid))
        .collect())
}

#[tauri::command]
pub async fn lidarr_artist_lookup(state: State<'_, AppState>, term: String) -> Result<Vec<LidarrArtist>> {
    state.lidarr()?.lookup_artists(&term).await
}

#[tauri::command]
pub async fn lidarr_add_artist(
    state: State<'_, AppState>,
    artist: LidarrArtist,
    root_folder_path: String,
    quality_profile_id: i64,
) -> Result<LidarrArtist> {
    state
        .lidarr()?
        .add_artist(&artist.mbid, &artist.name, &root_folder_path, quality_profile_id, None)
        .await
}

#[tauri::command]
pub async fn lidarr_artist_albums(state: State<'_, AppState>, artist_id: i64) -> Result<Vec<LidarrAlbum>> {
    state.lidarr()?.get_albums_by_artist(artist_id).await
}

#[tauri::command]
pub async fn lidarr_album_lookup(state: State<'_, AppState>, term: String) -> Result<Vec<LidarrAlbumLookup>> {
    state.lidarr()?.lookup_albums(&term).await
}

#[tauri::command]
pub async fn lidarr_add_album(
    state: State<'_, AppState>,
    lookup: LidarrAlbumLookup,
    root_folder_path: String,
    quality_profile_id: i64,
    search_on_add: bool,
) -> Result<i64> {
    state
        .lidarr()?
        .add_album(&lookup, &root_folder_path, quality_profile_id, search_on_add)
        .await
}

#[tauri::command]
pub async fn lidarr_search_artist(state: State<'_, AppState>, artist_id: i64) -> Result<()> {
    state.lidarr()?.trigger_artist_search(artist_id).await
}

#[tauri::command]
pub async fn lidarr_search_album(state: State<'_, AppState>, album_id: i64) -> Result<()> {
    state.lidarr()?.trigger_album_search(album_id).await
}

#[tauri::command]
pub async fn lidarr_releases(state: State<'_, AppState>, album_id: i64) -> Result<Vec<LidarrRelease>> {
    state.lidarr()?.search_releases(album_id).await
}

#[tauri::command]
pub async fn lidarr_grab(state: State<'_, AppState>, release: LidarrRelease) -> Result<()> {
    state.lidarr()?.grab_release(&release.raw).await
}
