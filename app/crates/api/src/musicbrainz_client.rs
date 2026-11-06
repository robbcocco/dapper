use std::sync::LazyLock;
use std::time::Duration;

use dapper_domain::{MbReleaseGroup, Result};
use reqwest::header::{ACCEPT, HeaderMap, HeaderValue, USER_AGENT};
use serde_json::Value;
use tokio::sync::Mutex;
use tokio::time::Instant;

use crate::http::net_err;

const MB_BASE: &str = "https://musicbrainz.org";
const CAA_BASE: &str = "https://coverartarchive.org";
const MB_USER_AGENT: &str = "Dapper/1.0 (github.com/dapper-music)";

/// Spaces request starts at least `interval` apart. Waiters queue on a fair
/// mutex, so concurrent callers are served in arrival order.
pub(crate) struct RateLimiter {
    interval: Duration,
    next: Mutex<Option<Instant>>,
}

impl RateLimiter {
    pub(crate) const fn new(interval: Duration) -> Self {
        Self {
            interval,
            next: Mutex::const_new(None),
        }
    }

    pub(crate) async fn acquire(&self) {
        let mut next = self.next.lock().await;
        if let Some(at) = *next {
            tokio::time::sleep_until(at).await;
        }
        *next = Some(Instant::now() + self.interval);
    }
}

/// MusicBrainz asks clients to stay at or below 1 request/second; shared by
/// every `MusicBrainzClient` in the process.
static MB_LIMITER: RateLimiter = RateLimiter::new(Duration::from_secs(1));

static MB_HTTP: LazyLock<reqwest::Client> = LazyLock::new(|| {
    let mut headers = HeaderMap::new();
    headers.insert(USER_AGENT, HeaderValue::from_static(MB_USER_AGENT));
    headers.insert(ACCEPT, HeaderValue::from_static("application/json"));
    reqwest::Client::builder()
        .default_headers(headers)
        .connect_timeout(Duration::from_secs(10))
        .read_timeout(Duration::from_secs(15))
        .build()
        .expect("static HTTP client config")
});

static CAA_HTTP: LazyLock<reqwest::Client> = LazyLock::new(|| {
    reqwest::Client::builder()
        .connect_timeout(Duration::from_secs(10))
        .read_timeout(Duration::from_secs(30))
        .redirect(reqwest::redirect::Policy::limited(5))
        .build()
        .expect("static HTTP client config")
});

/// Lucene phrase escaping as done by the Dart client.
fn esc(s: &str) -> String {
    s.replace('"', "\\\"")
        .replace('(', "\\(")
        .replace(')', "\\)")
}

/// MusicBrainz release-group search + Cover Art Archive front-cover fetch.
/// Failures are logged and surface as empty results (matching the Dart UI
/// flow, which treats "nothing found" and "lookup failed" alike).
#[derive(Debug, Clone)]
pub struct MusicBrainzClient {
    mb_base: String,
    caa_base: String,
}

impl Default for MusicBrainzClient {
    fn default() -> Self {
        Self::new()
    }
}

impl MusicBrainzClient {
    pub fn new() -> Self {
        Self::with_base_urls(MB_BASE, CAA_BASE)
    }

    /// Alternate endpoints (tests, mirrors).
    pub fn with_base_urls(mb_base: &str, caa_base: &str) -> Self {
        Self {
            mb_base: mb_base.trim_end_matches('/').to_string(),
            caa_base: caa_base.trim_end_matches('/').to_string(),
        }
    }

    pub async fn search_release_groups(
        &self,
        album_name: &str,
        artist_name: Option<&str>,
    ) -> Vec<MbReleaseGroup> {
        let mut parts = vec![format!("release:\"{}\"", esc(album_name))];
        if let Some(a) = artist_name.filter(|a| !a.is_empty()) {
            parts.push(format!("artist:\"{}\"", esc(a)));
        }
        self.query_release_groups(&parts.join(" AND ")).await
    }

    /// Free-text Lucene query, passed through unescaped.
    pub async fn search_by_text(&self, query: &str) -> Vec<MbReleaseGroup> {
        self.query_release_groups(query).await
    }

