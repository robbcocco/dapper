use std::time::Duration;

use dapper_domain::{
    AppError, LidarrAlbum, LidarrAlbumLookup, LidarrArtist, LidarrCustomFilter,
    LidarrQualityProfile, LidarrRelease, LidarrRootFolder, Result,
};
use parking_lot::Mutex;
use reqwest::header::{HeaderMap, HeaderValue};
use reqwest::{Method, RequestBuilder};
use serde_json::{Map, Value, json};
use url::Url;

use crate::http::{net_err, redact_userinfo, same_origin_redirects};

const ERROR_BODY_EXCERPT: usize = 300;

pub struct LidarrClient {
    http: reqwest::Client,
    base: String,
    // Profiles don't change mid-session and the client is rebuilt on
    // instance/credential change, so the first lookup is cached.
    metadata_profile_id: Mutex<Option<i64>>,
}

impl LidarrClient {
    pub fn new(base_url: &str, api_key: &str) -> Result<Self> {
        let mut key = HeaderValue::from_str(api_key)
            .map_err(|_| AppError::Other("Invalid Lidarr API key".into()))?;
        key.set_sensitive(true);
        let mut headers = HeaderMap::new();
        headers.insert("X-Api-Key", key);
        // connect fast-fails an unreachable host; the read timeout is generous
        // because interactive indexer searches can take up to a minute.
        let http = reqwest::Client::builder()
            .default_headers(headers)
            .connect_timeout(Duration::from_secs(10))
            .read_timeout(Duration::from_secs(60))
            .redirect(same_origin_redirects())
            .build()
            .map_err(net_err)?;
        let base = base_url.trim().trim_end_matches('/').to_string();
        Url::parse(&base).map_err(|e| {
            AppError::Other(format!(
                "Invalid Lidarr URL '{}': {e}",
                redact_userinfo(base_url)
            ))
        })?;
        Ok(Self {
            http,
            base,
            metadata_profile_id: Mutex::new(None),
        })
    }

    fn request(
        &self,
        method: Method,
        path: &str,
        query: &[(&str, String)],
    ) -> Result<RequestBuilder> {
        let url = Url::parse_with_params(&format!("{}{path}", self.base), query)
            .map_err(|e| AppError::Other(format!("Invalid Lidarr URL: {e}")))?;
        Ok(self.http.request(method, url))
    }

    async fn send(&self, rb: RequestBuilder) -> Result<(u16, Value)> {
        let resp = rb.send().await.map_err(net_err)?;
        let status = resp.status();
        let body = resp.bytes().await.map_err(net_err)?;
        if !status.is_success() {
            let text = String::from_utf8_lossy(&body);
            let excerpt: String = text.chars().take(ERROR_BODY_EXCERPT).collect();
            return Err(AppError::Network(if excerpt.trim().is_empty() {
                format!("Lidarr request failed (HTTP {})", status.as_u16())
            } else {
                format!(
                    "Lidarr request failed (HTTP {}): {}",
                    status.as_u16(),
                    excerpt.trim()
                )
            }));
        }
        let value = if body.is_empty() {
            Value::Null
        } else {
            serde_json::from_slice(&body)
                .map_err(|e| AppError::Other(format!("Lidarr returned malformed JSON: {e}")))?
        };
        Ok((status.as_u16(), value))
    }

    async fn get(&self, path: &str, query: &[(&str, String)]) -> Result<Value> {
        Ok(self.send(self.request(Method::GET, path, query)?).await?.1)
    }

    async fn post(&self, path: &str, body: &Value) -> Result<Value> {
        Ok(self
            .send(self.request(Method::POST, path, &[])?.json(body))
            .await?
            .1)
    }

    async fn get_list(&self, path: &str, query: &[(&str, String)]) -> Result<Vec<Value>> {
        Ok(match self.get(path, query).await? {
            Value::Array(items) => items.into_iter().filter(Value::is_object).collect(),
            _ => Vec::new(),
        })
    }

    pub async fn test_connection(&self) -> Result<bool> {
        let (status, _) = self
            .send(self.request(Method::GET, "/api/v1/system/status", &[])?)
            .await?;
        Ok(status == 200)
    }

    pub async fn get_artists(&self) -> Result<Vec<LidarrArtist>> {
        Ok(self
            .get_list("/api/v1/artist", &[])
            .await?
            .iter()
            .map(LidarrArtist::from_json)
            .collect())
    }

