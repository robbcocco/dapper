//! Scores library songs against one external playlist track.
//! Port of `lib/application/spotify_import/song_matcher.dart`.

use std::collections::HashSet;
use std::sync::{Arc, LazyLock};

use dapper_domain::{Song, SpotifyTrack};
use regex::Regex;
use serde::Serialize;

use crate::ports::SongSearch;

/// Above this combined score the best candidate is auto-picked.
pub const AUTO_MATCH_THRESHOLD: f64 = 0.78;
/// Candidates kept per track.
pub const MAX_CANDIDATES: usize = 8;
/// Songs requested per library search (Subsonic `songCount`).
pub const SEARCH_COUNT: usize = 50;

static ARTIST_SPLIT: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"[,&]").unwrap());
static PARENS: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"\([^)]*\)").unwrap());
static BRACKETS: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"\[[^\]]*\]").unwrap());
static PUNCT: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"[^\p{L}\p{N}\s]").unwrap());
static SPACES: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"\s+").unwrap());

#[derive(Debug, Clone, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct RankedSong {
    pub song: Song,
    pub score: f64,
}

/// Result of matching one external track against the library.
#[derive(Debug, Clone, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct TrackMatch {
    pub source: SpotifyTrack,
    /// Up to [`MAX_CANDIDATES`], descending score.
    pub candidates: Vec<RankedSong>,
    /// Score of the first candidate, or 0.
    pub best_score: f64,
    /// Auto-picked or user-picked song id; `None` = skip.
    pub selected_id: Option<String>,
}

#[derive(Clone)]
pub struct SongMatcher {
    search: Arc<dyn SongSearch>,
}

impl SongMatcher {
    pub fn new(search: Arc<dyn SongSearch>) -> Self {
        Self { search }
    }

    /// Searches the library for `track`; search errors yield an empty match so
    /// the track is flagged for manual resolution instead of aborting.
    pub async fn match_track(&self, track: &SpotifyTrack) -> TrackMatch {
        let hits = self
            .search
            .search_songs(&build_query(track), SEARCH_COUNT)
            .await
            .unwrap_or_default();
        rank(track, hits)
    }
}

/// Ranks `hits` for `track` (pure part of [`SongMatcher::match_track`]).
pub fn rank(track: &SpotifyTrack, hits: Vec<Song>) -> TrackMatch {
    let mut ranked: Vec<RankedSong> = hits
        .into_iter()
        .filter_map(|song| {
            let score = score(track, &song);
            (score > 0.0).then_some(RankedSong { song, score })
        })
        .collect();
    ranked.sort_by(|a, b| b.score.total_cmp(&a.score));
    let best_score = ranked.first().map_or(0.0, |r| r.score);
    let selected_id = (best_score >= AUTO_MATCH_THRESHOLD).then(|| ranked[0].song.id.clone());
    ranked.truncate(MAX_CANDIDATES);
    TrackMatch { source: track.clone(), candidates: ranked, best_score, selected_id }
}

/// Title plus primary artist (text before the first `,` or `&`).
pub fn build_query(t: &SpotifyTrack) -> String {
    let primary = ARTIST_SPLIT.split(&t.artist).next().unwrap_or("").trim();
    format!("{} {}", t.title, primary).trim().to_owned()
}

pub fn score(t: &SpotifyTrack, s: &Song) -> f64 {
    let artist = s.artist.as_deref().or(s.album_artist.as_deref()).unwrap_or("");
    let mut score = similarity(&t.title, &s.title) * 0.65 + similarity(&t.artist, artist) * 0.35;
    if let (Some(ms), Some(dur)) = (t.duration_ms, s.duration) {
        let delta = (ms as f64 / 1000.0 - dur as f64).abs();
        if delta <= 3.0 {
            score += 0.08;
        } else if delta <= 8.0 {
            score += 0.04;
        } else if delta > 30.0 {
            score -= 0.15;
        }
    }
    score.clamp(0.0, 1.0)
}

