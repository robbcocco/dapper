use std::collections::HashSet;
use std::sync::Arc;

use dapper_api::{SubsonicApi, SubsonicClient};
use dapper_domain::{Album, AppError, Artist, LibraryReader, Song};
use parking_lot::Mutex;
use serde_json::{Value, json};
use tempfile::TempDir;
use wiremock::matchers::{method, path, query_param};
use wiremock::{Mock, MockServer, Request, Respond, ResponseTemplate};

use crate::*;

// ── Fixtures ─────────────────────────────────────────────────────────────────

fn envelope(body: Value) -> ResponseTemplate {
    let mut env = json!({"status": "ok", "version": "1.16.1"});
    if let (Value::Object(e), Value::Object(b)) = (&mut env, body) {
        e.extend(b);
    }
    ResponseTemplate::new(200).set_body_json(json!({ "subsonic-response": env }))
}

fn failed(code: i64) -> ResponseTemplate {
    ResponseTemplate::new(200).set_body_json(json!({
        "subsonic-response": {"status": "failed", "error": {"code": code, "message": "nope"}}
    }))
}

fn qp(req: &Request, key: &str) -> Option<String> {
    req.url
        .query_pairs()
        .find(|(k, _)| k == key)
        .map(|(_, v)| v.into_owned())
}

/// Mutable server state; responders read it on every request so a test can
/// change the "server library" between syncs.
#[derive(Default, Clone)]
struct ServerLib {
    last_scan: Option<String>,
    artists: Vec<Value>,
    albums: Vec<Value>,
    songs: Vec<Value>,
    starred_songs: Vec<String>,
    starred_albums: Vec<String>,
    genres: Vec<Value>,
    playlists: Vec<Value>,
}

type Shared = Arc<Mutex<ServerLib>>;

type Route = fn(&ServerLib, &Request) -> Value;

struct Handler(Shared, Route);

impl Respond for Handler {
    fn respond(&self, req: &Request) -> ResponseTemplate {
        envelope((self.1)(&self.0.lock(), req))
    }
}

fn page(items: &[Value], req: &Request, size: &str, offset: &str) -> Vec<Value> {
    let size: usize = qp(req, size).unwrap().parse().unwrap();
    let offset: usize = qp(req, offset).unwrap_or_default().parse().unwrap_or(0);
    items.iter().skip(offset).take(size).cloned().collect()
}

async fn mount(server: &MockServer, lib: &Shared) {
    let routes: [(&str, Route); 7] = [
        (
            "/rest/getScanStatus",
            |l, _| json!({"scanStatus": {"scanning": false, "count": l.songs.len(), "lastScan": l.last_scan}}),
        ),
        (
            "/rest/getArtists",
            |l, _| json!({"artists": {"index": [{"name": "#", "artist": l.artists}]}}),
        ),
        ("/rest/getAlbumList2", |l, r| {
            assert_eq!(qp(r, "type").as_deref(), Some("alphabeticalByName"));
            json!({"albumList2": {"album": page(&l.albums, r, "size", "offset")}})
        }),
        ("/rest/search3", |l, r| {
            assert_eq!(qp(r, "query").as_deref(), Some(""));
            json!({"searchResult3": {"song": page(&l.songs, r, "songCount", "songOffset")}})
        }),
        ("/rest/getStarred2", |l, _| {
            let ids = |v: &[String]| {
                v.iter()
                    .map(|id| json!({"id": id, "title": id}))
                    .collect::<Vec<_>>()
            };
            json!({"starred2": {"song": ids(&l.starred_songs), "album": ids(&l.starred_albums)}})
        }),
        (
            "/rest/getGenres",
            |l, _| json!({"genres": {"genre": l.genres}}),
        ),
        (
            "/rest/getPlaylists",
            |l, _| json!({"playlists": {"playlist": l.playlists}}),
        ),
    ];
    for (p, f) in routes {
        Mock::given(method("GET"))
            .and(path(p))
            .respond_with(Handler(lib.clone(), f))
            .mount(server)
            .await;
    }
}

fn song(id: &str, title: &str, album_id: &str, album: &str, artist: &str) -> Value {
    json!({"id": id, "title": title, "albumId": album_id, "album": album, "artist": artist,
           "artistId": format!("ar-{artist}"), "duration": 100, "suffix": "flac"})
}

fn album(id: &str, name: &str, artist: &str, year: Option<i32>, created: &str) -> Value {
    json!({"id": id, "name": name, "artist": artist, "artistId": format!("ar-{artist}"),
           "year": year, "created": created, "songCount": 1, "duration": 100})
}

