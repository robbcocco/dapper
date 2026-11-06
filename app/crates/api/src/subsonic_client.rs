use std::time::{Duration, SystemTime, UNIX_EPOCH};

use dapper_domain::{AppError, Result};
use md5::{Digest, Md5};
use rand::RngExt;
use serde_json::Value;
use url::Url;

use crate::http::{join, net_err, parse_base, redact_userinfo};

pub const API_VERSION: &str = "1.16.1";
pub const CLIENT_NAME: &str = "dapper";
pub const RESPONSE_FORMAT: &str = "json";

/// Subsonic REST endpoint paths.
pub mod endpoints {
    pub const PING: &str = "/rest/ping";
    pub const GET_ARTISTS: &str = "/rest/getArtists";
    pub const GET_ARTIST: &str = "/rest/getArtist";
    pub const GET_ALBUM: &str = "/rest/getAlbum";
    pub const GET_COVER_ART: &str = "/rest/getCoverArt";
    pub const GET_ALBUM_LIST2: &str = "/rest/getAlbumList2";
    pub const GET_PLAYLISTS: &str = "/rest/getPlaylists";
    pub const GET_PLAYLIST: &str = "/rest/getPlaylist";
    pub const GET_STARRED2: &str = "/rest/getStarred2";
    pub const GET_GENRES: &str = "/rest/getGenres";
    pub const GET_SCAN_STATUS: &str = "/rest/getScanStatus";
    pub const SEARCH3: &str = "/rest/search3";
    pub const STREAM: &str = "/rest/stream";
    pub const DOWNLOAD: &str = "/rest/download";
    pub const CREATE_PLAYLIST: &str = "/rest/createPlaylist";
    pub const UPDATE_PLAYLIST: &str = "/rest/updatePlaylist";
    pub const DELETE_PLAYLIST: &str = "/rest/deletePlaylist";
    pub const STAR: &str = "/rest/star";
    pub const UNSTAR: &str = "/rest/unstar";
    pub const SCROBBLE: &str = "/rest/scrobble";
    pub const GET_LYRICS_BY_SONG_ID: &str = "/rest/getLyricsBySongId";
    pub const SET_RATING: &str = "/rest/setRating";
}

/// Query parameters; repeated keys encode Subsonic list params (`songId=a&songId=b`).
pub type Params = Vec<(&'static str, String)>;

fn base36(mut n: u64) -> String {
    const DIGITS: &[u8; 36] = b"0123456789abcdefghijklmnopqrstuvwxyz";
    if n == 0 {
        return "0".into();
    }
    let mut out = Vec::with_capacity(13);
    while n > 0 {
        out.push(DIGITS[(n % 36) as usize]);
        n /= 36;
    }
    out.reverse();
    String::from_utf8(out).expect("ascii")
}

/// Millisecond timestamp + 32 random bits, both base-36, so two requests in
/// the same millisecond can't produce identical salt+token pairs.
fn generate_salt() -> String {
    let ms = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_millis() as u64)
        .unwrap_or(0);
    let suffix: u32 = rand::rng().random();
    format!("{}{}", base36(ms), base36(suffix.into()))
}

#[derive(Clone)]
pub struct SubsonicClient {
    http: reqwest::Client,
    base: Url,
    username: String,
    password: String,
}

impl std::fmt::Debug for SubsonicClient {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("SubsonicClient")
            .field("base", &redact_userinfo(self.base.as_str()))
            .field("username", &self.username)
            .finish()
    }
}

impl SubsonicClient {
    pub fn new(base_url: &str, username: &str, password: &str) -> Result<Self> {
        let http = reqwest::Client::builder()
            .connect_timeout(Duration::from_secs(10))
            .read_timeout(Duration::from_secs(30))
            .build()
            .map_err(net_err)?;
        Ok(Self {
            http,
            base: parse_base(base_url)?,
            username: username.into(),
            password: password.into(),
        })
    }

    /// The underlying HTTP client (shared connection pool), e.g. for downloads.
    pub fn http(&self) -> &reqwest::Client {
        &self.http
    }

