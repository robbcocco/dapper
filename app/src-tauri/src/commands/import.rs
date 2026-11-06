use dapper_domain::{Result, Song};
use dapper_import::ImportState;
use tauri::{Manager, State};

use crate::state::AppState;

/// Runs in the background; progress arrives as `import-state` events.
#[tauri::command]
pub fn import_start(state: State<'_, AppState>, url: String) {
    let app = state.app.clone();
    tauri::async_runtime::spawn(async move {
        app.state::<AppState>().import.start_import(&url).await;
    });
}

#[tauri::command]
pub fn import_set_selection(state: State<'_, AppState>, index: usize, song_id: Option<String>, song: Option<Song>) {
    state.import.set_selection(index, song_id, song);
}

#[tauri::command]
pub async fn import_manual_search(state: State<'_, AppState>, query: String) -> Result<Vec<Song>> {
    Ok(state.import.manual_search(&query).await)
}

#[tauri::command]
pub fn import_commit(state: State<'_, AppState>, name: Option<String>) {
    let app = state.app.clone();
    tauri::async_runtime::spawn(async move {
        app.state::<AppState>().import.commit(name.as_deref()).await;
    });
}

#[tauri::command]
pub fn import_reset(state: State<'_, AppState>) {
    state.import.reset();
}

#[tauri::command]
pub fn import_state(state: State<'_, AppState>) -> ImportState {
    state.import.state()
}
