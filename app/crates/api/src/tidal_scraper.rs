use std::sync::LazyLock;
use std::time::Duration;

use dapper_domain::{PlaylistProvider, Result, SpotifyPlaylistData, SpotifyTrack};
use regex::Regex;
use serde_json::Value;

use crate::http::failure_kind;
use crate::spotify_scraper::scrape_error;

// Read-only web-client token shipped in the Tidal web app's JS bundle and
// used by anonymous embed previews; a rotation surfaces as a 401/403.
const WEB_TOKEN: &str = "CzET4vdadNUFQ5JU";
const PAGE_SIZE: usize = 100;
// Hard cap so a misbehaving pagination response can't spin forever.
const MAX_OFFSET: usize = 5000;

const UUID: &str = r"[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}";
static BARE: LazyLock<Regex> = LazyLock::new(|| Regex::new(&format!("^{UUID}$")).unwrap());
static URI: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(&format!("tidal:playlist:({UUID})")).unwrap());
static URL: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(&format!(
        r"tidal\.com/(?:[a-z\-]+/)?(?:browse/)?playlist/({UUID})"
    ))
    .unwrap()
});

/// Public Tidal playlist via `api.tidal.com/v1` (the web app's HTML carries
/// no track data).
pub struct TidalScraper {
    http: reqwest::Client,
    base: String,
    token: String,
    country_code: String,
}

impl Default for TidalScraper {
    fn default() -> Self {
        Self::new()
    }
}

enum Failure {
    Status(u16),
    Transport(&'static str),
}

impl TidalScraper {
    pub fn new() -> Self {
        Self::with_config("https://api.tidal.com/v1", WEB_TOKEN, "US")
    }

    pub fn with_config(base_url: &str, token: &str, country_code: &str) -> Self {
        let http = reqwest::Client::builder()
            .connect_timeout(Duration::from_secs(10))
            .read_timeout(Duration::from_secs(15))
            .build()
            .expect("static HTTP client config");
        Self {
            http,
            base: base_url.trim_end_matches('/').to_string(),
            token: token.into(),
            country_code: country_code.into(),
        }
    }

    /// Lower-cased playlist UUID from a bare UUID, `tidal:playlist:<uuid>` or
    /// any `tidal.com/.../playlist/<uuid>` URL (embed/listen subdomains too).
    pub fn parse_playlist_id(input: &str) -> Option<String> {
        let s = input.trim();
        if s.is_empty() {
            return None;
        }
        if BARE.is_match(s) {
            return Some(s.to_lowercase());
        }
        URI.captures(s)
            .or_else(|| URL.captures(s))
            .map(|c| c[1].to_lowercase())
    }

    async fn get_object(
        &self,
        path: &str,
        query: &[(&str, String)],
    ) -> std::result::Result<Value, Failure> {
        let url = url::Url::parse_with_params(&format!("{}{path}", self.base), query)
            .map_err(|_| Failure::Transport("unknown"))?;
        let resp = self
            .http
            .get(url)
            .header("X-Tidal-Token", &self.token)
            .send()
            .await
            .map_err(|e| Failure::Transport(failure_kind(&e)))?;
        if !resp.status().is_success() {
            return Err(Failure::Status(resp.status().as_u16()));
        }
        let body = resp
            .bytes()
            .await
            .map_err(|e| Failure::Transport(failure_kind(&e)))?;
        Ok(serde_json::from_slice::<Value>(&body)
            .ok()
            .filter(Value::is_object)
            .unwrap_or(Value::Null))
    }

    async fn fetch_raw(&self, id: &str) -> std::result::Result<(Value, Vec<Value>), Failure> {
        let meta = self
            .get_object(
                &format!("/playlists/{id}"),
                &[("countryCode", self.country_code.clone())],
            )
            .await?;
        let mut items = Vec::new();
        let mut offset = 0usize;
        loop {
            let mut body = self
                .get_object(
                    &format!("/playlists/{id}/items"),
                    &[
                        ("countryCode", self.country_code.clone()),
                        ("limit", PAGE_SIZE.to_string()),
                        ("offset", offset.to_string()),
                    ],
                )
                .await?;
            let page = match body.get_mut("items").map(Value::take) {
                Some(Value::Array(page)) => page,
                _ => Vec::new(),
            };
            let page_len = page.len();
            items.extend(page);
            let total = body
                .get("totalNumberOfItems")
                .and_then(Value::as_u64)
                .map_or(items.len(), |t| t as usize);
            offset += page_len;
            if page_len == 0 || offset >= total || offset > MAX_OFFSET {
                break;
            }
        }
        Ok((meta, items))
    }

