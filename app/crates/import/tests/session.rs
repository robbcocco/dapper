use std::collections::HashMap;
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, AtomicUsize, Ordering};
use std::time::Duration;

use async_trait::async_trait;
use dapper_domain::{AppError, PlaylistProvider, Result, Song, SpotifyPlaylistData, SpotifyTrack};
use dapper_import::{ImportSession, ImportState, MATCH_CONCURRENCY, PlaylistSink, PlaylistSource, SongSearch};
use parking_lot::Mutex;

/// Library containing exactly one song per title; "fail" queries error.
struct FakeSearch {
    inflight: AtomicUsize,
    peak: AtomicUsize,
    delays: HashMap<String, u64>,
    available: AtomicBool,
}

#[async_trait]
impl SongSearch for FakeSearch {
    fn is_available(&self) -> bool {
        self.available.load(Ordering::SeqCst)
    }

    async fn search_songs(&self, query: &str, _count: usize) -> Result<Vec<Song>> {
        let now = self.inflight.fetch_add(1, Ordering::SeqCst) + 1;
        self.peak.fetch_max(now, Ordering::SeqCst);
        let title = query.trim_end_matches(" Artist").to_owned();
        tokio::time::sleep(Duration::from_millis(*self.delays.get(&title).unwrap_or(&5))).await;
        self.inflight.fetch_sub(1, Ordering::SeqCst);
        if title.starts_with("fail") {
            return Err(AppError::Network("boom".into()));
        }
        Ok(vec![Song { id: format!("id-{title}"), title, artist: Some("Artist".into()), ..Default::default() }])
    }
}

struct FakeSource {
    by_url: HashMap<String, (Vec<String>, u64)>,
}

#[async_trait]
impl PlaylistSource for FakeSource {
    async fn fetch(&self, url: &str) -> Result<SpotifyPlaylistData> {
        if url == "private" {
            return Err(AppError::Other("This playlist is private.".into()));
        }
        let (titles, delay) = self.by_url.get(url).ok_or_else(|| AppError::NotFound("unsupported".into()))?;
        tokio::time::sleep(Duration::from_millis(*delay)).await;
        Ok(SpotifyPlaylistData {
            name: url.to_owned(),
            tracks: titles
                .iter()
                .map(|t| SpotifyTrack { title: t.clone(), artist: "Artist".into(), album: None, duration_ms: None })
                .collect(),
            truncated: false,
            provider: PlaylistProvider::Spotify,
        })
    }
}

#[derive(Default)]
struct FakeSink {
    created: Mutex<Vec<(String, Vec<String>)>>,
    fail: bool,
}

#[async_trait]
impl PlaylistSink for FakeSink {
    async fn create_playlist(&self, name: &str, song_ids: &[String]) -> Result<()> {
        if self.fail {
            return Err(AppError::Network("down".into()));
        }
        self.created.lock().push((name.to_owned(), song_ids.to_vec()));
        Ok(())
    }
}

fn titles(n: usize) -> Vec<String> {
    (0..n).map(|i| format!("Track{i}")).collect()
}

fn session(
    playlists: &[(&str, Vec<String>, u64)],
    delays: HashMap<String, u64>,
    sink: Arc<FakeSink>,
) -> (Arc<ImportSession>, Arc<FakeSearch>) {
    let search = Arc::new(FakeSearch { inflight: 0.into(), peak: 0.into(), delays, available: true.into() });
    let source = Arc::new(FakeSource {
        by_url: playlists.iter().map(|(u, t, d)| (u.to_string(), (t.clone(), *d))).collect(),
    });
    (Arc::new(ImportSession::new(search.clone(), source, sink)), search)
}

fn review(s: &ImportSession) -> (Vec<Option<String>>, usize, usize) {
    match s.state() {
        ImportState::Review { matches, auto_matched_count, unmatched_count, .. } => {
            (matches.into_iter().map(|m| m.selected_id).collect(), auto_matched_count, unmatched_count)
        }
        other => panic!("expected review, got {other:?}"),
    }
}

#[tokio::test]
async fn matches_concurrently_preserving_order() {
    // Early tracks are slowest so completion order differs from playlist order.
    let t = titles(30);
    let delays = t.iter().enumerate().map(|(i, x)| (x.clone(), 40 - i as u64)).collect();
    let (s, search) = session(&[("u", t.clone(), 0)], delays, Default::default());
    let mut rx = s.subscribe();
    let watcher = tokio::spawn(async move {
        let mut seen = 0;
        while rx.changed().await.is_ok() {
            seen += 1;
            if matches!(*rx.borrow(), ImportState::Review { .. }) {
                break;
            }
        }
        seen
    });
    s.start_import("u").await;
    let (ids, auto, unmatched) = review(&s);
    assert_eq!(ids, t.iter().map(|x| Some(format!("id-{x}"))).collect::<Vec<_>>());
    assert_eq!((auto, unmatched), (30, 0));
    assert_eq!(search.peak.load(Ordering::SeqCst), MATCH_CONCURRENCY);
    // Throttled: far fewer publications than one per track.
    assert!(watcher.await.unwrap() < 30);
}