    pub async fn lookup_artists(&self, term: &str) -> Result<Vec<LidarrArtist>> {
        let items = self
            .get_list("/api/v1/artist/lookup", &[("term", term.into())])
            .await?;
        Ok(items.iter().map(LidarrArtist::from_json).collect())
    }

    /// Lidarr rejects `POST /artist` without a `metadataProfileId`, so the
    /// instance's first profile is used when the caller doesn't pick one.
    pub async fn add_artist(
        &self,
        mbid: &str,
        name: &str,
        root_folder_path: &str,
        quality_profile_id: i64,
        metadata_profile_id: Option<i64>,
    ) -> Result<LidarrArtist> {
        let meta_id = match metadata_profile_id {
            Some(id) => Some(id),
            None => self.default_metadata_profile_id().await?,
        };
        let mut body = json!({
            "foreignArtistId": mbid,
            "artistName": name,
            "monitored": true,
            "rootFolderPath": root_folder_path,
            "qualityProfileId": quality_profile_id,
        });
        if let Some(id) = meta_id {
            body["metadataProfileId"] = id.into();
        }
        body["addOptions"] = json!({"monitor": "all", "searchForMissingAlbums": false});
        Ok(LidarrArtist::from_json(
            &self.post("/api/v1/artist", &body).await?,
        ))
    }

    /// First metadata profile id (> 0) on the instance; `None` when it has
    /// none. Request failures propagate.
    async fn default_metadata_profile_id(&self) -> Result<Option<i64>> {
        if let Some(id) = *self.metadata_profile_id.lock() {
            return Ok(Some(id));
        }
        let profiles = self.get_list("/api/v1/metadataprofile", &[]).await?;
        let id = profiles
            .iter()
            .filter_map(|p| p.get("id").and_then(Value::as_i64))
            .find(|id| *id > 0);
        if let Some(id) = id {
            *self.metadata_profile_id.lock() = Some(id);
        }
        Ok(id)
    }

    pub async fn get_root_folders(&self) -> Result<Vec<LidarrRootFolder>> {
        self.get_list("/api/v1/rootfolder", &[])
            .await?
            .iter()
            .map(LidarrRootFolder::from_json)
            .collect()
    }

    pub async fn get_quality_profiles(&self) -> Result<Vec<LidarrQualityProfile>> {
        self.get_list("/api/v1/qualityprofile", &[])
            .await?
            .iter()
            .map(LidarrQualityProfile::from_json)
            .collect()
    }

    pub async fn lookup_albums(&self, term: &str) -> Result<Vec<LidarrAlbumLookup>> {
        let items = self
            .get_list("/api/v1/album/lookup", &[("term", term.into())])
            .await?;
        Ok(items.iter().map(LidarrAlbumLookup::from_json).collect())
    }

    /// Adds an album from a lookup result, creating its artist in the same
    /// call when needed. Returns the new album's Lidarr id (0 when absent).
    pub async fn add_album(
        &self,
        album: &LidarrAlbumLookup,
        root_folder_path: &str,
        quality_profile_id: i64,
        search_on_add: bool,
    ) -> Result<i64> {
        let mut payload = album.raw.clone();
        payload.insert("monitored".into(), true.into());
        payload.insert(
            "addOptions".into(),
            json!({"addType": "automatic", "searchForNewAlbum": search_on_add}),
        );
        let mut artist: Map<String, Value> = match payload.get("artist") {
            Some(Value::Object(a)) => a.clone(),
            _ => Map::new(),
        };
        artist.insert("monitored".into(), true.into());
        artist.insert("qualityProfileId".into(), quality_profile_id.into());
        artist.insert("rootFolderPath".into(), root_folder_path.into());
        // A new artist needs a metadataProfileId > 0; lookups usually carry 0.
        let existing = artist.get("metadataProfileId").and_then(Value::as_i64);
        if existing.is_none_or(|id| id <= 0)
            && let Some(id) = self.default_metadata_profile_id().await?
        {
            artist.insert("metadataProfileId".into(), id.into());
        }
        artist.insert(
            "addOptions".into(),
            json!({"monitor": "specificAlbum", "searchForMissingAlbums": false}),
        );
        payload.insert("artist".into(), Value::Object(artist));

        let resp = self.post("/api/v1/album", &Value::Object(payload)).await?;
        Ok(resp.get("id").and_then(Value::as_i64).unwrap_or(0))
    }