fn small_library() -> ServerLib {
    ServerLib {
        last_scan: Some("2026-01-01T00:00:00Z".into()),
        artists: vec![
            json!({"id": "ar-The Beatles", "name": "The Beatles", "albumCount": 1, "musicBrainzId": "mb-beatles"}),
            json!({"id": "ar-Beyoncé", "name": "Beyoncé", "albumCount": 1}),
            json!({"id": "ar-Sigur Rós", "name": "Sigur Rós", "albumCount": 1}),
        ],
        albums: vec![
            album(
                "al-abbey",
                "Abbey Road",
                "The Beatles",
                Some(1969),
                "2026-01-03T00:00:00Z",
            ),
            album(
                "al-lemonade",
                "Lemonade",
                "Beyoncé",
                Some(2016),
                "2026-01-01T00:00:00Z",
            ),
            album(
                "al-takk",
                "Takk...",
                "Sigur Rós",
                None,
                "2026-01-02T00:00:00Z",
            ),
        ],
        songs: vec![
            json!({"id": "s-come", "title": "Come Together", "albumId": "al-abbey", "album": "Abbey Road",
                   "artist": "The Beatles", "track": 1, "discNumber": 1, "duration": 259, "genre": "Rock",
                   "userRating": 5, "starred": "2025-05-05T00:00:00Z"}),
            json!({"id": "s-something", "title": "Something", "albumId": "al-abbey", "album": "Abbey Road",
                   "artist": "The Beatles", "track": 2, "discNumber": 1, "duration": 182, "genre": "Rock"}),
            json!({"id": "s-sorry", "title": "Sorry", "albumId": "al-lemonade", "album": "Lemonade",
                   "artist": "Beyoncé", "albumArtist": "Beyoncé", "track": 1, "duration": 232, "genre": "R&B"}),
            json!({"id": "s-hoppipolla", "title": "Hoppípolla", "albumId": "al-takk", "album": "Takk...",
                   "artist": "Sigur Rós", "track": 2, "duration": 268, "genre": "Post-Rock"}),
            json!({"id": "s-glosoli", "title": "Glósóli", "albumId": "al-takk", "album": "Takk...",
                   "artist": "Sigur Rós", "track": 1, "duration": 375, "genre": "Rock"}),
        ],
        starred_songs: vec!["s-come".into(), "s-sorry".into()],
        starred_albums: vec!["al-takk".into()],
        genres: vec![
            json!({"value": "Post-Rock", "songCount": 1, "albumCount": 1}),
            json!({"value": "R&B", "songCount": 1, "albumCount": 1}),
            json!({"value": "Rock", "songCount": 3, "albumCount": 2}),
        ],
        playlists: vec![
            json!({"id": "pl-1", "name": "Mix", "songCount": 2, "duration": 441}),
            json!({"id": "pl-2", "name": "Chill", "songCount": 1, "duration": 268}),
        ],
    }
}

struct Harness {
    server: MockServer,
    lib: Shared,
    library: Library,
    _dir: TempDir,
}

impl Harness {
    async fn new(data: ServerLib) -> Self {
        // Not pooled: dropping it must really take the server offline.
        let server = MockServer::builder().start().await;
        let lib = Arc::new(Mutex::new(data));
        mount(&server, &lib).await;
        let api = Arc::new(SubsonicApi::new(
            SubsonicClient::new(&server.uri(), "u", "p").unwrap(),
        ));
        let dir = TempDir::new().unwrap();
        let library = Library::open(&Library::db_path(dir.path(), "srv"), "srv", api).unwrap();
        Self {
            server,
            lib,
            library,
            _dir: dir,
        }
    }

    async fn sync(&self, force: bool) -> (SyncReport, Vec<SyncProgress>) {
        let mut events = Vec::new();
        let report = self.library.sync(force, |p| events.push(p)).await.unwrap();
        (report, events)
    }

    async fn requests(&self, p: &str) -> usize {
        self.server
            .received_requests()
            .await
            .unwrap()
            .iter()
            .filter(|r| r.url.path() == p)
            .count()
    }

    fn db(&self) -> &LibraryDb {
        self.library.db()
    }
}

fn ids<T>(items: &[T], f: impl Fn(&T) -> &str) -> Vec<String> {
    items.iter().map(|i| f(i).to_string()).collect()
}

fn song_ids(s: &[Song]) -> Vec<String> {
    ids(s, |s| &s.id)
}

fn album_ids(a: &[Album]) -> Vec<String> {
    ids(a, |a| &a.id)
}

// ── Sync ─────────────────────────────────────────────────────────────────────

#[tokio::test]
async fn sync_pages_through_large_library() {
    let mut data = small_library();
    data.albums = (0..1203)
        .map(|i| {
            album(
                &format!("al{i:04}"),
                &format!("Album {i:04}"),
                "X",
                None,
                "",
            )
        })
        .collect();
    data.songs = (0..2501)
        .map(|i| {
            song(
                &format!("s{i:05}"),
                &format!("Song {i}"),
                &format!("al{:04}", i % 1203),
                "A",
                "X",
            )
        })
        .collect();
    let h = Harness::new(data).await;
    assert!(!h.library.is_ready());

    let (report, events) = h.sync(false).await;
    assert!(!report.skipped);
    assert_eq!(
        (report.artists, report.albums, report.songs),
        (3, 1203, 2501)
    );
    assert_eq!(h.requests("/rest/getAlbumList2").await, 3);
    assert_eq!(h.requests("/rest/search3").await, 6);
    assert!(h.library.is_ready());

    let status = h.library.status().await.unwrap();
    assert!(status.ready && status.completed_at.is_some());
    assert_eq!(
        (status.albums, status.songs, status.playlists),
        (1203, 2501, 2)
    );
    assert_eq!(status.last_scan.as_deref(), Some("2026-01-01T00:00:00Z"));

    let songs_progress: Vec<_> = events
        .iter()
        .filter(|e| e.phase == SyncPhase::Songs)
        .map(|e| (e.done, e.total))
        .collect();
    assert_eq!(
        songs_progress,
        [
            (0, Some(2501)),
            (500, Some(2501)),
            (1000, Some(2501)),
            (1500, Some(2501)),
            (2000, Some(2501)),
            (2500, Some(2501)),
            (2501, Some(2501))
        ]
    );
    assert_eq!(events.last().unwrap().phase, SyncPhase::Done);

    // Exactly-full last page needs one extra (empty) request.
    let mut data = small_library();
    data.songs = (0..500)
        .map(|i| song(&format!("s{i}"), "t", "al-abbey", "A", "X"))
        .collect();
    let h = Harness::new(data).await;
    let (report, _) = h.sync(false).await;
    assert_eq!(report.songs, 500);
    assert_eq!(h.requests("/rest/search3").await, 2);
}

