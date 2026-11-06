//! Port of test/datasources/remote/subsonic_client_test.dart.

use std::collections::{HashMap, HashSet};

use dapper_api::{
    API_VERSION, CLIENT_NAME, RESPONSE_FORMAT, SubsonicApi, SubsonicClient, endpoints,
};
use dapper_domain::AppError;
use md5::{Digest, Md5};
use serde_json::json;
use url::Url;
use wiremock::matchers::{method, path, query_param};
use wiremock::{Mock, MockServer, ResponseTemplate};

fn client_at(base: &str) -> SubsonicClient {
    SubsonicClient::new(base, "alice", "p4ss").unwrap()
}

fn client() -> SubsonicClient {
    client_at("https://music.example.com")
}

fn md5_hex(s: &str) -> String {
    hex::encode(Md5::digest(s.as_bytes()))
}

fn query(u: &Url) -> HashMap<String, String> {
    u.query_pairs().into_owned().collect()
}

fn fail_envelope(code: i32, message: &str) -> serde_json::Value {
    json!({"subsonic-response": {"status": "failed", "error": {"code": code, "message": message}}})
}

// ── build_uri ────────────────────────────────────────────────────────────

#[test]
fn build_uri_includes_all_required_auth_params() {
    let q = query(&client().build_uri("/rest/ping", &[]));
    assert_eq!(q["u"], "alice");
    assert!(q.contains_key("s"));
    assert!(q.contains_key("t"));
    assert_eq!(q["v"], API_VERSION);
    assert_eq!(q["c"], CLIENT_NAME);
    assert_eq!(q["f"], RESPONSE_FORMAT);
    assert_eq!(
        (API_VERSION, CLIENT_NAME, RESPONSE_FORMAT),
        ("1.16.1", "dapper", "json")
    );
}

#[test]
fn build_uri_merges_extra_params() {
    let q = query(&client().build_uri(
        "/rest/getCoverArt",
        &[("id", "cov-1".into()), ("size", 256.to_string())],
    ));
    assert_eq!(q["id"], "cov-1");
    assert_eq!(q["size"], "256");
}

#[test]
fn build_uri_token_is_md5_of_password_plus_salt() {
    let q = query(&client().build_uri("/rest/ping", &[]));
    assert_eq!(q["t"], md5_hex(&format!("p4ss{}", q["s"])));
}

#[test]
fn build_uri_uses_base_host_and_path() {
    let u = client().build_uri("/rest/ping", &[]);
    assert_eq!(u.scheme(), "https");
    assert_eq!(u.host_str(), Some("music.example.com"));
    assert_eq!(u.path(), "/rest/ping");
}

#[test]
fn build_uri_preserves_base_url_subpath() {
    let u = client_at("https://music.example.com/navidrome")
        .build_uri("/rest/getCoverArt", &[("id", "cov-1".into())]);
    assert_eq!(u.host_str(), Some("music.example.com"));
    assert_eq!(u.path(), "/navidrome/rest/getCoverArt");
}

#[test]
fn build_uri_trailing_slash_does_not_double() {
    assert_eq!(
        client_at("https://music.example.com/sub/")
            .build_uri("/rest/ping", &[])
            .path(),
        "/sub/rest/ping"
    );
}

#[test]
fn build_uri_salts_are_unique_across_rapid_calls() {
    let c = client();
    let salts: HashSet<String> = (0..200)
        .map(|_| query(&c.build_uri("/rest/ping", &[]))["s"].clone())
        .collect();
    assert_eq!(salts.len(), 200);
}

// ── transfer_uri ─────────────────────────────────────────────────────────

#[test]
fn transfer_uri_hits_download_when_format_is_none() {
    let api = SubsonicApi::new(client());
    let u = api.transfer_uri("song-id", None, None);
    assert_eq!(u.path(), endpoints::DOWNLOAD);
    let q = query(&u);
    assert_eq!(q["id"], "song-id");
    assert!(!q.contains_key("format"));
    assert!(!q.contains_key("maxBitRate"));
}

#[test]
fn transfer_uri_hits_stream_with_format() {
    let api = SubsonicApi::new(client());
    let u = api.transfer_uri("song-id", Some("mp3"), None);
    assert_eq!(u.path(), endpoints::STREAM);
    let q = query(&u);
    assert_eq!(q["format"], "mp3");
    assert_eq!(q["id"], "song-id");
}

#[test]
fn transfer_uri_includes_positive_max_bit_rate() {
    let api = SubsonicApi::new(client());
    assert_eq!(
        query(&api.transfer_uri("song-id", Some("opus"), Some(128)))["maxBitRate"],
        "128"
    );
}

