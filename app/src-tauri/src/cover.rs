//! `cover://localhost/<serverId>/<coverArtId>?size=N` (Windows:
//! `http://cover.localhost/...`): cover art served from the disk cache
//! `covers/<serverId>/<hash>_<size>`, fetched from the selected server on miss.

use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::sync::Arc;

use dapper_api::endpoints;
use dapper_domain::{AppError, Result};
use md5::{Digest, Md5};
use tauri::http::{Request, Response, StatusCode, header};
use tauri::{AppHandle, Manager, UriSchemeResponder};

use crate::state::{AppState, blocking};

const CACHE_CONTROL: &str = "public, max-age=31536000, immutable";

pub struct CoverCache {
    dir: PathBuf,
    /// One lock per cache file so concurrent misses fetch once.
    inflight: parking_lot::Mutex<HashMap<PathBuf, Arc<tokio::sync::Mutex<()>>>>,
}

impl CoverCache {
    pub fn new(dir: PathBuf) -> Self {
        Self { dir, inflight: Default::default() }
    }

    pub fn dir(&self) -> &Path {
        &self.dir
    }

    fn key(cover_art_id: &str) -> String {
        hex::encode(Md5::digest(cover_art_id.as_bytes()))
    }

    fn path(&self, server_id: &str, cover_art_id: &str, size: u32) -> PathBuf {
        self.dir.join(server_id).join(format!("{}_{size}", Self::key(cover_art_id)))
    }

    /// Drops every cached size of one cover (after it was replaced).
    pub async fn evict(&self, server_id: &str, cover_art_id: &str) -> Result<()> {
        let dir = self.dir.join(server_id);
        let prefix = format!("{}_", Self::key(cover_art_id));
        blocking(move || {
            let entries = match std::fs::read_dir(&dir) {
                Ok(e) => e,
                Err(e) if e.kind() == std::io::ErrorKind::NotFound => return Ok(()),
                Err(e) => return Err(e.into()),
            };
            for entry in entries.flatten() {
                if entry.file_name().to_string_lossy().starts_with(&prefix) {
                    std::fs::remove_file(entry.path())?;
                }
            }
            Ok(())
        })
        .await
    }

    async fn get(&self, state: &AppState, server_id: &str, cover_art_id: &str, size: u32) -> Result<Option<Vec<u8>>> {
        let path = self.path(server_id, cover_art_id, size);
        if let Some(bytes) = read_if_exists(&path).await? {
            return Ok(Some(bytes));
        }
        let Some(session) = state.session.get().filter(|s| s.server.id == server_id) else {
            return Ok(None);
        };
        let lock = self.inflight.lock().entry(path.clone()).or_default().clone();
        let guard = lock.lock().await;
        let result = async {
            if let Some(bytes) = read_if_exists(&path).await? {
                return Ok(Some(bytes));
            }
            let mut params = vec![("id", cover_art_id.to_string())];
            if size > 0 {
                params.push(("size", size.to_string()));
            }
            let url = session.api.client().build_uri(endpoints::GET_COVER_ART, &params);
            let resp = session
                .api
                .client()
                .http()
                .get(url)
                .send()
                .await
                .map_err(|e| AppError::Network(e.without_url().to_string()))?;
            if resp.status().as_u16() == StatusCode::NOT_FOUND.as_u16() {
                return Ok(None);
            }
            let resp = resp
                .error_for_status()
                .map_err(|e| AppError::Network(e.without_url().to_string()))?;
            let is_image = resp
                .headers()
                .get(header::CONTENT_TYPE)
                .and_then(|v| v.to_str().ok())
                .is_some_and(|t| t.starts_with("image/"));
            let bytes = resp
                .bytes()
                .await
                .map_err(|e| AppError::Network(e.without_url().to_string()))?
                .to_vec();
            // Subsonic reports failures as a JSON envelope with HTTP 200.
            if !is_image || bytes.is_empty() {
                return Ok(None);
            }
            let dest = path.clone();
            blocking(move || write_atomic(&dest, &bytes).map(|()| Some(bytes))).await
        }
        .await;
        drop(guard);
        let mut inflight = self.inflight.lock();
        if Arc::strong_count(&lock) <= 2 {
            inflight.remove(&path);
        }
        result
    }

    /// Bytes on disk under `covers/`.
    pub async fn size(&self) -> Result<u64> {
        let dir = self.dir.clone();
        blocking(move || Ok(dir_size(&dir))).await
    }

    /// Removes the whole cache; returns (files, bytes) removed.
    pub async fn clear(&self) -> Result<(u64, u64)> {
        let dir = self.dir.clone();
        blocking(move || Ok(remove_files(&dir))).await
    }
}

async fn read_if_exists(path: &Path) -> Result<Option<Vec<u8>>> {
    match tokio::fs::read(path).await {
        Ok(b) => Ok(Some(b)),
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(None),
        Err(e) => Err(e.into()),
    }
}

fn write_atomic(path: &Path, data: &[u8]) -> Result<()> {
    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent)?;
    }
    let tmp = path.with_extension("part");
    std::fs::write(&tmp, data)?;
    std::fs::rename(&tmp, path)?;
    Ok(())
}