    pub async fn fetch_playlist(&self, id_or_url: &str) -> Result<SpotifyPlaylistData> {
        let Some(id) = Self::parse_playlist_id(id_or_url) else {
            return Err(scrape_error(
                "Could not find a Tidal playlist ID in that text.",
            ));
        };
        let (meta, items) = self.fetch_raw(&id).await.map_err(|f| match f {
            Failure::Status(401 | 403) => scrape_error(
                "Tidal denied the request — the public token may have been rotated. Try updating Dapper.",
            ),
            Failure::Status(404) => scrape_error("Tidal playlist not found. Make sure the link is public."),
            Failure::Status(s) => scrape_error(format!("Tidal request failed ({s}).")),
            Failure::Transport(kind) => scrape_error(format!("Tidal request failed ({kind}).")),
        })?;
        parse_playlist(&meta, &items)
    }
}

fn parse_playlist(meta: &Value, items: &[Value]) -> Result<SpotifyPlaylistData> {
    if items.is_empty() {
        return Err(scrape_error("Tidal returned no tracks for this playlist."));
    }
    let name = match meta.get("title").and_then(Value::as_str) {
        Some(t) if !t.trim().is_empty() => t.to_string(),
        _ => "Tidal Playlist".to_string(),
    };

    let tracks: Vec<SpotifyTrack> = items
        .iter()
        .filter_map(|raw| {
            let item = raw.get("item")?.as_object()?;
            // Skip videos / mixes — only tracks have a usable title+artist pair.
            if let Some(t) = raw.get("type").and_then(Value::as_str)
                && t.to_lowercase() != "track"
            {
                return None;
            }
            let title = item.get("title")?.as_str()?.trim();
            if title.is_empty() {
                return None;
            }
            Some(SpotifyTrack {
                title: title.to_string(),
                artist: join_artists(item.get("artists")),
                album: item
                    .get("album")
                    .and_then(|a| a.get("title"))
                    .and_then(Value::as_str)
                    .map(str::to_string),
                duration_ms: item
                    .get("duration")
                    .and_then(Value::as_i64)
                    .map(|s| s * 1000),
            })
        })
        .collect();
    if tracks.is_empty() {
        return Err(scrape_error(
            "Could not read any tracks from the Tidal playlist.",
        ));
    }

    let advertised = meta
        .get("numberOfTracks")
        .and_then(Value::as_i64)
        .unwrap_or(tracks.len() as i64);
    let truncated = (tracks.len() as i64) < advertised;
    Ok(SpotifyPlaylistData {
        name,
        tracks,
        truncated,
        provider: PlaylistProvider::Tidal,
    })
}

fn join_artists(raw: Option<&Value>) -> String {
    let Some(Value::Array(list)) = raw else {
        return String::new();
    };
    list.iter()
        .filter_map(|a| {
            a.get("name")?
                .as_str()
                .map(str::trim)
                .filter(|n| !n.is_empty())
        })
        .collect::<Vec<_>>()
        .join(", ")
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;
    use wiremock::matchers::{header, method, path, query_param};
    use wiremock::{Mock, MockServer, ResponseTemplate};

    const ID: &str = "0d4d6d8b-1b2c-4e1a-9f00-aaaaaaaaaaaa";

    #[test]
    fn parses_playlist_ids() {
        let upper = ID.to_uppercase();
        assert_eq!(TidalScraper::parse_playlist_id(&upper).as_deref(), Some(ID));
        assert_eq!(
            TidalScraper::parse_playlist_id(&format!("tidal:playlist:{upper}")).as_deref(),
            Some(ID)
        );
        assert_eq!(
            TidalScraper::parse_playlist_id(&format!("https://listen.tidal.com/playlist/{ID}"))
                .as_deref(),
            Some(ID)
        );
        assert_eq!(
            TidalScraper::parse_playlist_id(&format!("https://tidal.com/browse/playlist/{ID}?u"))
                .as_deref(),
            Some(ID)
        );
        assert_eq!(
            TidalScraper::parse_playlist_id(&format!("https://embed.tidal.com/playlist/{ID}"))
                .as_deref(),
            Some(ID)
        );
        assert_eq!(
            TidalScraper::parse_playlist_id(&format!("https://tidal.com/album/{ID}")),
            None
        );
        assert_eq!(
            TidalScraper::parse_playlist_id("37i9dQZF1DXcBWIGoYBM5M"),
            None
        );
    }

    #[test]
    fn parses_items() {
        let meta = json!({"title": "  ", "numberOfTracks": 4});
        let items = vec![
            json!({"type": "track", "item": {"title": " One ", "duration": 61,
                "artists": [{"name": " A "}, {"name": ""}, {"name": "B"}], "album": {"title": "Alb"}}}),
            json!({"type": "video", "item": {"title": "Clip"}}),
            json!({"item": {"title": "Two"}}),
            json!({"type": "TRACK", "item": {"title": ""}}),
        ];
        let p = parse_playlist(&meta, &items).unwrap();
        assert_eq!(p.name, "Tidal Playlist");
        assert!(p.truncated);
        assert_eq!(p.provider, PlaylistProvider::Tidal);
        assert_eq!(
            p.tracks,
            vec![
                SpotifyTrack {
                    title: "One".into(),
                    artist: "A, B".into(),
                    album: Some("Alb".into()),
                    duration_ms: Some(61000)
                },
                SpotifyTrack {
                    title: "Two".into(),
                    artist: "".into(),
                    album: None,
                    duration_ms: None
                },
            ]
        );
        assert_eq!(
            parse_playlist(&meta, &[]).unwrap_err().to_string(),
            "Tidal returned no tracks for this playlist."
        );
    }

    #[tokio::test]
    async fn fetches_all_pages_with_token() {
        let server = MockServer::start().await;
        Mock::given(method("GET"))
            .and(path(format!("/playlists/{ID}")))
            .and(header("x-tidal-token", "tok"))
            .and(query_param("countryCode", "DE"))
            .respond_with(
                ResponseTemplate::new(200)
                    .set_body_json(json!({"title": "Mix", "numberOfTracks": 101})),
            )
            .mount(&server)
            .await;
        let track = |n: usize| json!({"type": "track", "item": {"title": format!("T{n}")}});
        Mock::given(path(format!("/playlists/{ID}/items")))
            .and(query_param("offset", "0"))
            .and(query_param("limit", "100"))
            .respond_with(ResponseTemplate::new(200).set_body_json(json!({
                "items": (0..100).map(track).collect::<Vec<_>>(), "totalNumberOfItems": 101
            })))
            .mount(&server)
            .await;
        Mock::given(path(format!("/playlists/{ID}/items")))
            .and(query_param("offset", "100"))
            .respond_with(
                ResponseTemplate::new(200)
                    .set_body_json(json!({"items": [track(100)], "totalNumberOfItems": 101})),
            )
            .mount(&server)
            .await;
        let s = TidalScraper::with_config(&server.uri(), "tok", "DE");
        let p = s
            .fetch_playlist(&format!("tidal:playlist:{ID}"))
            .await
            .unwrap();
        assert_eq!(p.name, "Mix");
        assert_eq!(p.tracks.len(), 101);
        assert!(!p.truncated);
    }

    #[tokio::test]
    async fn maps_http_failures_to_messages() {
        let server = MockServer::start().await;
        Mock::given(path(format!("/playlists/{ID}")))
            .respond_with(ResponseTemplate::new(403))
            .mount(&server)
            .await;
        let s = TidalScraper::with_config(&server.uri(), "tok", "US");
        let err = s.fetch_playlist(ID).await.unwrap_err().to_string();
        assert!(err.starts_with("Tidal denied the request"), "{err}");
        let err = TidalScraper::with_config(&server.uri(), "tok", "US")
            .fetch_playlist("ffffffff-1b2c-4e1a-9f00-aaaaaaaaaaaa")
            .await
            .unwrap_err()
            .to_string();
        assert_eq!(
            err,
            "Tidal playlist not found. Make sure the link is public."
        );
    }
}