    pub async fn get_albums_by_artist(&self, artist_id: i64) -> Result<Vec<LidarrAlbum>> {
        let items = self
            .get_list("/api/v1/album", &[("artistId", artist_id.to_string())])
            .await?;
        Ok(items.iter().map(LidarrAlbum::from_json).collect())
    }

    pub async fn trigger_artist_search(&self, artist_id: i64) -> Result<()> {
        self.post(
            "/api/v1/command",
            &json!({"name": "ArtistSearch", "artistId": artist_id}),
        )
        .await
        .map(drop)
    }

    pub async fn trigger_album_search(&self, album_id: i64) -> Result<()> {
        self.post(
            "/api/v1/command",
            &json!({"name": "AlbumSearch", "albumIds": [album_id]}),
        )
        .await
        .map(drop)
    }

    /// Interactive indexer search; can legitimately take up to a minute.
    pub async fn search_releases(&self, album_id: i64) -> Result<Vec<LidarrRelease>> {
        let items = self
            .get_list("/api/v1/release", &[("albumId", album_id.to_string())])
            .await?;
        Ok(items.iter().map(LidarrRelease::from_json).collect())
    }

    /// Grabs a release by POSTing its original JSON back verbatim.
    pub async fn grab_release(&self, release_json: &Map<String, Value>) -> Result<()> {
        self.post("/api/v1/release", &Value::Object(release_json.clone()))
            .await
            .map(drop)
    }