pub fn dir_size(dir: &Path) -> u64 {
    let Ok(entries) = std::fs::read_dir(dir) else {
        return 0;
    };
    entries
        .flatten()
        .map(|e| match e.file_type() {
            Ok(t) if t.is_dir() => dir_size(&e.path()),
            Ok(_) => e.metadata().map_or(0, |m| m.len()),
            Err(_) => 0,
        })
        .sum()
}

/// Deletes every file under `dir` (best effort, keeping the directories).
pub fn remove_files(dir: &Path) -> (u64, u64) {
    let Ok(entries) = std::fs::read_dir(dir) else {
        return (0, 0);
    };
    let (mut files, mut bytes) = (0, 0);
    for e in entries.flatten() {
        match e.file_type() {
            Ok(t) if t.is_dir() => {
                let (f, b) = remove_files(&e.path());
                files += f;
                bytes += b;
            }
            Ok(_) => {
                let len = e.metadata().map_or(0, |m| m.len());
                if std::fs::remove_file(e.path()).is_ok() {
                    files += 1;
                    bytes += len;
                }
            }
            Err(_) => {}
        }
    }
    (files, bytes)
}

fn sniff(bytes: &[u8]) -> &'static str {
    match bytes {
        [0xFF, 0xD8, 0xFF, ..] => "image/jpeg",
        [0x89, b'P', b'N', b'G', ..] => "image/png",
        [b'G', b'I', b'F', b'8', ..] => "image/gif",
        [b'R', b'I', b'F', b'F', _, _, _, _, b'W', b'E', b'B', b'P', ..] => "image/webp",
        [b'B', b'M', ..] => "image/bmp",
        _ => "application/octet-stream",
    }
}

fn parse(request: &Request<Vec<u8>>) -> Option<(String, String, u32)> {
    let uri = request.uri();
    let mut parts = uri.path().trim_start_matches('/').splitn(2, '/');
    let server_id = percent_decode(parts.next()?)?;
    let cover_art_id = percent_decode(parts.next()?)?;
    if server_id.is_empty() || cover_art_id.is_empty() {
        return None;
    }
    let size = uri
        .query()
        .into_iter()
        .flat_map(|q| q.split('&'))
        .find_map(|kv| kv.strip_prefix("size="))
        .map_or(Some(0), |s| s.parse().ok())?;
    Some((server_id, cover_art_id, size))
}

fn percent_decode(s: &str) -> Option<String> {
    let bytes = s.as_bytes();
    let mut out = Vec::with_capacity(bytes.len());
    let mut i = 0;
    while i < bytes.len() {
        if bytes[i] == b'%' {
            let hex = s.get(i + 1..i + 3)?;
            out.push(u8::from_str_radix(hex, 16).ok()?);
            i += 3;
        } else {
            out.push(bytes[i]);
            i += 1;
        }
    }
    String::from_utf8(out).ok()
}

fn respond(responder: UriSchemeResponder, status: StatusCode, body: Vec<u8>) {
    let mut builder = Response::builder().status(status);
    if status == StatusCode::OK {
        builder = builder
            .header(header::CONTENT_TYPE, sniff(&body))
            .header(header::CACHE_CONTROL, CACHE_CONTROL);
    }
    let response = builder.body(body).expect("static response parts");
    responder.respond(response);
}

/// Protocol handler registered for the `cover` scheme.
pub fn handle(app: &AppHandle, request: Request<Vec<u8>>, responder: UriSchemeResponder) {
    let Some((server_id, cover_art_id, size)) = parse(&request) else {
        respond(responder, StatusCode::NOT_FOUND, Vec::new());
        return;
    };
    let app = app.clone();
    tauri::async_runtime::spawn(async move {
        let Some(state) = app.try_state::<AppState>() else {
            respond(responder, StatusCode::SERVICE_UNAVAILABLE, Vec::new());
            return;
        };
        match state.covers.get(&state, &server_id, &cover_art_id, size).await {
            Ok(Some(bytes)) => respond(responder, StatusCode::OK, bytes),
            Ok(None) => respond(responder, StatusCode::NOT_FOUND, Vec::new()),
            Err(e) => {
                tracing::debug!(%server_id, error = %e, "cover fetch failed");
                respond(responder, StatusCode::BAD_GATEWAY, Vec::new());
            }
        }
    });
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_cover_urls() {
        let req = Request::builder()
            .uri("cover://localhost/srv-1/al-12%2F3_0?size=300")
            .body(Vec::new())
            .unwrap();
        assert_eq!(parse(&req), Some(("srv-1".into(), "al-12/3_0".into(), 300)));
        let req = Request::builder()
            .uri("http://cover.localhost/srv/abc")
            .body(Vec::new())
            .unwrap();
        assert_eq!(parse(&req), Some(("srv".into(), "abc".into(), 0)));
        let req = Request::builder().uri("cover://localhost/srv").body(Vec::new()).unwrap();
        assert_eq!(parse(&req), None);
        let req = Request::builder()
            .uri("cover://localhost/srv/x?size=big")
            .body(Vec::new())
            .unwrap();
        assert_eq!(parse(&req), None);
    }
}