#[tokio::test]
async fn search_errors_become_unmatched() {
    let (s, _) = session(&[("u", vec!["a".into(), "fail1".into(), "b".into()], 0)], HashMap::new(), Default::default());
    s.start_import("u").await;
    let (ids, auto, unmatched) = review(&s);
    assert_eq!(ids, vec![Some("id-a".into()), None, Some("id-b".into())]);
    assert_eq!((auto, unmatched), (2, 1));
}

#[tokio::test]
async fn source_error_and_empty_playlist() {
    let (s, _) = session(&[("empty", vec![], 0)], HashMap::new(), Default::default());
    s.start_import("nope").await;
    assert_eq!(s.state(), ImportState::Error { message: "Unexpected error: unsupported".into(), tracks: None });
    s.start_import("private").await;
    assert_eq!(s.state(), ImportState::Error { message: "This playlist is private.".into(), tracks: None });
    s.start_import("empty").await;
    assert_eq!(review(&s).0, Vec::<Option<String>>::new());
}

#[tokio::test]
async fn new_run_discards_stale_results() {
    let slow: HashMap<_, _> = [("Old0".to_string(), 200)].into();
    let (s, _) = session(&[("old", vec!["Old0".into()], 0), ("new", vec!["New0".into()], 0)], slow, Default::default());
    let s2 = s.clone();
    let stale = tokio::spawn(async move { s2.start_import("old").await });
    tokio::time::sleep(Duration::from_millis(50)).await;
    s.start_import("new").await;
    stale.await.unwrap();
    assert_eq!(review(&s).0, vec![Some("id-New0".into())]);

    // reset during scraping wins too
    let (s, _) = session(&[("u", vec!["x".into()], 100)], HashMap::new(), Default::default());
    let s2 = s.clone();
    let run = tokio::spawn(async move { s2.start_import("u").await });
    tokio::time::sleep(Duration::from_millis(20)).await;
    s.reset();
    run.await.unwrap();
    assert_eq!(s.state(), ImportState::Idle);
}

#[tokio::test]
async fn selection_and_commit_skip_unmatched_in_order() {
    let sink = Arc::new(FakeSink::default());
    let (s, _) = session(&[("u", vec!["a".into(), "fail".into(), "b".into(), "c".into()], 0)], HashMap::new(), sink.clone());
    s.start_import("u").await;
    let before = s.state();
    s.set_selection(2, None, None);
    let manual = Song { id: "m".into(), title: "Manual".into(), ..Default::default() };
    s.set_selection(1, Some("m".into()), Some(manual.clone()));
    s.set_selection(99, Some("x".into()), None); // out of range: ignored
    // The earlier snapshot is untouched (immutable update).
    let ImportState::Review { matches: old, .. } = before else { panic!() };
    assert_eq!(old[2].selected_id.as_deref(), Some("id-b"));
    let ImportState::Review { matches, auto_matched_count, unmatched_count, .. } = s.state() else { panic!() };
    assert_eq!(matches[1].candidates[0].song, manual);
    assert_eq!(matches[1].best_score, 1.0);
    assert_eq!((auto_matched_count, unmatched_count), (3, 1));

    assert!(s.manual_search("  ").await.is_empty());
    assert_eq!(s.manual_search("z").await[0].id, "id-z");

    s.commit(Some("Mine")).await;
    assert_eq!(s.state(), ImportState::Done { playlist_name: "Mine".into(), imported_count: 3, skipped_count: 1 });
    assert_eq!(*sink.created.lock(), vec![("Mine".to_string(), vec!["id-a".into(), "m".into(), "id-c".into()])]);
    // Not in review any more: no-op.
    s.commit(None).await;
    assert_eq!(sink.created.lock().len(), 1);
}

#[tokio::test]
async fn commit_errors() {
    let sink = Arc::new(FakeSink { fail: true, ..Default::default() });
    let (s, _) = session(&[("u", vec!["fail".into(), "a".into()], 0)], HashMap::new(), sink);
    s.start_import("u").await;
    s.set_selection(1, None, None);
    s.commit(None).await;
    assert!(matches!(s.state(), ImportState::Error { ref message, .. } if message.starts_with("No songs are selected")));
    s.start_import("u").await;
    s.commit(None).await;
    assert_eq!(
        s.state(),
        ImportState::Error { message: "Could not create the playlist: down".into(), tracks: None }
    );
}

#[tokio::test]
async fn no_server_errors_before_scraping_and_on_commit() {
    let sink = Arc::new(FakeSink::default());
    let (s, search) = session(&[("u", vec!["a".into()], 0)], HashMap::new(), sink.clone());
    search.available.store(false, Ordering::SeqCst);
    let mut rx = s.subscribe();
    s.start_import("u").await;
    rx.borrow_and_update();
    assert_eq!(
        s.state(),
        ImportState::Error { message: "Connect a Navidrome server first, then try again.".into(), tracks: None }
    );
    assert!(!rx.has_changed().unwrap(), "no Scraping published after the error");

    search.available.store(true, Ordering::SeqCst);
    s.start_import("u").await;
    search.available.store(false, Ordering::SeqCst);
    s.commit(None).await;
    assert_eq!(
        s.state(),
        ImportState::Error {
            message: "Lost connection to the Navidrome server. Reconnect and try again.".into(),
            tracks: None
        }
    );
    assert!(sink.created.lock().is_empty());
}