    async fn query_release_groups(&self, query: &str) -> Vec<MbReleaseGroup> {
        match self.try_query(query).await {
            Ok(groups) => groups,
            Err(e) => {
                tracing::warn!(error = %e, "MusicBrainz release-group query failed");
                Vec::new()
            }
        }
    }

    async fn try_query(&self, query: &str) -> Result<Vec<MbReleaseGroup>> {
        let url = url::Url::parse_with_params(
            &format!("{}/ws/2/release-group", self.mb_base),
            &[("query", query), ("fmt", "json"), ("limit", "6")],
        )
        .map_err(|e| dapper_domain::AppError::Other(e.to_string()))?;
        MB_LIMITER.acquire().await;
        let resp = MB_HTTP
            .get(url)
            .send()
            .await
            .map_err(net_err)?
            .error_for_status()
            .map_err(net_err)?;
        let body: Value = resp.json().await.map_err(net_err)?;
        body.get("release-groups")
            .and_then(Value::as_array)
            .map(|groups| groups.iter().map(MbReleaseGroup::from_json).collect())
            .unwrap_or_else(|| Ok(Vec::new()))
    }

    /// Front cover for a release group, following CAA's redirects.
    pub async fn fetch_cover_art(&self, mbid: &str) -> Option<Vec<u8>> {
        let url = format!("{}/release-group/{mbid}/front", self.caa_base);
        let result = async {
            let resp = CAA_HTTP.get(&url).send().await?.error_for_status()?;
            resp.bytes().await
        }
        .await;
        match result {
            Ok(b) => Some(b.to_vec()),
            Err(e) => {
                tracing::warn!(%mbid, error = %net_err(e), "cover-art fetch failed");
                None
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use wiremock::matchers::{header, method, path, query_param};
    use wiremock::{Mock, MockServer, ResponseTemplate};

    #[test]
    fn escapes_quotes_and_parens() {
        assert_eq!(esc(r#"A "B" (C)"#), r#"A \"B\" \(C\)"#);
    }

    #[tokio::test(start_paused = true)]
    async fn limiter_spaces_requests_one_second_apart() {
        let limiter = RateLimiter::new(Duration::from_secs(1));
        let start = Instant::now();
        limiter.acquire().await;
        limiter.acquire().await;
        limiter.acquire().await;
        assert!(start.elapsed() >= Duration::from_secs(2));
        assert!(start.elapsed() < Duration::from_millis(2100));
    }

    #[tokio::test]
    async fn search_builds_escaped_query_and_parses_groups() {
        let server = MockServer::start().await;
        Mock::given(method("GET"))
            .and(path("/ws/2/release-group"))
            .and(query_param("query", r#"release:"Live \(1999\)" AND artist:"The \"Band\"""#))
            .and(query_param("fmt", "json"))
            .and(query_param("limit", "6"))
            .and(header("user-agent", MB_USER_AGENT))
            .respond_with(ResponseTemplate::new(200).set_body_json(serde_json::json!({
                "release-groups": [{"id": "rg1", "title": "Live", "first-release-date": "1999-02-03",
                    "artist-credit": [{"name": "The Band"}]}]
            })))
            .mount(&server)
            .await;
        Mock::given(path("/release-group/rg1/front"))
            .respond_with(ResponseTemplate::new(200).set_body_bytes(vec![0xFF, 0xD8]))
            .mount(&server)
            .await;
        let c = MusicBrainzClient::with_base_urls(&server.uri(), &server.uri());
        let groups = c
            .search_release_groups("Live (1999)", Some(r#"The "Band""#))
            .await;
        assert_eq!(groups.len(), 1);
        assert_eq!(groups[0].artist_name.as_deref(), Some("The Band"));
        assert_eq!(c.fetch_cover_art("rg1").await, Some(vec![0xFF, 0xD8]));
        assert_eq!(c.fetch_cover_art("missing").await, None);
        assert!(c.search_by_text("nothing").await.is_empty());
    }
}