#[tokio::test]
async fn resync_sweeps_rows_gone_from_server() {
    let h = Harness::new(small_library()).await;
    h.sync(false).await;
    assert!(h.db().song("s-sorry").unwrap().is_some());

    {
        let mut l = h.lib.lock();
        l.last_scan = Some("2026-02-01T00:00:00Z".into());
        l.songs.retain(|s| s["id"] != "s-sorry");
        l.albums.retain(|a| a["id"] != "al-lemonade");
        l.artists.retain(|a| a["id"] != "ar-Beyoncé");
        l.songs[0]["title"] = json!("Come Together (Remaster)");
    }
    let (report, _) = h.sync(false).await;
    assert!(!report.skipped);
    assert_eq!(
        (
            report.removed_artists,
            report.removed_albums,
            report.removed_songs
        ),
        (1, 1, 1)
    );
    assert!(h.db().song("s-sorry").unwrap().is_none());
    assert!(h.db().album("al-lemonade").unwrap().is_none());
    assert_eq!(h.db().artists().unwrap().len(), 2);

    // FTS follows deletes and renames.
    let r = h.db().search("sorry", SearchLimits::default()).unwrap();
    assert!(r.is_empty(), "{r:?}");
    let r = h.db().search("remaster", SearchLimits::default()).unwrap();
    assert_eq!(song_ids(&r.songs), ["s-come"]);
    let r = h.db().search("beyonce", SearchLimits::default()).unwrap();
    assert!(r.is_empty(), "{r:?}");
}

#[tokio::test]
async fn unchanged_scan_status_skips_listing_but_refreshes_stars_and_playlists() {
    let h = Harness::new(small_library()).await;
    h.sync(false).await;
    {
        let mut l = h.lib.lock();
        l.starred_songs = vec!["s-something".into()];
        l.playlists.remove(0);
        // Not visible to a skipped sync: listing is not re-read.
        l.songs[1]["title"] = json!("Changed");
    }
    let (report, _) = h.sync(false).await;
    assert!(report.skipped);
    assert_eq!((report.artists, report.albums, report.songs), (3, 3, 5));
    assert_eq!(h.requests("/rest/getAlbumList2").await, 1);
    assert_eq!(h.requests("/rest/search3").await, 1);
    assert_eq!(h.requests("/rest/getArtists").await, 1);
    assert_eq!(
        h.db().starred_song_ids().unwrap(),
        HashSet::from(["s-something".to_string()])
    );
    assert_eq!(ids(&h.db().playlists().unwrap(), |p| &p.id), ["pl-2"]);
    assert_eq!(
        h.db().song("s-something").unwrap().unwrap().title,
        "Something"
    );

    let (report, _) = h.sync(true).await;
    assert!(!report.skipped);
    assert_eq!(h.requests("/rest/search3").await, 2);
    assert_eq!(
        h.db().song("s-something").unwrap().unwrap().title,
        "Changed"
    );
}

#[tokio::test]
async fn interrupted_sync_keeps_previous_data_and_is_not_skipped_next_time() {
    let h = Harness::new(small_library()).await;
    h.sync(false).await;
    h.lib.lock().last_scan = Some("2026-03-01T00:00:00Z".into());
    h.server.reset().await;
    let lib = h.lib.clone();
    // Listing fails half-way: songs endpoint errors.
    Mock::given(path("/rest/search3"))
        .respond_with(failed(0))
        .mount(&h.server)
        .await;
    mount(&h.server, &lib).await;
    let err = h.library.sync(false, |_| {}).await.unwrap_err();
    assert!(matches!(err, AppError::Subsonic { .. }));
    assert_eq!(h.db().songs_count().unwrap(), 5);
    assert_eq!(
        h.db().status().unwrap().last_scan.as_deref(),
        Some("2026-01-01T00:00:00Z")
    );

    h.server.reset().await;
    mount(&h.server, &lib).await;
    let (report, _) = h.sync(false).await;
    assert!(!report.skipped);
    assert_eq!(report.removed_songs, 0);
    assert_eq!(h.db().songs_count().unwrap(), 5);
}

#[tokio::test]
async fn empty_song_listing_of_nonempty_library_does_not_sweep() {
    let h = Harness::new(small_library()).await;
    h.sync(false).await;
    h.lib.lock().last_scan = Some("2026-04-01T00:00:00Z".into());
    h.server.reset().await;
    Mock::given(path("/rest/search3"))
        .respond_with(envelope(json!({"searchResult3": {}})))
        .mount(&h.server)
        .await;
    mount(&h.server, &h.lib).await;
    assert!(h.library.sync(false, |_| {}).await.is_err());
    assert_eq!(h.db().songs_count().unwrap(), 5);
}

