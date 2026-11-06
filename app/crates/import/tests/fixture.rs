//! Golden equality against Dart's SongMatcher (`app/fixtures/song_matcher.json`).

use std::path::Path;

use dapper_domain::{Song, SpotifyTrack};
use dapper_import::matcher::{build_query, rank};
use serde_json::Value;

#[test]
fn song_matcher_fixture() {
    let path = Path::new(env!("CARGO_MANIFEST_DIR")).join("../../fixtures/song_matcher.json");
    let Ok(raw) = std::fs::read_to_string(&path) else {
        eprintln!("skipping: {} not present", path.display());
        return;
    };
    let doc: Value = serde_json::from_str(&raw).unwrap();
    let cases = doc["cases"].as_array().unwrap();
    assert!(!cases.is_empty());
    for (n, case) in cases.iter().enumerate() {
        let input = &case["input"];
        let out = &case["output"];
        let track: SpotifyTrack = serde_json::from_value(input["track"].clone()).unwrap();
        let hits: Vec<Song> = if input["searchThrows"].as_bool().unwrap_or(false) {
            Vec::new()
        } else {
            serde_json::from_value(input["searchResults"].clone()).unwrap()
        };
        assert_eq!(build_query(&track), out["query"].as_str().unwrap(), "case {n} query");
        let m = rank(&track, hits);
        let want = out["candidates"].as_array().unwrap();
        let got: Vec<(&str, f64)> = m.candidates.iter().map(|c| (c.song.id.as_str(), c.score)).collect();
        assert_eq!(got.len(), want.len(), "case {n} candidate count: {got:?}");
        for (g, w) in got.iter().zip(want) {
            assert_eq!(g.0, w["id"].as_str().unwrap(), "case {n} order: {got:?}");
            assert!((g.1 - w["score"].as_f64().unwrap()).abs() < 1e-9, "case {n} score {g:?} vs {w}");
        }
        assert!((m.best_score - out["bestScore"].as_f64().unwrap()).abs() < 1e-9, "case {n} best");
        assert_eq!(m.selected_id.as_deref(), out["selectedId"].as_str(), "case {n} selected");
    }
    eprintln!("song_matcher fixture: {} cases matched", cases.len());
}
