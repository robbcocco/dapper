use std::path::Path;
use std::time::Duration;

use dapper_api::{SubsonicApi, SubsonicClient};
use dapper_domain::{AppError, NavidromeServer, Result};
use dapper_library::Library;
use serde::Serialize;
use tauri::State;

use crate::events;
use crate::state::{AppState, blocking};

/// Outer limit for connection tests: per-stage HTTP timeouts may not fire
/// while macOS holds a connection for Local Network approval.
const TEST_TIMEOUT: Duration = Duration::from_secs(15);

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ServersState {
    servers: Vec<NavidromeServer>,
    selected_id: Option<String>,
}

pub(crate) fn normalize_url(url: &str) -> String {
    url.trim().trim_end_matches('/').to_string()
}

async fn ping(url: &str, username: &str, password: &str) -> Result<()> {
    let api = SubsonicApi::new(SubsonicClient::new(url, username, password)?);
    let ok = tokio::time::timeout(TEST_TIMEOUT, api.ping())
        .await
        .map_err(|_| AppError::Network("Connection timed out".into()))??;
    if ok {
        Ok(())
    } else {
        Err(AppError::Other("Server returned non-ok status".into()))
    }
}

/// Deletes a removed server's library cache and cover art.
fn remove_server_data(support_dir: &Path, id: &str) {
    let db = Library::db_path(support_dir, id);
    for suffix in ["", "-wal", "-shm"] {
        let mut p = db.clone().into_os_string();
        p.push(suffix);
        let _ = std::fs::remove_file(p);
    }
    let _ = std::fs::remove_dir_all(support_dir.join("covers").join(id));
}

#[tauri::command]
pub async fn servers_list(state: State<'_, AppState>) -> Result<ServersState> {
    let repo = state.servers.clone();
    blocking(move || {
        Ok(ServersState {
            servers: repo.load_all()?,
            selected_id: repo.load_selected_id()?,
        })
    })
    .await
}

#[tauri::command]
pub async fn server_test(url: String, username: String, password: String) -> Result<()> {
    ping(&normalize_url(&url), username.trim(), &password).await
}

#[tauri::command]
pub async fn server_add(
    state: State<'_, AppState>,
    name: String,
    url: String,
    username: String,
    password: String,
) -> Result<NavidromeServer> {
    let url = normalize_url(&url);
    let username = username.trim().to_string();
    ping(&url, &username, &password).await?;
    let name = name.trim();
    let server = NavidromeServer {
        id: dapper_store::new_id(),
        name: if name.is_empty() { url.clone() } else { name.to_string() },
        url,
        username,
    };
    let repo = state.servers.clone();
    let saved = server.clone();
    let selected = blocking(move || {
        repo.add(&saved, &password)?;
        repo.load_selected_id()
    })
    .await?;
    after_change(&state, selected, &server.id).await?;
    Ok(server)
}

/// Rebuilds the session when `id` is the selection (which announces it);
/// otherwise just announces the list change.
async fn after_change(state: &AppState, selected: Option<String>, id: &str) -> Result<()> {
    if selected.as_deref() == Some(id) {
        state.reload_session().await
    } else {
        events::server_changed(&state.app, selected);
        Ok(())
    }
}

#[tauri::command]
pub async fn server_update(
    state: State<'_, AppState>,
    id: String,
    name: String,
    url: String,
    username: String,
    password: Option<String>,
) -> Result<NavidromeServer> {
    let url = normalize_url(&url);
    let username = username.trim().to_string();
    let new_password = password.filter(|p| !p.is_empty());
    let resolved = match &new_password {
        Some(p) => p.clone(),
        None => {
            let (repo, id) = (state.servers.clone(), id.clone());
            blocking(move || repo.load_password(&id)).await?.unwrap_or_default()
        }
    };
    ping(&url, &username, &resolved).await?;
    let server = NavidromeServer { id, name: name.trim().to_string(), url, username };
    let repo = state.servers.clone();
    let saved = server.clone();
    let selected = blocking(move || {
        repo.update(&saved, new_password.as_deref())?;
        repo.load_selected_id()
    })
    .await?;
    after_change(&state, selected, &server.id).await?;
    Ok(server)
}

#[tauri::command]
pub async fn server_remove(state: State<'_, AppState>, id: String) -> Result<()> {
    let repo = state.servers.clone();
    let removed = id.clone();
    let was_current = state.session.selected_id().as_deref() == Some(id.as_str());
    let next = blocking(move || repo.remove(&removed)).await?;
    if was_current || state.session.selected_id() != next {
        state.reload_session().await?;
    } else {
        events::server_changed(&state.app, next);
    }
    let support = state.support_dir.clone();
    blocking(move || {
        remove_server_data(&support, &id);
        Ok(())
    })
    .await
}

#[tauri::command]
pub async fn server_select(state: State<'_, AppState>, id: String) -> Result<()> {
    let repo = state.servers.clone();
    blocking(move || {
        if !repo.load_all()?.iter().any(|s| s.id == id) {
            return Err(AppError::NotFound("Server not found".into()));
        }
        repo.save_selected_id(Some(&id))
    })
    .await?;
    state.reload_session().await
}