    /// Fresh Subsonic auth + format params; each call generates a new salt.
    pub fn auth_params(username: &str, password: &str) -> [(&'static str, String); 6] {
        let salt = generate_salt();
        let token = hex::encode(Md5::digest(format!("{password}{salt}").as_bytes()));
        [
            ("u", username.to_string()),
            ("t", token),
            ("s", salt),
            ("v", API_VERSION.into()),
            ("c", CLIENT_NAME.into()),
            ("f", RESPONSE_FORMAT.into()),
        ]
    }

    /// Signed URL for endpoints consumed directly (stream, coverArt, download).
    /// Preserves any base-URL path prefix (`https://host/navidrome`).
    pub fn build_uri(&self, path: &str, extra: &[(&str, String)]) -> Url {
        let mut url = join(&self.base, path);
        {
            let mut q = url.query_pairs_mut();
            for (k, v) in Self::auth_params(&self.username, &self.password) {
                q.append_pair(k, &v);
            }
            for (k, v) in extra {
                q.append_pair(k, v);
            }
        }
        url
    }

    /// GETs `path` and returns the decoded `subsonic-response` object.
    /// HTTP 401/403 and envelope codes 40/41 → `AppError::Auth`; other
    /// envelope failures → `AppError::Subsonic` with the server's code.
    pub async fn get(&self, path: &str, params: &[(&str, String)]) -> Result<Value> {
        tracing::debug!(path, "subsonic GET");
        let url = self.build_uri(path, params);
        let resp = self.http.get(url).send().await.map_err(net_err)?;
        let status = resp.status().as_u16();
        // A reverse proxy guarding Navidrome answers with an HTML 401/403 page,
        // so classify by status before attempting to decode anything.
        if status == 401 || status == 403 {
            return Err(AppError::Auth);
        }
        let body = resp.bytes().await.map_err(net_err)?;
        let decoded: Option<Value> = if body.is_empty() {
            None
        } else {
            serde_json::from_slice(&body).ok()
        };
        let envelope = decoded
            .as_ref()
            .and_then(|d| d.get("subsonic-response"))
            .filter(|e| e.is_object());

        if let Some(env) = envelope
            && env.get("status").and_then(Value::as_str) == Some("failed")
        {
            let error = env.get("error");
            let code = error
                .and_then(|e| e.get("code"))
                .and_then(Value::as_i64)
                .unwrap_or(0) as i32;
            if code == 40 || code == 41 {
                return Err(AppError::Auth);
            }
            let message = error
                .and_then(|e| e.get("message"))
                .and_then(Value::as_str)
                .unwrap_or("Unknown error")
                .to_string();
            return Err(AppError::Subsonic { message, code });
        }
        if status >= 400 {
            return Err(AppError::Subsonic {
                message: format!("Server error ({status})"),
                code: 0,
            });
        }
        if body.is_empty() {
            return Err(AppError::Subsonic {
                message: "Empty response from server".into(),
                code: 0,
            });
        }
        match decoded {
            Some(Value::Object(mut root)) => match root.remove("subsonic-response") {
                Some(env @ Value::Object(_)) => Ok(env),
                _ => Err(malformed()),
            },
            _ => Err(malformed()),
        }
    }
}

pub(crate) fn malformed() -> AppError {
    AppError::Subsonic {
        message: "Malformed response from server".into(),
        code: 0,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn base36_matches_dart_to_radix_string() {
        assert_eq!(base36(0), "0");
        assert_eq!(base36(35), "z");
        assert_eq!(base36(36), "10");
        assert_eq!(base36(u32::MAX.into()), "1z141z3");
    }

    #[test]
    fn join_keeps_subpath() {
        let b = Url::parse("https://h/sub/").unwrap();
        assert_eq!(join(&b, "/rest/ping").as_str(), "https://h/sub/rest/ping");
        assert_eq!(join(&b, "rest/ping").as_str(), "https://h/sub/rest/ping");
    }
}