#[tokio::test]
async fn starred_flags_follow_get_starred2() {
    let h = Harness::new(small_library()).await;
    h.sync(false).await;
    let db = h.db();
    assert_eq!(
        db.starred_song_ids().unwrap(),
        HashSet::from(["s-come".to_string(), "s-sorry".to_string()])
    );
    // Already-starred rows keep the server's timestamp.
    assert_eq!(
        db.song("s-come").unwrap().unwrap().starred.as_deref(),
        Some("2025-05-05T00:00:00Z")
    );
    assert!(db.song("s-sorry").unwrap().unwrap().starred.is_some());
    assert!(db.album("al-takk").unwrap().unwrap().starred.is_some());
    assert!(db.album("al-abbey").unwrap().unwrap().starred.is_none());
    assert_eq!(h.library.starred_song_ids().await.unwrap().len(), 2);
}

#[tokio::test]
async fn genres_sorted_by_song_count_and_albums_by_genre_include_song_genres() {
    let h = Harness::new(small_library()).await;
    h.sync(false).await;
    let genres = h.library.genres().await.unwrap();
    assert_eq!(ids(&genres, |g| &g.name), ["Rock", "Post-Rock", "R&B"]);
    assert_eq!((genres[0].song_count, genres[0].album_count), (3, 2));
    // al-takk has no album genre but one of its songs is Rock.
    assert_eq!(
        album_ids(&h.library.albums_by_genre("Rock").await.unwrap()),
        ["al-abbey", "al-takk"]
    );
    assert_eq!(
        album_ids(&h.library.albums_by_genre("R&B").await.unwrap()),
        ["al-lemonade"]
    );
}

#[tokio::test]
async fn artists_keep_server_order_and_musicbrainz_ids() {
    let h = Harness::new(small_library()).await;
    h.sync(false).await;
    let artists: Vec<Artist> = h.library.artists().await.unwrap();
    assert_eq!(
        ids(&artists, |a| &a.name),
        ["The Beatles", "Beyoncé", "Sigur Rós"]
    );
    assert_eq!(artists[0].music_brainz_id.as_deref(), Some("mb-beatles"));
    assert_eq!(artists[0].album_count, 1);
    let albums = h.library.artist_albums("ar-Sigur Rós").await.unwrap();
    assert_eq!(album_ids(&albums), ["al-takk"]);
}

#[tokio::test]
async fn album_songs_ordered_by_disc_and_track_with_album_artist_fallback() {
    let h = Harness::new(small_library()).await;
    h.sync(false).await;
    let a = h.library.album("al-takk").await.unwrap();
    assert_eq!(song_ids(&a.songs), ["s-glosoli", "s-hoppipolla"]);
    assert!(
        a.songs
            .iter()
            .all(|s| s.album_artist.as_deref() == Some("Sigur Rós"))
    );
    assert_eq!(a.created.as_deref(), Some("2026-01-02T00:00:00Z"));
    assert_eq!(
        song_ids(&h.library.album_songs("al-abbey").await.unwrap()),
        ["s-come", "s-something"]
    );
}

#[tokio::test]
async fn playlists_sync_and_server_first_detail_with_offline_fallback() {
    let h = Harness::new(small_library()).await;
    h.sync(false).await;
    assert_eq!(
        ids(&h.library.playlists().await.unwrap(), |p| &p.name),
        ["Mix", "Chill"]
    );
    // Entries not fetched yet: nothing to serve offline.
    assert!(h.db().playlist("pl-1").unwrap().is_none());

    Mock::given(path("/rest/getPlaylist"))
        .and(query_param("id", "pl-1"))
        .respond_with(envelope(
            json!({"playlist": {"id": "pl-1", "name": "Mix", "songCount": 2,
            "duration": 441, "entry": [{"id": "s-come", "title": "Come Together"},
                                       {"id": "s-hoppipolla", "title": "Hoppípolla"}]}}),
        ))
        .mount(&h.server)
        .await;
    let p = h.library.playlist("pl-1").await.unwrap();
    assert_eq!(song_ids(&p.songs), ["s-come", "s-hoppipolla"]);
    assert_eq!(h.db().playlist("pl-1").unwrap().unwrap(), p);

    // A metadata change from the listing marks cached entries stale.
    h.lib.lock().playlists[0]["songCount"] = json!(3);
    h.db()
        .replace_playlists(&h.library.api().get_playlists().await.unwrap())
        .unwrap();
    assert!(h.db().playlist("pl-1").unwrap().is_none());
    h.library.playlist("pl-1").await.unwrap();

    // Server gone: cached copy is served; unknown playlists still error.
    let Harness {
        server,
        library,
        _dir,
        ..
    } = h;
    drop(server);
    assert_eq!(
        song_ids(&library.playlist("pl-1").await.unwrap().songs),
        ["s-come", "s-hoppipolla"]
    );
    assert!(matches!(
        library.playlist("pl-2").await,
        Err(AppError::Network(_))
    ));
    // Cached reads keep working offline.
    assert_eq!(library.artists().await.unwrap().len(), 3);
}

// ── Concurrency / cancellation ───────────────────────────────────────────────

