use std::sync::LazyLock;
use std::time::Duration;

use dapper_domain::{AppError, PlaylistProvider, Result, SpotifyPlaylistData, SpotifyTrack};
use regex::Regex;
use reqwest::header::{ACCEPT, ACCEPT_LANGUAGE, HeaderMap, HeaderValue, USER_AGENT};
use serde_json::{Map, Value};

use crate::http::{failure_kind, net_err};
use crate::tidal_scraper::TidalScraper;

/// User-actionable scrape failure (Dart `SpotifyScrapeException`).
pub(crate) fn scrape_error(msg: impl Into<String>) -> AppError {
    AppError::Other(msg.into())
}

/// One scraper per upstream playlist provider.
pub enum PlaylistScraper {
    Spotify(SpotifyScraper),
    Tidal(TidalScraper),
}

impl PlaylistScraper {
    /// The first provider that recognises `input` (URL, URI or bare id).
    pub fn detect(input: &str) -> Option<Self> {
        if SpotifyScraper::parse_playlist_id(input).is_some() {
            return Some(Self::Spotify(SpotifyScraper::new()));
        }
        if TidalScraper::parse_playlist_id(input).is_some() {
            return Some(Self::Tidal(TidalScraper::new()));
        }
        None
    }

    pub fn provider(&self) -> PlaylistProvider {
        match self {
            Self::Spotify(_) => PlaylistProvider::Spotify,
            Self::Tidal(_) => PlaylistProvider::Tidal,
        }
    }

    pub async fn fetch_playlist(&self, id_or_url: &str) -> Result<SpotifyPlaylistData> {
        match self {
            Self::Spotify(s) => s.fetch_playlist(id_or_url).await,
            Self::Tidal(t) => t.fetch_playlist(id_or_url).await,
        }
    }
}

static BARE_ID: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"^[A-Za-z0-9]{22}$").unwrap());
static URI_ID: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"spotify:playlist:([A-Za-z0-9]{22})").unwrap());
static URL_ID: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(r"open\.spotify\.com/(?:[a-z\-]+/)?(?:embed/)?playlist/([A-Za-z0-9]{22})").unwrap()
});
static NEXT_DATA: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(r#"(?s)<script[^>]*id="__NEXT_DATA__"[^>]*>(.*?)</script>"#).unwrap()
});

/// Public Spotify playlist via the unauthenticated embed page, whose
/// `__NEXT_DATA__` script blob carries the playlist and its track list. No
/// documented contract exists, so several shapes are tolerated.
pub struct SpotifyScraper {
    http: reqwest::Client,
    base: String,
}

impl Default for SpotifyScraper {
    fn default() -> Self {
        Self::new()
    }
}

impl SpotifyScraper {
    pub fn new() -> Self {
        Self::with_base_url("https://open.spotify.com")
    }

    /// Alternate embed host (tests).
    pub fn with_base_url(base: &str) -> Self {
        let mut headers = HeaderMap::new();
        // The embed page short-circuits to a stub for bot-looking UAs.
        headers.insert(
            USER_AGENT,
            HeaderValue::from_static(
                "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36",
            ),
        );
        headers.insert(
            ACCEPT,
            HeaderValue::from_static(
                "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
            ),
        );
        headers.insert(ACCEPT_LANGUAGE, HeaderValue::from_static("en-US,en;q=0.9"));
        let http = reqwest::Client::builder()
            .default_headers(headers)
            .connect_timeout(Duration::from_secs(10))
            .read_timeout(Duration::from_secs(15))
            .build()
            .expect("static HTTP client config");
        Self {
            http,
            base: base.trim_end_matches('/').to_string(),
        }
    }

    /// Playlist id from a bare 22-char id, `spotify:playlist:<id>` or an
    /// `open.spotify.com/[locale/][embed/]playlist/<id>` URL.
    pub fn parse_playlist_id(input: &str) -> Option<String> {
        let trimmed = input.trim();
        if trimmed.is_empty() {
            return None;
        }
        if BARE_ID.is_match(trimmed) {
            return Some(trimmed.to_string());
        }
        URI_ID
            .captures(trimmed)
            .or_else(|| URL_ID.captures(trimmed))
            .map(|c| c[1].to_string())
    }

    pub async fn fetch_playlist(&self, id_or_url: &str) -> Result<SpotifyPlaylistData> {
        let Some(id) = Self::parse_playlist_id(id_or_url) else {
            return Err(scrape_error(
                "Could not find a Spotify playlist ID in that text.",
            ));
        };
        let url = format!("{}/embed/playlist/{id}", self.base);
        let resp =
            self.http.get(url).send().await.map_err(|e| {
                scrape_error(format!("Spotify request failed ({}).", failure_kind(&e)))
            })?;
        if !resp.status().is_success() {
            return Err(scrape_error(format!(
                "Spotify request failed ({}).",
                resp.status().as_u16()
            )));
        }
        let html = resp.text().await.map_err(net_err)?;
        if html.is_empty() {
            return Err(scrape_error("Empty response from Spotify."));
        }
        parse_embed_html(&html)
    }
}

