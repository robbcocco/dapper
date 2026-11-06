//! Import workflow state machine.
//! Port of `spotify_import_notifier.dart` + `spotify_import_state.dart`.

use std::sync::Arc;
use std::sync::atomic::{AtomicUsize, Ordering};
use std::time::{Duration, Instant};

use dapper_domain::{AppError, Song, SpotifyTrack};
use parking_lot::Mutex;
use serde::Serialize;
use tokio::sync::watch;

use crate::matcher::{RankedSong, SEARCH_COUNT, SongMatcher, TrackMatch};
use crate::ports::{PlaylistSink, PlaylistSource, SongSearch};

/// Max concurrent library searches while matching.
pub const MATCH_CONCURRENCY: usize = 6;
/// Minimum interval between `Matching` progress publications.
const PROGRESS_INTERVAL: Duration = Duration::from_millis(100);

#[derive(Debug, Clone, PartialEq, Serialize)]
#[serde(tag = "kind", rename_all = "camelCase", rename_all_fields = "camelCase")]
pub enum ImportState {
    Idle,
    Scraping,
    Matching { playlist_name: String, done: usize, total: usize },
    Review {
        playlist_name: String,
        truncated: bool,
        matches: Vec<TrackMatch>,
        auto_matched_count: usize,
        unmatched_count: usize,
    },
    Creating,
    Done { playlist_name: String, imported_count: usize, skipped_count: usize },
    /// `tracks` is set when the failure happened after scraping succeeded.
    Error { message: String, tracks: Option<Vec<SpotifyTrack>> },
}

impl ImportState {
    fn review(playlist_name: String, truncated: bool, matches: Vec<TrackMatch>) -> Self {
        let auto = matches.iter().filter(|m| m.selected_id.is_some()).count();
        let unmatched = matches.len() - auto;
        Self::Review { playlist_name, truncated, matches, auto_matched_count: auto, unmatched_count: unmatched }
    }

    fn error(message: impl Into<String>) -> Self {
        Self::Error { message: message.into(), tracks: None }
    }
}

pub struct ImportSession {
    search: Arc<dyn SongSearch>,
    source: Arc<dyn PlaylistSource>,
    sink: Arc<dyn PlaylistSink>,
    tx: watch::Sender<ImportState>,
    /// Bumped by every new run / reset. Held while publishing so a stale run
    /// can never overwrite state belonging to a newer one.
    epoch: Mutex<u64>,
}

impl ImportSession {
    pub fn new(search: Arc<dyn SongSearch>, source: Arc<dyn PlaylistSource>, sink: Arc<dyn PlaylistSink>) -> Self {
        Self { search, source, sink, tx: watch::Sender::new(ImportState::Idle), epoch: Mutex::new(0) }
    }

    pub fn subscribe(&self) -> watch::Receiver<ImportState> {
        self.tx.subscribe()
    }

    pub fn state(&self) -> ImportState {
        self.tx.borrow().clone()
    }

    fn begin(&self, state: ImportState) -> u64 {
        let mut e = self.epoch.lock();
        *e += 1;
        self.tx.send_replace(state);
        *e
    }

    /// Publishes `state` iff `epoch` is still current.
    fn publish(&self, epoch: u64, state: ImportState) -> bool {
        let e = self.epoch.lock();
        if *e != epoch {
            return false;
        }
        self.tx.send_replace(state);
        true
    }

    fn is_current(&self, epoch: u64) -> bool {
        *self.epoch.lock() == epoch
    }

    /// Back to the URL-entry screen; in-flight runs are discarded.
    pub fn reset(&self) {
        self.begin(ImportState::Idle);
    }

