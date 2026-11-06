use std::sync::Arc;

use dapper_domain::{
    Album, AppError, Artist, Genre, Lyrics, MbReleaseGroup, Playlist, Result, SearchResults, Song,
};
use dapper_library::{AlbumSort, SearchLimits, SongSort, SortDir};
use serde::{Deserialize, Serialize};
use serde_json::{Map, Value};
use tauri::State;

use crate::events;
use crate::session::Session;
use crate::state::{AppState, SyncStatus};

/// Server page size used when listing every song id before the first sync.
pub(crate) const SERVER_PAGE: i64 = 500;

/// `Page<T>` in types.ts. Before the first completed sync the library pages
/// from the server without a known total; `total` is then the best known
/// lower bound, one past the loaded rows while the window came back full so
/// virtual lists keep requesting.
#[derive(Serialize)]
pub struct Page<T> {
    total: i64,
    items: Vec<T>,
}

impl<T> Page<T> {
    fn from_library(page: dapper_library::Page<T>, offset: i64, limit: i64) -> Self {
        let len = page.items.len() as i64;
        let total = page
            .total
            .unwrap_or_else(|| offset + len + i64::from(len == limit && limit > 0));
        Self { total, items: page.items }
    }
}

#[derive(Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct SongUpdateFields {
    title: Option<String>,
    artist: Option<String>,
    album: Option<String>,
    album_artist: Option<String>,
    track: Option<i64>,
    disc: Option<i64>,
    year: Option<i64>,
    genre: Option<String>,
}

impl SongUpdateFields {
    /// Navidrome's native song model field names.
    fn into_json(self) -> Value {
        let mut m = Map::new();
        let mut put = |k: &str, v: Option<Value>| {
            if let Some(v) = v {
                m.insert(k.into(), v);
            }
        };
        put("title", self.title.map(Value::from));
        put("artist", self.artist.map(Value::from));
        put("album", self.album.map(Value::from));
        put("albumArtist", self.album_artist.map(Value::from));
        put("trackNumber", self.track.map(Value::from));
        put("discNumber", self.disc.map(Value::from));
        put("year", self.year.map(Value::from));
        put("genre", self.genre.map(Value::from));
        Value::Object(m)
    }
}

fn session(state: &AppState) -> Result<Arc<Session>> {
    state.session()
}

#[tauri::command]
pub fn library_sync(state: State<'_, AppState>, force: bool) {
    state.start_sync(force);
}

#[tauri::command]
pub fn library_sync_status(state: State<'_, AppState>) -> SyncStatus {
    state.sync.borrow().clone()
}

#[tauri::command]
pub async fn artists_list(state: State<'_, AppState>) -> Result<Vec<Artist>> {
    session(&state)?.library.artists().await
}

#[tauri::command]
pub async fn artist_albums(state: State<'_, AppState>, artist_id: String) -> Result<Vec<Album>> {
    session(&state)?.library.artist_albums(&artist_id).await
}

#[tauri::command]
pub async fn album_get(state: State<'_, AppState>, album_id: String) -> Result<Album> {
    session(&state)?.library.album(&album_id).await
}

#[tauri::command]
pub async fn albums_recent(state: State<'_, AppState>, limit: i64) -> Result<Vec<Album>> {
    session(&state)?.library.recent_albums(limit).await
}

#[tauri::command]
pub async fn albums_window(
    state: State<'_, AppState>,
    offset: i64,
    limit: i64,
    sort: AlbumSort,
) -> Result<Page<Album>> {
    let dir = if sort == AlbumSort::Recent { SortDir::Desc } else { SortDir::Asc };
    let page = session(&state)?.library.albums_page(offset, limit, sort, dir).await?;
    Ok(Page::from_library(page, offset, limit))
}

fn dir(desc: bool) -> SortDir {
    if desc { SortDir::Desc } else { SortDir::Asc }
}

#[tauri::command]
pub async fn songs_window(
    state: State<'_, AppState>,
    offset: i64,
    limit: i64,
    sort: SongSort,
    desc: bool,
) -> Result<Page<Song>> {
    let page = session(&state)?.library.songs_page(offset, limit, sort, dir(desc)).await?;
    Ok(Page::from_library(page, offset, limit))
}

#[tauri::command]
pub async fn songs_ids(state: State<'_, AppState>, sort: SongSort, desc: bool) -> Result<Vec<String>> {
    let library = session(&state)?.library.clone();
    if library.is_ready() {
        return library.song_ids(0, i64::MAX, sort, dir(desc)).await;
    }
    let mut ids = Vec::new();
    loop {
        let page = library.song_ids(ids.len() as i64, SERVER_PAGE, sort, dir(desc)).await?;
        let short = (page.len() as i64) < SERVER_PAGE;
        ids.extend(page);
        if short {
            return Ok(ids);
        }
    }
}