pub(crate) fn parse_embed_html(html: &str) -> Result<SpotifyPlaylistData> {
    let Some(blob) = NEXT_DATA
        .captures(html)
        .map(|c| c.get(1).expect("group").as_str())
    else {
        return Err(scrape_error(
            "Spotify changed its embed format — could not find playlist data. \
             Try again later or paste a different playlist.",
        ));
    };
    let decoded: Value = serde_json::from_str(blob)
        .map_err(|_| scrape_error("Spotify returned malformed playlist data."))?;

    let Some(entity) = navigate_to_entity(&decoded) else {
        tracing::debug!("SpotifyScraper: entity not found in payload");
        return Err(scrape_error(
            "Spotify did not include any track data for this playlist. \
             It may be private, region-locked, or removed.",
        ));
    };

    let name = match entity
        .get("name")
        .filter(|v| !v.is_null())
        .or_else(|| entity.get("title").filter(|v| !v.is_null()))
    {
        Some(Value::String(s)) => s.clone(),
        Some(other) => other.to_string(),
        None => "Spotify Playlist".into(),
    };

    let raw_tracks = extract_track_list(entity);
    if raw_tracks.is_empty() {
        return Err(scrape_error(
            "Playlist is empty (or its tracks are not visible without login).",
        ));
    }

    let tracks: Vec<SpotifyTrack> = raw_tracks
        .iter()
        .filter_map(Value::as_object)
        .filter_map(|raw| {
            let title = pick_string(raw, &["title", "name"])?;
            Some(SpotifyTrack {
                title,
                artist: extract_artist(raw),
                album: None,
                duration_ms: pick_int(raw, &["duration", "durationMs", "duration_ms"]),
            })
        })
        .collect();
    if tracks.is_empty() {
        return Err(scrape_error("Could not read any tracks from the playlist."));
    }

    // The embed caps at 100 tracks; flag it so the UI can warn.
    let advertised = pick_int(entity, &["trackCount"]).unwrap_or(tracks.len() as i64);
    let truncated = (tracks.len() as i64) < advertised;
    Ok(SpotifyPlaylistData {
        name,
        tracks,
        truncated,
        provider: PlaylistProvider::Spotify,
    })
}

/// Known paths first, then a depth-limited search (in document order) for any
/// object that looks like the playlist entity.
fn navigate_to_entity(root: &Value) -> Option<&Map<String, Value>> {
    if !root.is_object() {
        return None;
    }
    const PATHS: [&[&str]; 3] = [
        &["props", "pageProps", "state", "data", "entity"],
        &["props", "pageProps", "initialState", "data", "entity"],
        &["props", "pageProps", "entity"],
    ];
    for path in PATHS {
        let hit = path.iter().try_fold(root, |cur, k| {
            cur.as_object()?.get(*k).filter(|v| !v.is_null())
        });
        if let Some(Value::Object(m)) = hit
            && looks_like_entity(m)
        {
            return Some(m);
        }
    }
    search_entity(root, 0)
}

fn looks_like_entity(m: &Map<String, Value>) -> bool {
    m.contains_key("trackList") || m.contains_key("audioItems") || m.contains_key("tracks")
}

fn search_entity(node: &Value, depth: usize) -> Option<&Map<String, Value>> {
    if depth > 6 {
        return None;
    }
    match node {
        Value::Object(m) if looks_like_entity(m) => Some(m),
        Value::Object(m) => m.values().find_map(|v| search_entity(v, depth + 1)),
        Value::Array(items) => items.iter().find_map(|v| search_entity(v, depth + 1)),
        _ => None,
    }
}

fn extract_track_list(entity: &Map<String, Value>) -> &[Value] {
    // Dart `entity['trackList'] ?? entity['audioItems']`: a present non-null
    // trackList shadows audioItems even when it isn't a list.
    let primary = entity
        .get("trackList")
        .filter(|v| !v.is_null())
        .or_else(|| entity.get("audioItems"));
    if let Some(Value::Array(items)) = primary {
        return items;
    }
    match entity.get("tracks") {
        Some(Value::Array(items)) => items,
        Some(Value::Object(m)) => match m.get("items") {
            Some(Value::Array(items)) => items,
            _ => &[],
        },
        _ => &[],
    }
}

fn extract_artist(raw: &Map<String, Value>) -> String {
    // The embed usually carries a comma-joined artist string in `subtitle`.
    if let Some(s) = pick_string(raw, &["subtitle", "artist"]) {
        return s;
    }
    if let Some(Value::Array(artists)) = raw.get("artists") {
        let names: Vec<String> = artists
            .iter()
            .filter_map(|a| match a {
                Value::Object(m) => pick_string(m, &["name"]),
                Value::String(s) => Some(s.clone()),
                _ => None,
            })
            .collect();
        if !names.is_empty() {
            return names.join(", ");
        }
    }
    String::new()
}

fn pick_string(m: &Map<String, Value>, keys: &[&str]) -> Option<String> {
    keys.iter().find_map(|k| {
        let s = m.get(*k)?.as_str()?.trim();
        (!s.is_empty()).then(|| s.to_string())
    })
}