#[tokio::test]
async fn instances_on_same_db_serialise_their_syncs() {
    let h = Harness::new(small_library()).await;
    // Same file reached through a different spelling of the path.
    let alias = h
        ._dir
        .path()
        .join("library")
        .join("..")
        .join("library")
        .join("srv.db");
    let other = Library::open(&alias, "srv", h.library.api().clone()).unwrap();

    let (a, b) = tokio::join!(h.library.sync(false, |_| {}), other.sync(false, |_| {}));
    let (a, b) = (a.unwrap(), b.unwrap());
    assert!(a.skipped != b.skipped, "{a:?} {b:?}");
    assert_eq!(h.requests("/rest/search3").await, 1);
    assert!(h.library.is_ready() && other.is_ready());
    let status = other.status().await.unwrap();
    assert_eq!((status.artists, status.albums, status.songs), (3, 3, 5));

    // Forced passes from both instances still leave one consistent copy.
    h.lib.lock().songs.pop();
    let (a, b) = tokio::join!(h.library.sync(true, |_| {}), other.sync(true, |_| {}));
    assert!(!a.unwrap().skipped && !b.unwrap().skipped);
    assert_eq!(h.db().songs_count().unwrap(), 4);
    assert_eq!(other.db().songs_count().unwrap(), 4);
}

#[test]
fn superseded_pass_cannot_stamp_or_sweep() {
    let (_d, db) = seeded_db();
    let old = db.begin_generation().unwrap();
    let new = db.begin_generation().unwrap();
    let late = [mk_song("late", "Late", "X", "Y", None, 1)];
    assert_eq!(db.upsert_songs(&late, old), Err(AppError::Cancelled));
    assert_eq!(db.upsert_albums(&[], old), Err(AppError::Cancelled));
    assert_eq!(db.upsert_artists(&[], 0, old), Err(AppError::Cancelled));
    let mark = crate::db::ScanMark {
        last_scan: Some("s".into()),
        count: 1,
    };
    assert_eq!(db.finish_sync(old, &mark, "t"), Err(AppError::Cancelled));
    assert!(db.song("late").unwrap().is_none());
    assert!(!db.is_ready().unwrap());

    db.upsert_songs(&late, new).unwrap();
    assert_eq!(db.finish_sync(new, &mark, "t").unwrap(), (0, 4, 5));
    assert_eq!(
        db.all_song_ids().unwrap(),
        HashSet::from(["late".to_string()])
    );
}

#[tokio::test]
async fn aborted_sync_releases_lock_and_next_pass_is_complete() {
    let h = Harness::new(small_library()).await;
    h.server.reset().await;
    Mock::given(path("/rest/search3"))
        .respond_with(
            envelope(json!({"searchResult3": {}})).set_delay(std::time::Duration::from_secs(30)),
        )
        .mount(&h.server)
        .await;
    mount(&h.server, &h.lib).await;

    let (tx, mut rx) = tokio::sync::mpsc::unbounded_channel();
    let lib = h.library.clone();
    let task = tokio::spawn(async move {
        lib.sync(false, move |p| {
            let _ = tx.send(p.phase);
        })
        .await
    });
    while rx.recv().await != Some(SyncPhase::Songs) {}
    task.abort();
    assert!(task.await.unwrap_err().is_cancelled());
    assert!(!h.library.is_ready());

    h.server.reset().await;
    mount(&h.server, &h.lib).await;
    let other = Library::open(
        &Library::db_path(h._dir.path(), "srv"),
        "srv",
        h.library.api().clone(),
    )
    .unwrap();
    let report = tokio::time::timeout(std::time::Duration::from_secs(5), other.sync(false, |_| {}))
        .await
        .expect("lock released by the aborted pass")
        .unwrap();
    assert!(!report.skipped);
    assert_eq!((report.artists, report.albums, report.songs), (3, 3, 5));
    assert_eq!(other.db().status().unwrap().songs, 5);
}

// ── Write-through ────────────────────────────────────────────────────────────

#[tokio::test]
async fn star_and_rating_write_through_after_server_accepts() {
    let h = Harness::new(small_library()).await;
    h.sync(false).await;
    for p in ["/rest/star", "/rest/unstar", "/rest/setRating"] {
        Mock::given(path(p))
            .and(query_param("id", "s-something"))
            .respond_with(envelope(json!({})))
            .mount(&h.server)
            .await;
    }
    Mock::given(path("/rest/setRating"))
        .and(query_param("id", "s-glosoli"))
        .respond_with(failed(70))
        .mount(&h.server)
        .await;
    Mock::given(path("/rest/star"))
        .and(query_param("id", "s-glosoli"))
        .respond_with(failed(70))
        .mount(&h.server)
        .await;

    h.library.star("s-something").await.unwrap();
    assert!(
        h.library
            .starred_song_ids()
            .await
            .unwrap()
            .contains("s-something")
    );
    h.library.unstar("s-something").await.unwrap();
    assert!(
        !h.library
            .starred_song_ids()
            .await
            .unwrap()
            .contains("s-something")
    );

    h.library.set_rating("s-something", 4).await.unwrap();
    let all = vec![
        "s-something".to_string(),
        "s-come".to_string(),
        "s-glosoli".to_string(),
    ];
    let r = h.library.ratings(all.clone()).await.unwrap();
    assert_eq!(
        (r["s-something"], r["s-come"], r.get("s-glosoli")),
        (4, 5, None)
    );
    h.library.set_rating("s-something", 0).await.unwrap();
    assert!(
        !h.library
            .ratings(all)
            .await
            .unwrap()
            .contains_key("s-something")
    );

    // Rejected by the server: cache untouched.
    assert!(h.library.set_rating("s-glosoli", 3).await.is_err());
    assert!(
        h.db()
            .song("s-glosoli")
            .unwrap()
            .unwrap()
            .user_rating
            .is_none()
    );
    assert!(h.library.star("s-glosoli").await.is_err());
    assert!(h.db().song("s-glosoli").unwrap().unwrap().starred.is_none());
}