#[test]
fn transfer_uri_omits_zero_or_missing_max_bit_rate() {
    let api = SubsonicApi::new(client());
    assert!(!query(&api.transfer_uri("s", Some("mp3"), Some(0))).contains_key("maxBitRate"));
    assert!(!query(&api.transfer_uri("s", Some("mp3"), None)).contains_key("maxBitRate"));
}

#[test]
fn zip_and_cover_uris() {
    let api = SubsonicApi::new(client_at("https://h/nd"));
    let z = api.zip_uri("al-1");
    assert_eq!(z.path(), "/nd/rest/download");
    assert_eq!(query(&z)["id"], "al-1");
    let a = api.cover_art_uri("c", 256);
    assert_eq!(a.path(), "/nd/rest/getCoverArt");
    assert_eq!(api.cover_art_uri("c", 256), a, "memoised per (id, size)");
    assert_ne!(api.cover_art_uri("c", 512), a);
}

// ── scrobble URL shape ───────────────────────────────────────────────────

#[test]
fn scrobble_submission_flags() {
    let c = client();
    let u = c.build_uri(
        endpoints::SCROBBLE,
        &[("id", "song-id".into()), ("submission", true.to_string())],
    );
    assert_eq!(u.path(), endpoints::SCROBBLE);
    assert_eq!(query(&u)["id"], "song-id");
    assert_eq!(query(&u)["submission"], "true");
    let u = c.build_uri(
        endpoints::SCROBBLE,
        &[("id", "song-id".into()), ("submission", false.to_string())],
    );
    assert_eq!(query(&u)["submission"], "false");
}

#[tokio::test]
async fn scrobble_sends_submission_and_time() {
    let server = MockServer::start().await;
    Mock::given(path("/rest/scrobble"))
        .and(query_param("id", "s1"))
        .and(query_param("submission", "false"))
        .and(query_param("time", "1700000000000"))
        .respond_with(
            ResponseTemplate::new(200)
                .set_body_json(json!({"subsonic-response": {"status": "ok"}})),
        )
        .expect(1)
        .mount(&server)
        .await;
    SubsonicApi::new(client_at(&server.uri()))
        .scrobble("s1", false, Some(1_700_000_000_000))
        .await
        .unwrap();
}

// ── error classification ─────────────────────────────────────────────────

async fn get_with(resp: ResponseTemplate) -> Result<serde_json::Value, AppError> {
    let server = MockServer::start().await;
    Mock::given(method("GET"))
        .respond_with(resp)
        .mount(&server)
        .await;
    client_at(&server.uri()).get(endpoints::PING, &[]).await
}

#[tokio::test]
async fn envelope_code_40_is_auth_error() {
    let r = get_with(
        ResponseTemplate::new(200).set_body_json(fail_envelope(40, "Wrong username or password")),
    )
    .await;
    assert_eq!(r, Err(AppError::Auth));
}

#[tokio::test]
async fn envelope_code_70_keeps_code() {
    let r = get_with(
        ResponseTemplate::new(200)
            .set_body_json(fail_envelope(70, "The requested data was not found")),
    )
    .await;
    assert_eq!(
        r,
        Err(AppError::Subsonic {
            message: "The requested data was not found".into(),
            code: 70
        })
    );
}

#[tokio::test]
async fn http_401_and_403_are_auth_errors() {
    assert_eq!(
        get_with(ResponseTemplate::new(401).set_body_string("nope")).await,
        Err(AppError::Auth)
    );
    assert_eq!(
        get_with(ResponseTemplate::new(403).set_body_string("<html>")).await,
        Err(AppError::Auth)
    );
}

#[tokio::test]
async fn non_json_server_error_and_empty_body() {
    assert_eq!(
        get_with(ResponseTemplate::new(502).set_body_string("<html>bad gateway</html>")).await,
        Err(AppError::Subsonic {
            message: "Server error (502)".into(),
            code: 0
        })
    );
    assert_eq!(
        get_with(ResponseTemplate::new(200)).await,
        Err(AppError::Subsonic {
            message: "Empty response from server".into(),
            code: 0
        })
    );
}

#[tokio::test]
async fn connection_failure_is_network_error_without_secrets() {
    let r = client_at("http://127.0.0.1:1")
        .get(endpoints::PING, &[])
        .await;
    match r {
        Err(AppError::Network(m)) => assert!(!m.contains("t=") && !m.contains("p4ss"), "{m}"),
        other => panic!("{other:?}"),
    }
}

// ── auth_params ──────────────────────────────────────────────────────────