#[tauri::command]
pub async fn genres_list(state: State<'_, AppState>) -> Result<Vec<Genre>> {
    session(&state)?.library.genres().await
}

#[tauri::command]
pub async fn genre_albums(state: State<'_, AppState>, genre: String) -> Result<Vec<Album>> {
    session(&state)?.library.albums_by_genre(&genre).await
}

#[tauri::command]
pub async fn search(state: State<'_, AppState>, query: String) -> Result<SearchResults> {
    session(&state)?.library.search(&query, SearchLimits::default()).await
}

#[tauri::command]
pub async fn starred_ids(state: State<'_, AppState>) -> Result<Vec<String>> {
    Ok(session(&state)?.library.starred_song_ids().await?.into_iter().collect())
}

#[tauri::command]
pub async fn star_set(state: State<'_, AppState>, id: String, starred: bool) -> Result<()> {
    let s = session(&state)?;
    if starred { s.library.star(&id).await } else { s.library.unstar(&id).await }
}

#[tauri::command]
pub async fn rating_set(state: State<'_, AppState>, id: String, rating: i32) -> Result<()> {
    session(&state)?.library.set_rating(&id, rating.clamp(0, 5)).await
}

#[tauri::command]
pub async fn lyrics_get(state: State<'_, AppState>, song_id: String) -> Result<Option<Lyrics>> {
    session(&state)?.api.get_lyrics(&song_id).await
}

#[tauri::command]
pub async fn playlists_list(state: State<'_, AppState>) -> Result<Vec<Playlist>> {
    session(&state)?.library.playlists().await
}

#[tauri::command]
pub async fn playlist_get(state: State<'_, AppState>, id: String) -> Result<Playlist> {
    session(&state)?.library.playlist(&id).await
}

#[tauri::command]
pub async fn playlist_create(
    state: State<'_, AppState>,
    name: String,
    song_ids: Vec<String>,
) -> Result<Playlist> {
    let created = session(&state)?.library.create_playlist(&name, &song_ids).await?;
    events::library_changed(&state.app);
    Ok(created)
}

#[tauri::command]
pub async fn playlist_rename(state: State<'_, AppState>, id: String, name: String) -> Result<()> {
    session(&state)?.library.rename_playlist(&id, &name).await?;
    events::library_changed(&state.app);
    Ok(())
}

#[tauri::command]
pub async fn playlist_add_songs(state: State<'_, AppState>, id: String, song_ids: Vec<String>) -> Result<()> {
    session(&state)?.library.add_to_playlist(&id, &song_ids).await?;
    events::library_changed(&state.app);
    Ok(())
}

#[tauri::command]
pub async fn playlist_remove_song(state: State<'_, AppState>, id: String, index: i64) -> Result<()> {
    session(&state)?.library.remove_from_playlist(&id, &[index]).await?;
    events::library_changed(&state.app);
    Ok(())
}

#[tauri::command]
pub async fn playlist_delete(state: State<'_, AppState>, id: String) -> Result<()> {
    session(&state)?.library.delete_playlist(&id).await?;
    events::library_changed(&state.app);
    Ok(())
}

#[tauri::command]
pub async fn song_update(state: State<'_, AppState>, song_id: String, fields: SongUpdateFields) -> Result<()> {
    session(&state)?.navidrome.update_song(&song_id, &fields.into_json()).await?;
    events::library_changed(&state.app);
    Ok(())
}

#[tauri::command]
pub async fn mb_search_release_groups(
    state: State<'_, AppState>,
    album: String,
    artist: String,
) -> Result<Vec<MbReleaseGroup>> {
    Ok(state.mb.search_release_groups(&album, Some(&artist)).await)
}

async fn set_album_cover(state: &AppState, album_id: &str, image: Vec<u8>) -> Result<()> {
    let s = session(state)?;
    s.navidrome.upload_album_cover(album_id, image).await?;
    if let Ok(album) = s.library.album(album_id).await
        && let Some(cover) = album.cover_art_id
    {
        state.covers.evict(&s.server.id, &cover).await?;
    }
    events::library_changed(&state.app);
    Ok(())
}

#[tauri::command]
pub async fn album_cover_from_release_group(
    state: State<'_, AppState>,
    album_id: String,
    mbid: String,
) -> Result<()> {
    let image = state
        .mb
        .fetch_cover_art(&mbid)
        .await
        .ok_or_else(|| AppError::NotFound("No cover art found for this release".into()))?;
    set_album_cover(&state, &album_id, image).await
}