#[tokio::test]
async fn playlist_edits_go_to_server_then_refresh_cache() {
    let h = Harness::new(small_library()).await;
    h.sync(false).await;
    let entry = |id: &str| json!({"id": id, "title": id});

    Mock::given(path("/rest/createPlaylist"))
        .and(query_param("name", "New"))
        .respond_with(envelope(
            json!({"playlist": {"id": "pl-3", "name": "New", "songCount": 1,
            "entry": [entry("s-sorry")]}}),
        ))
        .mount(&h.server)
        .await;
    h.lib
        .lock()
        .playlists
        .push(json!({"id": "pl-3", "name": "New", "songCount": 1}));
    let created = h
        .library
        .create_playlist("New", &["s-sorry".into()])
        .await
        .unwrap();
    assert_eq!(created.id, "pl-3");
    assert_eq!(
        ids(&h.db().playlists().unwrap(), |p| &p.id),
        ["pl-1", "pl-2", "pl-3"]
    );
    assert_eq!(
        song_ids(&h.db().playlist("pl-3").unwrap().unwrap().songs),
        ["s-sorry"]
    );

    // Rename + add: server is updated, then listing and entries are re-read.
    Mock::given(path("/rest/updatePlaylist"))
        .and(query_param("playlistId", "pl-3"))
        .respond_with(envelope(json!({})))
        .expect(3)
        .mount(&h.server)
        .await;
    let detail = Arc::new(Mutex::new(
        json!({"id": "pl-3", "name": "Renamed", "songCount": 1,
        "entry": [entry("s-sorry")]}),
    ));
    struct Detail(Arc<Mutex<Value>>);
    impl Respond for Detail {
        fn respond(&self, _: &Request) -> ResponseTemplate {
            envelope(json!({"playlist": self.0.lock().clone()}))
        }
    }
    Mock::given(path("/rest/getPlaylist"))
        .respond_with(Detail(detail.clone()))
        .mount(&h.server)
        .await;

    h.lib.lock().playlists[2]["name"] = json!("Renamed");
    let p = h.library.rename_playlist("pl-3", "Renamed").await.unwrap();
    assert_eq!(p.name, "Renamed");
    assert_eq!(h.db().playlists().unwrap()[2].name, "Renamed");

    *detail.lock() = json!({"id": "pl-3", "name": "Renamed", "songCount": 2,
        "entry": [entry("s-sorry"), entry("s-come")]});
    h.lib.lock().playlists[2]["songCount"] = json!(2);
    h.library
        .add_to_playlist("pl-3", &["s-come".into()])
        .await
        .unwrap();
    assert_eq!(
        song_ids(&h.db().playlist("pl-3").unwrap().unwrap().songs),
        ["s-sorry", "s-come"]
    );

    *detail.lock() =
        json!({"id": "pl-3", "name": "Renamed", "songCount": 1, "entry": [entry("s-come")]});
    h.lib.lock().playlists[2]["songCount"] = json!(1);
    h.library.remove_from_playlist("pl-3", &[0]).await.unwrap();
    assert_eq!(
        song_ids(&h.db().playlist("pl-3").unwrap().unwrap().songs),
        ["s-come"]
    );
    let removes: Vec<_> = h
        .server
        .received_requests()
        .await
        .unwrap()
        .into_iter()
        .filter(|r| r.url.path() == "/rest/updatePlaylist")
        .filter_map(|r| qp(&r, "songIndexToRemove"))
        .collect();
    assert_eq!(removes, ["0"]);

    Mock::given(path("/rest/deletePlaylist"))
        .and(query_param("id", "pl-3"))
        .respond_with(envelope(json!({})))
        .mount(&h.server)
        .await;
    h.library.delete_playlist("pl-3").await.unwrap();
    assert_eq!(
        ids(&h.db().playlists().unwrap(), |p| &p.id),
        ["pl-1", "pl-2"]
    );
    assert!(h.db().playlist("pl-3").unwrap().is_none());
}

// ── Server fallback before the first sync ────────────────────────────────────

#[tokio::test]
async fn reads_hit_server_until_first_sync_completes() {
    let h = Harness::new(small_library()).await;
    Mock::given(path("/rest/search3"))
        .and(query_param("query", "beat"))
        .respond_with(envelope(
            json!({"searchResult3": {"artist": [{"id": "ar-x", "name": "Beat"}]}}),
        ))
        .with_priority(1)
        .mount(&h.server)
        .await;

    assert_eq!(h.library.artists().await.unwrap().len(), 3);
    let page = h
        .library
        .albums_page(0, 2, AlbumSort::Name, SortDir::Asc)
        .await
        .unwrap();
    assert_eq!((page.items.len(), page.total), (2, None));
    let page = h
        .library
        .songs_page(4, 10, SongSort::Title, SortDir::Asc)
        .await
        .unwrap();
    assert_eq!(
        (song_ids(&page.items), page.total),
        (vec!["s-glosoli".to_string()], None)
    );
    assert_eq!(h.library.starred_song_ids().await.unwrap().len(), 2);
    assert_eq!(
        ids(
            &h.library
                .search("  beat ", SearchLimits::default())
                .await
                .unwrap()
                .artists,
            |a| &a.id
        ),
        ["ar-x"]
    );
    assert_eq!(h.library.genres().await.unwrap()[0].name, "Rock");
    assert_eq!(
        LibraryReader::all_song_ids(&h.library).await.unwrap().len(),
        5
    );
    assert_eq!(
        LibraryReader::all_albums(&h.library).await.unwrap().len(),
        3
    );
    assert_eq!(h.library.playlists().await.unwrap().len(), 2);
    assert_eq!(h.db().songs_count().unwrap(), 0);

    h.sync(false).await;
    let before = h.server.received_requests().await.unwrap().len();
    assert_eq!(h.library.artists().await.unwrap().len(), 3);
    let page = h
        .library
        .albums_page(0, 2, AlbumSort::Name, SortDir::Asc)
        .await
        .unwrap();
    assert_eq!(page.total, Some(3));
    assert_eq!(
        LibraryReader::all_albums(&h.library).await.unwrap().len(),
        3
    );
    assert!(
        h.library
            .search("beat", SearchLimits::default())
            .await
            .unwrap()
            .artists[0]
            .id
            == "ar-The Beatles"
    );
    assert_eq!(h.server.received_requests().await.unwrap().len(), before);

    // Readiness survives reopening the database.
    let reopened = Library::open(
        &Library::db_path(h._dir.path(), "srv"),
        "srv",
        h.library.api().clone(),
    )
    .unwrap();
    assert!(reopened.is_ready());
}

