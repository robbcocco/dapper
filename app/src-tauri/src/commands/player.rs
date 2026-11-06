use std::time::Duration;

use dapper_domain::{Result, Song};
use dapper_library::{SongSort, SortDir};
use serde::Serialize;
use tauri::State;

use crate::commands::library::SERVER_PAGE;
use crate::events::{self, PlayerPosition, PlayerState};
use crate::state::AppState;

#[derive(Serialize)]
pub struct PlayerSnapshot {
    state: PlayerState,
    position: PlayerPosition,
}

fn start_index(i: i64) -> usize {
    usize::try_from(i).unwrap_or(0)
}

#[tauri::command]
pub fn player_state(state: State<'_, AppState>) -> PlayerSnapshot {
    let s = state.player.state();
    let position = PlayerPosition {
        position_ms: events::millis(state.player.position()),
        duration_ms: events::millis(s.duration),
    };
    PlayerSnapshot { state: PlayerState::from(&s), position }
}

#[tauri::command]
pub fn player_play_songs(state: State<'_, AppState>, songs: Vec<Song>, start_index: i64) {
    state.player.set_queue(songs, self::start_index(start_index));
}

#[tauri::command]
pub async fn player_play_album(state: State<'_, AppState>, album_id: String, start_index: i64) -> Result<()> {
    let album = state.session()?.library.album(&album_id).await?;
    state.player.set_queue(album.songs, self::start_index(start_index));
    Ok(())
}

/// Every album's songs in the artist's album order; albums are fetched in
/// parallel (serial fetches made deep discographies feel frozen).
#[tauri::command]
pub async fn player_play_artist(state: State<'_, AppState>, artist_id: String) -> Result<()> {
    let library = state.session()?.library.clone();
    let albums = library.artist_albums(&artist_id).await?;
    let full = futures::future::try_join_all(albums.iter().map(|a| library.album(&a.id))).await?;
    let songs: Vec<Song> = full.into_iter().flat_map(|a| a.songs).collect();
    if !songs.is_empty() {
        state.player.set_queue(songs, 0);
    }
    Ok(())
}

#[tauri::command]
pub async fn player_play_playlist(state: State<'_, AppState>, playlist_id: String, start_index: i64) -> Result<()> {
    let playlist = state.session()?.library.playlist(&playlist_id).await?;
    state.player.set_queue(playlist.songs, self::start_index(start_index));
    Ok(())
}

/// The whole song table in the given order (the Songs page plays the list).
#[tauri::command]
pub async fn player_play_library(
    state: State<'_, AppState>,
    sort: SongSort,
    desc: bool,
    start_index: i64,
) -> Result<()> {
    let library = state.session()?.library.clone();
    let dir = if desc { SortDir::Desc } else { SortDir::Asc };
    let songs = if library.is_ready() {
        library.songs_page(0, i64::MAX, sort, dir).await?.items
    } else {
        let mut songs = Vec::new();
        loop {
            let page = library.songs_page(songs.len() as i64, SERVER_PAGE, sort, dir).await?.items;
            let short = (page.len() as i64) < SERVER_PAGE;
            songs.extend(page);
            if short {
                break songs;
            }
        }
    };
    if !songs.is_empty() {
        state.player.set_queue(songs, self::start_index(start_index));
    }
    Ok(())
}

#[tauri::command]
pub fn player_toggle(state: State<'_, AppState>) {
    state.player.toggle_play_pause();
}

#[tauri::command]
pub fn player_next(state: State<'_, AppState>) {
    state.player.next();
}

#[tauri::command]
pub fn player_previous(state: State<'_, AppState>) {
    state.player.previous();
}

#[tauri::command]
pub fn player_seek(state: State<'_, AppState>, position_ms: f64) {
    state.player.seek(Duration::from_millis(position_ms.max(0.0) as u64));
}

#[tauri::command]
pub fn player_set_volume(state: State<'_, AppState>, volume: f32) {
    state.player.set_volume(volume);
}

#[tauri::command]
pub fn player_toggle_shuffle(state: State<'_, AppState>) {
    state.player.toggle_shuffle();
}

#[tauri::command]
pub fn player_cycle_repeat(state: State<'_, AppState>) {
    state.player.cycle_repeat();
}