#[test]
fn auth_params_carry_identity_and_md5_token() {
    let p: HashMap<_, _> = SubsonicClient::auth_params("alice", "p4ss")
        .into_iter()
        .collect();
    assert_eq!(p["u"], "alice");
    assert_eq!(p["v"], API_VERSION);
    assert_eq!(p["c"], CLIENT_NAME);
    assert_eq!(p["f"], RESPONSE_FORMAT);
    assert!(!p["s"].is_empty());
    assert_eq!(p["t"], md5_hex(&format!("p4ss{}", p["s"])));
}

#[test]
fn auth_params_fresh_salt_each_call() {
    let a: HashMap<_, _> = SubsonicClient::auth_params("alice", "p4ss")
        .into_iter()
        .collect();
    let b: HashMap<_, _> = SubsonicClient::auth_params("alice", "p4ss")
        .into_iter()
        .collect();
    assert_ne!(a["s"], b["s"]);
    assert_ne!(a["t"], b["t"]);
}

// ── API parsing over the wire ────────────────────────────────────────────

#[tokio::test]
async fn api_requests_keep_subpath_and_map_domain_types() {
    let server = MockServer::start().await;
    Mock::given(path("/nd/rest/getArtists"))
        .respond_with(ResponseTemplate::new(200).set_body_json(json!({"subsonic-response": {"status": "ok",
            "artists": {"index": [{"artist": [{"id": "ar1", "name": "A", "albumCount": 2}]}, {"artist": [{"id": "ar2", "name": "B"}]}]}}})))
        .mount(&server)
        .await;
    Mock::given(path("/nd/rest/getAlbum"))
        .and(query_param("id", "al1"))
        .respond_with(ResponseTemplate::new(200).set_body_json(json!({"subsonic-response": {"status": "ok",
            "album": {"id": "al1", "name": "X", "artist": "A", "song": [{"id": "s1", "title": "T"}]}}})))
        .expect(1)
        .mount(&server)
        .await;
    Mock::given(path("/nd/rest/getStarred2"))
        .respond_with(ResponseTemplate::new(200).set_body_json(json!({"subsonic-response": {"status": "ok",
            "starred2": {"song": [{"id": "s1", "title": "T"}], "album": [{"id": "al1", "name": "X"}]}}})))
        .mount(&server)
        .await;
    Mock::given(path("/nd/rest/getScanStatus"))
        .respond_with(ResponseTemplate::new(200).set_body_json(json!({"subsonic-response": {"status": "ok",
            "scanStatus": {"scanning": false, "count": 42, "folderCount": 3, "lastScan": "2026-01-01T00:00:00Z"}}})))
        .mount(&server)
        .await;
    Mock::given(path("/nd/rest/createPlaylist"))
        .and(query_param("name", "My List"))
        .respond_with(
            ResponseTemplate::new(200)
                .set_body_json(json!({"subsonic-response": {"status": "ok"}})),
        )
        .mount(&server)
        .await;

    let api = SubsonicApi::new(client_at(&format!("{}/nd/", server.uri())));
    let artists = api.get_artists().await.unwrap();
    assert_eq!(
        artists.iter().map(|a| a.id.as_str()).collect::<Vec<_>>(),
        ["ar1", "ar2"]
    );
    assert_eq!(artists[0].album_count, 2);

    let album = api.get_album("al1").await.unwrap();
    assert_eq!(album.songs[0].album_artist.as_deref(), Some("A"));
    assert_eq!(
        api.get_album("al1").await.unwrap(),
        album,
        "second call served from LRU"
    );

    let starred = api.get_starred2().await.unwrap();
    assert!(
        starred.song_ids.contains("s1")
            && starred.album_ids.contains("al1")
            && starred.artist_ids.is_empty()
    );

    let scan = api.get_scan_status().await.unwrap();
    assert_eq!(
        (scan.scanning, scan.count, scan.last_scan.as_deref()),
        (false, Some(42), Some("2026-01-01T00:00:00Z"))
    );

    let err = api
        .create_playlist("My List", &["a".into(), "b".into()])
        .await
        .unwrap_err();
    assert_eq!(
        err,
        AppError::Subsonic {
            message: "createPlaylist returned no playlist".into(),
            code: 0
        }
    );
    let reqs = server.received_requests().await.unwrap();
    let create = reqs
        .iter()
        .find(|r| r.url.path() == "/nd/rest/createPlaylist")
        .unwrap();
    let ids: Vec<String> = create
        .url
        .query_pairs()
        .filter(|(k, _)| k == "songId")
        .map(|(_, v)| v.into_owned())
        .collect();
    assert_eq!(ids, ["a", "b"]);
}
