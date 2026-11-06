//! Event names and payloads pushed to the UI (see the IPC contract).

use std::sync::Arc;
use std::time::Duration;

use dapper_audio::PlaybackState;
use dapper_domain::{RepeatMode, Song};
use serde::Serialize;
use tauri::{AppHandle, Emitter};
use tokio::sync::watch;

pub const SERVER_CHANGED: &str = "server-changed";
pub const LIBRARY_SYNC: &str = "library-sync";
pub const LIBRARY_CHANGED: &str = "library-changed";
pub const PLAYER_STATE: &str = "player-state";
pub const PLAYER_POSITION: &str = "player-position";
pub const DEVICES: &str = "devices";
pub const SCROBBLE_IMPORT: &str = "scrobble-import";
pub const MANIFEST_REVISION: &str = "manifest-revision";
pub const TRANSFER_TASKS: &str = "transfer-tasks";
pub const TRANSFER_PROGRESS: &str = "transfer-progress";
pub const TRANSFER_PAUSED: &str = "transfer-paused";
pub const QUEUE_STATUS: &str = "queue-status";
pub const ACTION_ERROR: &str = "action-error";
pub const LIDARR_CHANGED: &str = "lidarr-changed";
pub const IMPORT_STATE: &str = "import-state";

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ServerChanged {
    pub selected_id: Option<String>,
}

#[derive(Debug, Clone, Serialize)]
pub struct ActionError {
    pub message: String,
}

/// `PlayerState` in types.ts (`durationMs` instead of the engine's `duration`).
#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct PlayerState {
    pub current_song: Option<Song>,
    pub queue: Arc<[Song]>,
    pub current_index: usize,
    pub is_playing: bool,
    pub is_buffering: bool,
    pub duration_ms: u64,
    pub volume: f32,
    pub is_shuffled: bool,
    pub repeat_mode: RepeatMode,
    pub error_message: Option<String>,
}

impl From<&PlaybackState> for PlayerState {
    fn from(s: &PlaybackState) -> Self {
        Self {
            current_song: s.current_song.clone(),
            queue: s.queue.clone(),
            current_index: s.current_index,
            is_playing: s.is_playing,
            is_buffering: s.is_buffering,
            duration_ms: millis(s.duration),
            volume: s.volume,
            is_shuffled: s.is_shuffled,
            repeat_mode: s.repeat_mode,
            error_message: s.error_message.clone(),
        }
    }
}

#[derive(Debug, Clone, Copy, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct PlayerPosition {
    pub position_ms: u64,
    pub duration_ms: u64,
}

pub fn millis(d: Duration) -> u64 {
    u64::try_from(d.as_millis()).unwrap_or(u64::MAX)
}

pub fn emit<P: Serialize + Clone>(app: &AppHandle, event: &str, payload: P) {
    if let Err(e) = app.emit(event, payload) {
        tracing::warn!(event, error = %e, "event emit failed");
    }
}

pub fn library_changed(app: &AppHandle) {
    emit(app, LIBRARY_CHANGED, serde_json::json!({}));
}

pub fn server_changed(app: &AppHandle, selected_id: Option<String>) {
    emit(app, SERVER_CHANGED, ServerChanged { selected_id });
}

pub fn lidarr_changed(app: &AppHandle) {
    emit(app, LIDARR_CHANGED, serde_json::json!({}));
}

pub fn action_error(app: &AppHandle, message: impl Into<String>) {
    emit(app, ACTION_ERROR, ActionError { message: message.into() });
}

/// Emits the current value of `rx` and every later change until the sender
/// is dropped.
pub fn forward<T, P>(
    app: &AppHandle,
    event: &'static str,
    mut rx: watch::Receiver<T>,
    map: impl Fn(&T) -> P + Send + 'static,
) where
    T: Send + Sync + 'static,
    P: Serialize + Clone,
{
    let app = app.clone();
    tauri::async_runtime::spawn(async move {
        loop {
            let payload = map(&rx.borrow_and_update());
            emit(&app, event, payload);
            if rx.changed().await.is_err() {
                break;
            }
        }
    });
}
