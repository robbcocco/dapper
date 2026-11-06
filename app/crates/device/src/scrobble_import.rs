//! Offline scrobble import (port of `scrobble_importer.dart`): finds a
//! Rockbox-style `.scrobbler.log`, resolves rows against on-device manifests,
//! submits them, then rewrites the log keeping unsubmitted rows.

use std::collections::HashMap;
use std::fs;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicUsize, Ordering};

use dapper_domain::{DeviceSettings, ScrobbleSink};
use parking_lot::Mutex;
use serde::Serialize;

use crate::manifest::read_manifest;
use crate::scan::blocking;
use crate::scrobbler_log::{ScrobblerLogEntry, find_scrobbler_log, parse_scrobbler_log, read_scrobbler_log, rewrite_scrobbler_log};

/// Max concurrent scrobble submissions.
pub const SCROBBLE_SUBMIT_CONCURRENCY: usize = 5;

/// types.ts `ScrobbleImportResult`.
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ScrobbleImportResult {
    pub device_path: String,
    /// Rows parsed from the log.
    pub parsed: u64,
    /// Parsed rows resolved to a song on the device.
    pub matched: u64,
    /// Rows submitted without error.
    pub submitted: u64,
    /// Parsed rows that matched nothing.
    pub unmatched: u64,
    /// Matched rows whose submission failed.
    pub errors: u64,
}

impl ScrobbleImportResult {
    pub fn has_work(&self) -> bool {
        self.parsed > 0
    }
}

/// One import pass for `device_path`: locate + parse the log, index every
/// manifest under the music root (three levels deep), resolve each row by
/// (artist, album, title) → (artist, title) → title, submit matches through
/// `sink` with the log timestamp (ms) on up to [`SCROBBLE_SUBMIT_CONCURRENCY`]
/// in flight, then atomically rewrite the log keeping unmatched and failed
/// rows. Filesystem steps run via `block_in_place` on a multi-threaded
/// runtime (inline otherwise). Never fails: unreadable logs yield an empty
/// result.
pub async fn import_scrobbles(device_path: &str, settings: &DeviceSettings, sink: &dyn ScrobbleSink) -> ScrobbleImportResult {
    let mut result = ScrobbleImportResult { device_path: device_path.to_owned(), ..Default::default() };
    let loaded = blocking(|| {
        let log = find_scrobbler_log(Path::new(device_path))?;
        match read_scrobbler_log(&log) {
            Ok(c) => Some((log, c)),
            Err(e) => {
                tracing::warn!("import_scrobbles: could not read {} — {e}", log.display());
                None
            }
        }
    });
    let Some((log, contents)) = loaded else { return result };

    let entries = parse_scrobbler_log(&contents);
    if entries.is_empty() {
        // Header-only / all-skipped logs would otherwise be rescanned on every plug.
        rewrite(&log, &contents, &[]);
        return result;
    }

    let index = blocking(|| build_index(Path::new(&settings.resolved_music_root())));
    let mut keep = Vec::new();
    let mut matched: Vec<(&ScrobblerLogEntry, String)> = Vec::new();
    for e in &entries {
        match resolve(e, &index) {
            Some(id) => matched.push((e, id)),
            None => keep.push(e.raw.clone()),
        }
    }

    let cursor = AtomicUsize::new(0);
    let failed = Mutex::new(Vec::new());
    let submitted = AtomicUsize::new(0);
    let worker = || async {
        while let Some((entry, id)) = matched.get(cursor.fetch_add(1, Ordering::Relaxed)) {
            match sink.scrobble(id, true, Some(entry.timestamp * 1000)).await {
                Ok(()) => {
                    submitted.fetch_add(1, Ordering::Relaxed);
                }
                Err(e) => {
                    tracing::warn!("import_scrobbles: scrobble(\"{id}\") failed at {} — {e}", entry.timestamp);
                    failed.lock().push(entry.raw.clone());
                }
            }
        }
    };
    const _: () = assert!(SCROBBLE_SUBMIT_CONCURRENCY == 5);
    tokio::join!(worker(), worker(), worker(), worker(), worker());

    let failed = failed.into_inner();
    result.errors = failed.len() as u64;
    keep.extend(failed);
    rewrite(&log, &contents, &keep);

    result.parsed = entries.len() as u64;
    result.matched = matched.len() as u64;
    result.submitted = submitted.into_inner() as u64;
    result.unmatched = result.parsed - result.matched;
    result
}

fn rewrite(log: &Path, contents: &str, keep: &[String]) {
    if let Err(e) = blocking(|| rewrite_scrobbler_log(log, contents, keep)) {
        tracing::warn!("import_scrobbles: rewrite of {} failed — {e}", log.display());
    }
}

fn subdirs(dir: &Path) -> Vec<PathBuf> {
    fs::read_dir(dir)
        .map(|rd| rd.filter_map(|e| e.ok()).filter(|e| e.file_type().is_ok_and(|t| t.is_dir())).map(|e| e.path()).collect())
        .unwrap_or_default()
}