    /// Fetches the playlist and matches every track; ends in `Review` or `Error`.
    pub async fn start_import(&self, url: &str) {
        if !self.search.is_available() {
            self.begin(ImportState::error("Connect a Navidrome server first, then try again."));
            return;
        }
        let epoch = self.begin(ImportState::Scraping);
        let playlist = match self.source.fetch(url).await {
            Ok(p) => p,
            Err(e) => {
                // Scrapers report user-actionable failures (Dart
                // `SpotifyScrapeException`) as `Other`; anything else is unexpected.
                let message = match e {
                    AppError::Other(m) => m,
                    e => format!("Unexpected error: {e}"),
                };
                self.publish(epoch, ImportState::error(message));
                return;
            }
        };
        let total = playlist.tracks.len();
        let name = playlist.name.clone();
        if !self.publish(epoch, ImportState::Matching { playlist_name: name.clone(), done: 0, total }) {
            return;
        }

        let matcher = SongMatcher::new(self.search.clone());
        let tracks = &playlist.tracks;
        let cursor = AtomicUsize::new(0);
        let results: Mutex<Vec<Option<TrackMatch>>> = Mutex::new(vec![None; total]);
        let progress = Mutex::new((0usize, Instant::now()));
        let worker = || async {
            loop {
                let i = cursor.fetch_add(1, Ordering::Relaxed);
                if i >= total {
                    return;
                }
                let m = matcher.match_track(&tracks[i]).await;
                if !self.is_current(epoch) {
                    return;
                }
                results.lock()[i] = Some(m);
                let mut p = progress.lock();
                p.0 += 1;
                let now = Instant::now();
                if now.duration_since(p.1) >= PROGRESS_INTERVAL {
                    p.1 = now;
                    let done = p.0;
                    drop(p);
                    self.publish(epoch, ImportState::Matching { playlist_name: name.clone(), done, total });
                }
            }
        };
        futures::future::join_all((0..MATCH_CONCURRENCY).map(|_| worker())).await;

        let matches: Option<Vec<TrackMatch>> = results.into_inner().into_iter().collect();
        // `None` only when a worker bailed because the run went stale.
        if let Some(matches) = matches {
            self.publish(epoch, ImportState::review(name, playlist.truncated, matches));
        }
    }

    /// Selects `song_id` for track `index` (`None` = skip). A `song` from a
    /// manual search not already among the candidates is prepended with
    /// score 1.0 so the UI can render it.
    pub fn set_selection(&self, index: usize, song_id: Option<String>, song: Option<Song>) {
        let e = self.epoch.lock();
        let next = match &*self.tx.borrow() {
            ImportState::Review { playlist_name, truncated, matches, .. } if index < matches.len() => {
                let mut matches = matches.clone();
                let m = &mut matches[index];
                if let Some(song) = song.filter(|s| !m.candidates.iter().any(|c| c.song.id == s.id)) {
                    m.candidates.insert(0, RankedSong { song, score: 1.0 });
                    m.best_score = 1.0;
                }
                m.selected_id = song_id;
                ImportState::review(playlist_name.clone(), *truncated, matches)
            }
            _ => return,
        };
        self.tx.send_replace(next);
        drop(e);
    }

    /// Free-text library search from the review screen; errors yield `[]`.
    pub async fn manual_search(&self, query: &str) -> Vec<Song> {
        if query.trim().is_empty() {
            return Vec::new();
        }
        self.search.search_songs(query, SEARCH_COUNT).await.unwrap_or_default()
    }

    /// Creates the playlist from every selected id, in playlist order.
    /// `name` overrides the source playlist name.
    pub async fn commit(&self, name: Option<&str>) {
        let (epoch, name, song_ids, total) = {
            let e = self.epoch.lock();
            let ImportState::Review { playlist_name, matches, .. } = &*self.tx.borrow() else {
                return;
            };
            let ids: Vec<String> = matches.iter().filter_map(|m| m.selected_id.clone()).collect();
            let name = name.map_or_else(|| playlist_name.clone(), str::to_owned);
            (*e, name, ids, matches.len())
        };
        if !self.search.is_available() {
            self.publish(epoch, ImportState::error("Lost connection to the Navidrome server. Reconnect and try again."));
            return;
        }
        if song_ids.is_empty() {
            self.publish(epoch, ImportState::error("No songs are selected — nothing to send to Navidrome."));
            return;
        }
        if !self.publish(epoch, ImportState::Creating) {
            return;
        }
        let next = match self.sink.create_playlist(&name, &song_ids).await {
            Ok(()) => ImportState::Done {
                playlist_name: name,
                imported_count: song_ids.len(),
                skipped_count: total - song_ids.len(),
            },
            Err(e) => ImportState::error(format!("Could not create the playlist: {e}")),
        };
        self.publish(epoch, next);
    }
}