// ── Cache queries without a server ───────────────────────────────────────────

fn mk_song(id: &str, title: &str, artist: &str, album: &str, year: Option<i32>, dur: i64) -> Song {
    Song {
        id: id.into(),
        title: title.into(),
        artist: Some(artist.into()),
        album: Some(album.into()),
        album_id: Some(format!("al-{album}")),
        year,
        duration: Some(dur),
        ..Default::default()
    }
}

fn mk_album(id: &str, name: &str, artist: &str, year: Option<i32>, created: Option<&str>) -> Album {
    Album {
        id: id.into(),
        name: name.into(),
        artist: Some(artist.into()),
        year,
        created: created.map(Into::into),
        ..Default::default()
    }
}

fn seeded_db() -> (TempDir, LibraryDb) {
    let dir = TempDir::new().unwrap();
    let db = LibraryDb::open(&dir.path().join("x.db")).unwrap();
    let generation = db.begin_generation().unwrap();
    db.upsert_albums(
        &[
            mk_album(
                "a1",
                "zebra",
                "Alpha",
                Some(2001),
                Some("2026-01-02T00:00:00Z"),
            ),
            mk_album("a2", "Apple", "beta", None, Some("2026-01-03T00:00:00Z")),
            mk_album("a3", "Éclair", "Alpha", Some(1999), None),
            mk_album(
                "a4",
                "mango",
                "Gamma",
                Some(2001),
                Some("2026-01-01T00:00:00Z"),
            ),
        ],
        generation,
    )
    .unwrap();
    db.upsert_songs(
        &[
            mk_song(
                "s1",
                "Crème Brûlée",
                "Ludovico Einaudi",
                "Una Mattina",
                Some(2004),
                300,
            ),
            mk_song(
                "s2",
                "abbey lane",
                "The Beatles",
                "Abbey Road",
                Some(1969),
                120,
            ),
            mk_song("s3", "Zygote", "Àlvaro", "Mañana", None, 200),
            mk_song(
                "s4",
                "Come Together",
                "The Beatles",
                "Abbey Road",
                Some(1969),
                259,
            ),
            mk_song("s5", "Road Trip", "Nobody", "Highways", Some(2020), 10),
        ],
        generation,
    )
    .unwrap();
    (dir, db)
}

#[test]
fn fts5_is_available_in_bundled_sqlite() {
    let c = rusqlite::Connection::open_in_memory().unwrap();
    c.execute_batch(
        "CREATE VIRTUAL TABLE t USING fts5(x, tokenize='unicode61 remove_diacritics 2')",
    )
    .unwrap();
}

#[test]
fn search_ignores_diacritics_and_case() {
    let (_d, db) = seeded_db();
    let l = SearchLimits::default();
    assert_eq!(
        song_ids(&db.search("creme brulee", l).unwrap().songs),
        ["s1"]
    );
    assert_eq!(song_ids(&db.search("CRÈME", l).unwrap().songs), ["s1"]);
    assert_eq!(
        song_ids(&db.search("alvaro manana", l).unwrap().songs),
        ["s3"]
    );
    assert_eq!(album_ids(&db.search("eclair", l).unwrap().albums), ["a3"]);
}

#[test]
fn search_matches_prefixes_and_all_words_across_columns() {
    let (_d, db) = seeded_db();
    let l = SearchLimits::default();
    let mut hits = song_ids(&db.search("abb", l).unwrap().songs);
    hits.sort();
    assert_eq!(hits, ["s2", "s4"]);
    // "beatles" (artist) AND "come" (title).
    assert_eq!(
        song_ids(&db.search("beatles com", l).unwrap().songs),
        ["s4"]
    );
    // Each word must match somewhere.
    assert!(db.search("beatles einaudi", l).unwrap().songs.is_empty());
    // Single-letter prefix and FTS syntax characters are plain text.
    assert_eq!(song_ids(&db.search("z", l).unwrap().songs), ["s3"]);
    assert!(
        db.search("\"road\" OR -x NEAR(", l)
            .unwrap()
            .songs
            .is_empty()
    );
    assert_eq!(
        song_ids(
            &db.search("road\"", SearchLimits { songs: 10, ..l })
                .unwrap()
                .songs
        )
        .len(),
        3
    );
    assert!(db.search("  -- ", l).unwrap().is_empty());
    assert_eq!(
        db.search("road", SearchLimits { songs: 1, ..l })
            .unwrap()
            .songs
            .len(),
        1
    );
}