/// Normalised key → song id from every manifest up to three levels below
/// `root`, plus a title-only fallback (first indexed wins).
fn build_index(root: &Path) -> HashMap<String, String> {
    let mut index = HashMap::new();
    let mut consume = |folder: &Path| {
        let Some(m) = read_manifest(folder) else { return };
        for s in &m.songs {
            index.insert(
                key(s.artist.as_deref().unwrap_or(""), s.album.as_deref().unwrap_or(""), &s.title),
                s.id.clone(),
            );
            index.entry(key("", "", &s.title)).or_insert_with(|| s.id.clone());
        }
    };
    for l1 in subdirs(root) {
        consume(&l1);
        for l2 in subdirs(&l1) {
            consume(&l2);
            for l3 in subdirs(&l2) {
                consume(&l3);
            }
        }
    }
    index
}

fn key(artist: &str, album: &str, title: &str) -> String {
    format!("{}|{}|{}", norm(artist), norm(album), norm(title))
}

/// Lowercase, keep ASCII alphanumerics and every non-ASCII char.
fn norm(s: &str) -> String {
    s.to_lowercase().chars().filter(|c| c.is_ascii_digit() || c.is_ascii_lowercase() || !c.is_ascii()).collect()
}

fn resolve(e: &ScrobblerLogEntry, index: &HashMap<String, String>) -> Option<String> {
    index
        .get(&key(&e.artist, &e.album, &e.title))
        .or_else(|| index.get(&key(&e.artist, "", &e.title)))
        .or_else(|| index.get(&key("", "", &e.title)))
        .cloned()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::manifest::{AlbumManifest, ManifestSong, write_manifest};
    use crate::test_support::{FakeSink, song};

    const HEADER: &str = "#AUDIOSCROBBLER/1.1\n#TZ/UTC\n#CLIENT/Rockbox\n";

    #[test]
    fn normalises() {
        assert_eq!(norm("  Don’t Stop (feat. X) "), "don’tstopfeatx");
        assert_eq!(key("A", "", "B"), "a||b");
    }

    #[tokio::test]
    async fn imports_and_keeps_unsubmitted() {
        let t = tempfile::tempdir().unwrap();
        let music = t.path().join("Music");
        let d = music.join("The Band").join("Record");
        fs::create_dir_all(&d).unwrap();
        let mut s1 = song("s1", "Song One", "The Band", "Record");
        s1.album_artist = Some("The Band".into());
        let s2 = song("s2", "Song Two", "The Band", "Record");
        let s3 = song("s3", "Bad One", "The Band", "Record");
        write_manifest(
            &d,
            AlbumManifest { songs: [&s1, &s2, &s3].map(|s| ManifestSong::for_song(s, None)).to_vec(), expected_song_count: None },
        )
        .unwrap();
        let rows = [
            "The Band\tRecord\tSong One\t1\t200\tL\t1700000000\t",
            "the band\t\tsong two\t2\t200\tL\t1700000100\t",
            "Other\tX\tSong Two\t2\t200\tL\t1700000200\t",
            "Nobody\tNothing\tUnknown\t1\t200\tL\t1700000300\t",
            "The Band\tRecord\tBad One\t3\t200\tL\t1700000400\t",
        ];
        let log = t.path().join(".scrobbler.log");
        fs::write(&log, format!("{HEADER}{}\n", rows.join("\n"))).unwrap();

        let mut settings = DeviceSettings::new(t.path().to_string_lossy());
        settings.music_root_folder = "Music".into();
        let sink = FakeSink { fail_ids: ["s3".to_string()].into(), ..Default::default() };
        let r = import_scrobbles(&t.path().to_string_lossy(), &settings, &sink).await;
        assert_eq!((r.parsed, r.matched, r.submitted, r.unmatched, r.errors), (5, 4, 3, 1, 1));
        let mut calls = sink.calls.lock().clone();
        calls.sort();
        assert_eq!(
            calls,
            [
                ("s1".to_string(), true, Some(1_700_000_000_000)),
                ("s2".into(), true, Some(1_700_000_100_000)),
                ("s2".into(), true, Some(1_700_000_200_000)),
                ("s3".into(), true, Some(1_700_000_400_000)),
            ]
        );
        assert_eq!(fs::read_to_string(&log).unwrap(), format!("{HEADER}{}\n{}\n", rows[3], rows[4]));
        let j = serde_json::to_value(&r).unwrap();
        assert_eq!(j["devicePath"], t.path().to_string_lossy().as_ref());
    }

    #[tokio::test]
    async fn no_log_and_header_only() {
        let t = tempfile::tempdir().unwrap();
        let settings = DeviceSettings::new(t.path().to_string_lossy());
        let sink = FakeSink::default();
        let r = import_scrobbles(&t.path().to_string_lossy(), &settings, &sink).await;
        assert!(!r.has_work());
        let log = t.path().join("scrobbler.log");
        fs::write(&log, format!("{HEADER}garbage\n")).unwrap();
        let r = import_scrobbles(&t.path().to_string_lossy(), &settings, &sink).await;
        assert_eq!(r.parsed, 0);
        assert_eq!(fs::read_to_string(&log).unwrap(), HEADER);
    }
}