/// Token-Jaccard on normalised strings, with an exact-match bonus.
pub fn similarity(a: &str, b: &str) -> f64 {
    let (na, nb) = (normalize(a), normalize(b));
    let ta: HashSet<&str> = na.split(' ').filter(|t| !t.is_empty()).collect();
    let tb: HashSet<&str> = nb.split(' ').filter(|t| !t.is_empty()).collect();
    if ta.is_empty() || tb.is_empty() {
        return 0.0;
    }
    let inter = ta.intersection(&tb).count();
    let union = ta.union(&tb).count();
    let jaccard = inter as f64 / union as f64;
    if na == nb { (jaccard + 1.0) / 2.0 + 0.1 } else { jaccard }
}

pub fn normalize(s: &str) -> String {
    // Dart's toLowerCase is a simple 1:1 mapping: 'İ' → 'i' (Rust expands it to
    // "i\u{307}") and no context-sensitive final sigma.
    let out: String = s.chars().filter_map(|c| c.to_lowercase().next()).collect();
    let out = PARENS.replace_all(&out, " ");
    let out = BRACKETS.replace_all(&out, " ");
    let out = PUNCT.replace_all(&out, " ");
    SPACES.replace_all(&out, " ").trim().to_owned()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn track(title: &str, artist: &str, ms: Option<i64>) -> SpotifyTrack {
        SpotifyTrack { title: title.into(), artist: artist.into(), album: None, duration_ms: ms }
    }
    fn song(id: &str, title: &str, artist: Option<&str>, dur: Option<i64>) -> Song {
        Song { id: id.into(), title: title.into(), artist: artist.map(Into::into), duration: dur, ..Default::default() }
    }

    #[test]
    fn normalize_strips_parens_and_punct() {
        assert_eq!(normalize("İSTANBUL ΟΔΟΣ"), "istanbul οδοσ");
        assert_eq!(normalize("Song Title (feat. X) - Remastered [2011]"), "song title remastered");
        assert_eq!(normalize("Beyoncé!"), "beyoncé");
        assert_eq!(normalize("  ..  "), "");
    }

    #[test]
    fn query_uses_primary_artist() {
        assert_eq!(build_query(&track("Hey", "A, B & C", None)), "Hey A");
        assert_eq!(build_query(&track("Hey", "X & Y", None)), "Hey X");
        assert_eq!(build_query(&track("Hey", "", None)), "Hey");
    }

    #[test]
    fn similarity_exact_bonus() {
        assert!((similarity("Song", "song!") - 1.1).abs() < 1e-12);
        assert!((similarity("a b", "a c") - 1.0 / 3.0).abs() < 1e-12);
        assert_eq!(similarity("", "x"), 0.0);
    }

    #[test]
    fn score_duration_and_clamp() {
        let t = track("Song", "Artist", Some(200_000));
        assert_eq!(score(&t, &song("1", "Song", Some("Artist"), Some(201))), 1.0);
        let far = score(&t, &song("1", "Song x", Some("Artist"), Some(300)));
        assert!((far - (0.5 * 0.65 + 1.1 * 0.35 - 0.15)).abs() < 1e-12);
        // album artist fallback
        let s = Song { album_artist: Some("Artist".into()), ..song("1", "Other", None, None) };
        assert!((score(&t, &s) - 1.1 * 0.35).abs() < 1e-12);
    }

    #[test]
    fn rank_drops_zero_sorts_truncates_and_autopicks() {
        let t = track("Song", "Artist", None);
        let mut hits = vec![song("z", "Nope", Some("Nobody"), None)];
        for i in 0..10 {
            hits.push(song(&i.to_string(), if i == 5 { "Song" } else { "Song extra" }, Some("Artist"), None));
        }
        let m = rank(&t, hits);
        assert_eq!(m.candidates.len(), MAX_CANDIDATES);
        assert_eq!(m.candidates[0].song.id, "5");
        assert_eq!(m.selected_id.as_deref(), Some("5"));
        assert!(m.candidates.iter().all(|c| c.song.id != "z"));
        let weak = rank(&t, vec![song("w", "Song extra", Some("Other"), None)]);
        assert_eq!(weak.selected_id, None);
        assert!((weak.best_score - 0.325).abs() < 1e-12);
    }
}