fn pick_int(m: &Map<String, Value>, keys: &[&str]) -> Option<i64> {
    keys.iter().find_map(|k| match m.get(*k)? {
        Value::Number(n) => n.as_i64().or_else(|| n.as_f64().map(|f| f as i64)),
        Value::String(s) => s.trim().parse().ok(),
        _ => None,
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    fn page(data: &Value) -> String {
        format!(
            r#"<html><head><script id="__NEXT_DATA__" type="application/json">{data}</script></head><body></body></html>"#
        )
    }

    #[test]
    fn parses_playlist_ids() {
        let id = "37i9dQZF1DXcBWIGoYBM5M";
        assert_eq!(SpotifyScraper::parse_playlist_id(id).as_deref(), Some(id));
        assert_eq!(
            SpotifyScraper::parse_playlist_id(&format!(" spotify:playlist:{id} ")).as_deref(),
            Some(id)
        );
        assert_eq!(
            SpotifyScraper::parse_playlist_id(&format!(
                "https://open.spotify.com/intl-de/playlist/{id}?si=abc"
            ))
            .as_deref(),
            Some(id)
        );
        assert_eq!(
            SpotifyScraper::parse_playlist_id(&format!(
                "https://open.spotify.com/embed/playlist/{id}"
            ))
            .as_deref(),
            Some(id)
        );
        assert_eq!(
            SpotifyScraper::parse_playlist_id(
                "https://open.spotify.com/album/37i9dQZF1DXcBWIGoYBM5M"
            ),
            None
        );
        assert_eq!(SpotifyScraper::parse_playlist_id("   "), None);
    }

    #[test]
    fn detect_picks_provider() {
        assert_eq!(
            PlaylistScraper::detect("spotify:playlist:37i9dQZF1DXcBWIGoYBM5M")
                .map(|s| s.provider()),
            Some(PlaylistProvider::Spotify)
        );
        assert_eq!(
            PlaylistScraper::detect(
                "https://tidal.com/browse/playlist/0D4D6D8B-1B2C-4E1A-9F00-AAAAAAAAAAAA"
            )
            .map(|s| s.provider()),
            Some(PlaylistProvider::Tidal)
        );
        assert!(PlaylistScraper::detect("hello").is_none());
    }

    #[test]
    fn parses_known_path_entity() {
        let data = json!({"props": {"pageProps": {"state": {"data": {"entity": {
            "name": "Road Trip",
            "trackCount": 150,
            "trackList": [
                {"title": " Song A ", "subtitle": "Artist 1, Artist 2", "duration": 210000},
                {"title": "Song B", "artists": [{"name": "X"}, "Y", 3], "duration": "1000.5"},
                {"title": "Song C", "durationMs": 99.9},
                {"title": "  "},
                "garbage"
            ]
        }}}}}});
        let p = parse_embed_html(&page(&data)).unwrap();
        assert_eq!(p.name, "Road Trip");
        assert_eq!(p.provider, PlaylistProvider::Spotify);
        assert!(p.truncated);
        assert_eq!(
            p.tracks,
            vec![
                SpotifyTrack {
                    title: "Song A".into(),
                    artist: "Artist 1, Artist 2".into(),
                    album: None,
                    duration_ms: Some(210000)
                },
                SpotifyTrack {
                    title: "Song B".into(),
                    artist: "X, Y".into(),
                    album: None,
                    duration_ms: None
                },
                SpotifyTrack {
                    title: "Song C".into(),
                    artist: "".into(),
                    album: None,
                    duration_ms: Some(99)
                },
            ]
        );
    }

    #[test]
    fn falls_back_to_document_order_search() {
        // Two entity-shaped objects: Dart picks the first in insertion order.
        let html = page(&serde_json::from_str::<Value>(
            r#"{"props": {"z": {"title": "First", "tracks": {"items": [{"name": "T1", "artist": "A"}]}},
                          "a": {"name": "Second", "audioItems": [{"name": "T2"}]}}}"#,
        )
        .unwrap());
        let p = parse_embed_html(&html).unwrap();
        assert_eq!(p.name, "First");
        assert_eq!(p.tracks[0].title, "T1");
        assert!(!p.truncated);
    }

    #[test]
    fn reports_user_facing_errors() {
        let msg = |html: &str| parse_embed_html(html).unwrap_err().to_string();
        assert!(msg("<html></html>").starts_with("Spotify changed its embed format"));
        assert_eq!(
            msg(r#"<script id="__NEXT_DATA__">{not json</script>"#),
            "Spotify returned malformed playlist data."
        );
        assert!(
            msg(&page(&json!({"props": {}}))).starts_with("Spotify did not include any track data")
        );
        assert!(msg(&page(&json!({"entity": {"trackList": []}}))).starts_with("Playlist is empty"));
        assert_eq!(
            msg(&page(
                &json!({"entity": {"trackList": [{"subtitle": "x"}]}})
            )),
            "Could not read any tracks from the playlist."
        );
    }
}