    pub async fn get_custom_filters(&self) -> Result<Vec<LidarrCustomFilter>> {
        let items = self.get_list("/api/v1/customfilter", &[]).await?;
        let filters: Result<Vec<_>> = items.iter().map(LidarrCustomFilter::from_json).collect();
        Ok(filters?
            .into_iter()
            .filter(|f| !f.label.is_empty())
            .collect())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use wiremock::matchers::{body_partial_json, header, method, path};
    use wiremock::{Mock, MockServer, ResponseTemplate};

    async fn lidarr(server: &MockServer, profiles: ResponseTemplate) -> LidarrClient {
        Mock::given(method("GET"))
            .and(path("/api/v1/metadataprofile"))
            .respond_with(profiles)
            .mount(server)
            .await;
        Mock::given(method("POST"))
            .and(path("/api/v1/artist"))
            .and(header("x-api-key", "k"))
            .respond_with(ResponseTemplate::new(201).set_body_json(json!({
                "id": 10, "foreignArtistId": "mbid-x", "artistName": "Test Artist",
                "monitored": true, "qualityProfileId": 2
            })))
            .mount(server)
            .await;
        LidarrClient::new(&format!("{}//", server.uri()), "k").unwrap()
    }

    fn profiles() -> ResponseTemplate {
        ResponseTemplate::new(200)
            .set_body_json(json!([{"id": 3, "name": "Standard"}, {"id": 4, "name": "None"}]))
    }

    async fn posted_artist(server: &MockServer) -> Value {
        let reqs = server.received_requests().await.unwrap();
        let post = reqs
            .iter()
            .find(|r| r.method.as_str() == "POST" && r.url.path() == "/api/v1/artist")
            .unwrap();
        serde_json::from_slice(&post.body).unwrap()
    }

    #[tokio::test]
    async fn add_artist_includes_a_resolved_metadata_profile_id() {
        let server = MockServer::start().await;
        let client = lidarr(&server, profiles()).await;
        let result = client
            .add_artist("mbid-x", "Test Artist", "/music", 2, None)
            .await
            .unwrap();
        assert_eq!(result.id, 10);
        let posted = posted_artist(&server).await;
        assert_eq!(posted["metadataProfileId"], 3);
        assert_eq!(posted["qualityProfileId"], 2);
        assert_eq!(posted["rootFolderPath"], "/music");
    }

    #[tokio::test]
    async fn an_explicit_metadata_profile_id_is_respected_over_the_default() {
        let server = MockServer::start().await;
        let client = lidarr(&server, profiles()).await;
        client
            .add_artist("mbid-x", "Test Artist", "/music", 2, Some(99))
            .await
            .unwrap();
        assert_eq!(posted_artist(&server).await["metadataProfileId"], 99);
    }

    #[tokio::test]
    async fn metadata_profile_lookup_failure_propagates() {
        let server = MockServer::start().await;
        let client = lidarr(&server, ResponseTemplate::new(500)).await;
        let err = client
            .add_artist("mbid-x", "Test Artist", "/music", 2, None)
            .await
            .unwrap_err();
        assert!(
            matches!(&err, AppError::Network(m) if m.contains("HTTP 500")),
            "{err:?}"
        );
        let reqs = server.received_requests().await.unwrap();
        assert!(reqs.iter().all(|r| r.method.as_str() != "POST"));
    }

    #[tokio::test]
    async fn add_album_fills_artist_defaults() {
        let server = MockServer::start().await;
        Mock::given(method("GET"))
            .and(path("/api/v1/metadataprofile"))
            .respond_with(profiles())
            .mount(&server)
            .await;
        Mock::given(method("POST"))
            .and(path("/api/v1/album"))
            .and(body_partial_json(json!({
                "title": "T", "monitored": true,
                "addOptions": {"addType": "automatic", "searchForNewAlbum": false},
                "artist": {"artistName": "A", "monitored": true, "qualityProfileId": 2,
                    "rootFolderPath": "/m", "metadataProfileId": 3,
                    "addOptions": {"monitor": "specificAlbum", "searchForMissingAlbums": false}}
            })))
            .respond_with(ResponseTemplate::new(201).set_body_json(json!({"id": 77})))
            .expect(1)
            .mount(&server)
            .await;
        let client = LidarrClient::new(&server.uri(), "k").unwrap();
        let lookup = LidarrAlbumLookup::from_json(&json!({
            "title": "T", "foreignAlbumId": "f", "artist": {"artistName": "A", "metadataProfileId": 0}
        }));
        assert_eq!(client.add_album(&lookup, "/m", 2, false).await.unwrap(), 77);
    }

    #[tokio::test]
    async fn api_key_never_follows_a_cross_origin_redirect() {
        let lidarr = MockServer::start().await;
        let other = MockServer::start().await;
        Mock::given(path("/api/v1/artist"))
            .respond_with(
                ResponseTemplate::new(302)
                    .insert_header("location", format!("{}/steal", other.uri())),
            )
            .mount(&lidarr)
            .await;
        Mock::given(path("/api/v1/rootfolder"))
            .respond_with(
                ResponseTemplate::new(302).insert_header("location", "/api/v1/rootfolder2"),
            )
            .mount(&lidarr)
            .await;
        Mock::given(path("/api/v1/rootfolder2"))
            .and(header("x-api-key", "k"))
            .respond_with(
                ResponseTemplate::new(200).set_body_json(json!([{"id": 1, "path": "/m"}])),
            )
            .mount(&lidarr)
            .await;
        Mock::given(path("/steal"))
            .respond_with(ResponseTemplate::new(200).set_body_json(json!([])))
            .mount(&other)
            .await;
        let client = LidarrClient::new(&lidarr.uri(), "k").unwrap();

        let err = client.get_artists().await.unwrap_err();
        assert!(
            matches!(&err, AppError::Network(m) if m.contains("HTTP 302")),
            "{err:?}"
        );
        assert!(other.received_requests().await.unwrap().is_empty());

        let folders = client.get_root_folders().await.unwrap();
        assert_eq!(
            folders[0].path, "/m",
            "same-origin redirects are still followed"
        );
    }

    #[test]
    fn invalid_url_error_redacts_userinfo() {
        let err = LidarrClient::new("http://bob:s3cret@bad host", "k")
            .err()
            .unwrap()
            .to_string();
        assert!(
            !err.contains("s3cret") && err.contains("***@bad host"),
            "{err}"
        );
    }

    #[tokio::test]
    async fn custom_filters_drop_unlabelled() {
        let server = MockServer::start().await;
        Mock::given(path("/api/v1/customfilter"))
            .respond_with(ResponseTemplate::new(200).set_body_json(json!([
                {"id": 1, "label": "Keep", "filters": []}, {"id": 2, "label": ""}
            ])))
            .mount(&server)
            .await;
        let client = LidarrClient::new(&server.uri(), "k").unwrap();
        let f = client.get_custom_filters().await.unwrap();
        assert_eq!(f.len(), 1);
        assert_eq!(f[0].label, "Keep");
    }
}