#[test]
fn album_windows_sort_and_page() {
    let (_d, db) = seeded_db();
    let w = |o, n, s, d| album_ids(&db.albums_window(o, n, s, d).unwrap());
    assert_eq!(
        w(0, 10, AlbumSort::Name, SortDir::Asc),
        ["a2", "a4", "a1", "a3"]
    );
    assert_eq!(w(1, 2, AlbumSort::Name, SortDir::Asc), ["a4", "a1"]);
    assert_eq!(
        w(0, 10, AlbumSort::Name, SortDir::Desc),
        ["a3", "a1", "a4", "a2"]
    );
    // Artist ties broken by year.
    assert_eq!(
        w(0, 10, AlbumSort::Artist, SortDir::Asc),
        ["a3", "a1", "a2", "a4"]
    );
    // Missing years last in either direction; equal years by artist.
    assert_eq!(
        w(0, 10, AlbumSort::Year, SortDir::Asc),
        ["a3", "a1", "a4", "a2"]
    );
    assert_eq!(
        w(0, 10, AlbumSort::Year, SortDir::Desc),
        ["a1", "a4", "a3", "a2"]
    );
    assert_eq!(
        w(0, 10, AlbumSort::Recent, SortDir::Desc),
        ["a2", "a1", "a4", "a3"]
    );
    assert_eq!(album_ids(&db.recent_albums(2).unwrap()), ["a2", "a1"]);
    assert_eq!(db.albums_count().unwrap(), 4);
    assert_eq!(
        w(4, 10, AlbumSort::Name, SortDir::Asc),
        Vec::<String>::new()
    );
}

#[test]
fn song_windows_sort_and_page() {
    let (_d, db) = seeded_db();
    let w = |o, n, s, d| song_ids(&db.songs_window(o, n, s, d).unwrap());
    assert_eq!(
        w(0, 10, SongSort::Title, SortDir::Asc),
        ["s2", "s4", "s1", "s5", "s3"]
    );
    assert_eq!(
        w(0, 10, SongSort::Duration, SortDir::Desc),
        ["s1", "s4", "s3", "s2", "s5"]
    );
    assert_eq!(
        w(0, 10, SongSort::Artist, SortDir::Asc),
        ["s1", "s5", "s2", "s4", "s3"]
    );
    assert_eq!(
        w(0, 10, SongSort::Album, SortDir::Asc),
        ["s2", "s4", "s5", "s3", "s1"]
    );
    assert_eq!(
        w(0, 10, SongSort::Track, SortDir::Desc),
        ["s1", "s3", "s5", "s2", "s4"]
    );
    assert_eq!(
        serde_json::to_value(SongSort::Track).unwrap(),
        json!("track")
    );
    assert_eq!(
        w(0, 10, SongSort::Year, SortDir::Asc),
        ["s2", "s4", "s1", "s5", "s3"]
    );
    assert_eq!(w(2, 2, SongSort::Title, SortDir::Asc), ["s1", "s5"]);
    assert_eq!(
        db.song_ids(1, 3, SongSort::Title, SortDir::Asc).unwrap(),
        ["s4", "s1", "s5"]
    );
    assert_eq!(db.songs_count().unwrap(), 5);
    assert_eq!(db.all_song_ids().unwrap().len(), 5);
}

#[test]
fn reopening_migrated_db_is_idempotent() {
    let (dir, db) = seeded_db();
    drop(db);
    let db = LibraryDb::open(&dir.path().join("x.db")).unwrap();
    assert_eq!(db.songs_count().unwrap(), 5);
    assert!(!db.is_ready().unwrap());
}

// ── Live smoke ───────────────────────────────────────────────────────────────

/// `cargo test -p dapper-library live_demo_sync -- --ignored --nocapture`
#[tokio::test]
#[ignore = "network: syncs demo.navidrome.org"]
async fn live_demo_sync() {
    let api = Arc::new(SubsonicApi::new(
        SubsonicClient::new("https://demo.navidrome.org", "demo", "demo").unwrap(),
    ));
    let dir = TempDir::new().unwrap();
    let library = Library::open(&Library::db_path(dir.path(), "demo"), "demo", api).unwrap();
    let t = std::time::Instant::now();
    let report = library.sync(false, |_| {}).await.unwrap();
    println!("first sync {:?}: {report:?}", t.elapsed());
    println!("status: {:?}", library.status().await.unwrap());
    let t = std::time::Instant::now();
    let again = library.sync(false, |_| {}).await.unwrap();
    println!("second sync {:?}: skipped={}", t.elapsed(), again.skipped);
    println!("genres: {}", library.genres().await.unwrap().len());
    println!(
        "starred songs: {}",
        library.starred_song_ids().await.unwrap().len()
    );
    let r = library
        .search("the", SearchLimits::default())
        .await
        .unwrap();
    println!(
        "search 'the': {} artists, {} albums, {} songs; first song: {:?}",
        r.artists.len(),
        r.albums.len(),
        r.songs.len(),
        r.songs.first().map(|s| (&s.title, &s.artist, &s.album))
    );
    let page = library
        .songs_page(0, 3, SongSort::Title, SortDir::Asc)
        .await
        .unwrap();
    println!(
        "first songs by title: {:?}",
        page.items.iter().map(|s| &s.title).collect::<Vec<_>>()
    );
    assert!(library.is_ready() && report.songs > 0);
}
