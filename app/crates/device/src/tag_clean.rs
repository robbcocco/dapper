//! Device-wide FLAC tag sanitise + cover shrink (port of
//! `device_tag_sanitize.dart`), with the `.dapper-clean.json` mtime cache so
//! repeat runs only touch changed files.

use std::fs;
use std::io;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::mpsc;

use dapper_domain::DeviceSettings;
use serde::Serialize;

use crate::clean_cache::{CLEAN_CACHE_FILENAME, CleanCache, clean_cache_key, mtime_ms};
use crate::flac::{FlacCleanOptions, FlacCleanOutcome, clean_flac_file};
use crate::scan::{Progress, blocking};

/// Files processed in flight: CPU-bound image work plus USB writes plateau
/// past ~4.
pub const TAG_CLEAN_CONCURRENCY: usize = 4;

/// types.ts `TagSanitizeResult`.
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct TagSanitizeResult {
    pub files_scanned: u64,
    pub files_skipped: u64,
    pub files_modified: u64,
    pub covers_shrunk: u64,
    pub bytes_freed: u64,
    pub errors: Vec<String>,
}

/// Async wrapper over [`sanitize_device_tags_blocking`] (runs it via
/// `block_in_place` on a multi-threaded runtime, inline otherwise).
pub async fn sanitize_device_tags(settings: &DeviceSettings, on_progress: impl FnMut(Progress)) -> TagSanitizeResult {
    blocking(|| sanitize_device_tags_blocking(settings, on_progress))
}

/// Walks the music root, cleans every `.flac` (skipping `._*` sidecars and
/// files unchanged since the cached mtime) on [`TAG_CLEAN_CONCURRENCY`]
/// threads, then rewrites the clean cache. Blocking; progress is reported
/// from the calling thread.
pub fn sanitize_device_tags_blocking(settings: &DeviceSettings, mut on_progress: impl FnMut(Progress)) -> TagSanitizeResult {
    let root_s = settings.resolved_music_root();
    let root = Path::new(&root_s);
    let mut result = TagSanitizeResult::default();
    if !root.is_dir() {
        return result;
    }

    on_progress(Progress::new("Scanning device…", 0, None));
    let mut files = Vec::new();
    walk_flacs(root, &mut files);

    let mut cache = CleanCache::load(root);
    let pending: Vec<PathBuf> = files
        .iter()
        .filter(|f| {
            let Some(key) = clean_cache_key(root, f) else { return true };
            !fs::metadata(f).and_then(|m| mtime_ms(&m)).is_ok_and(|mt| cache.is_clean(&key, mt))
        })
        .cloned()
        .collect();

    result.files_scanned = files.len() as u64;
    let skipped = files.len() - pending.len();
    result.files_skipped = skipped as u64;
    let total = pending.len() as u64;
    let suffix = if skipped > 0 { format!(" ({skipped} cached)") } else { String::new() };
    on_progress(Progress::new(format!("{} files to process{suffix}…", pending.len()), 0, Some(total)));

    let opts = FlacCleanOptions::new(settings.auto_clean_metadata, settings.auto_shrink_cover_art);
    let cursor = AtomicUsize::new(0);
    let (tx, rx) = mpsc::channel::<(usize, io::Result<(FlacCleanOutcome, u64, i64)>)>();
    std::thread::scope(|s| {
        for _ in 0..TAG_CLEAN_CONCURRENCY.min(pending.len()) {
            let tx = tx.clone();
            let (cursor, pending, opts) = (&cursor, &pending, &opts);
            s.spawn(move || {
                loop {
                    let i = cursor.fetch_add(1, Ordering::Relaxed);
                    let Some(path) = pending.get(i) else { break };
                    let _ = tx.send((i, clean_one(path, opts)));
                }
            });
        }
        drop(tx);
        let mut done = 0u64;
        for (i, res) in rx {
            let path = &pending[i];
            match res {
                Ok((outcome, freed, mtime)) => {
                    if outcome.picture_shrunk {
                        result.covers_shrunk += 1;
                        result.bytes_freed += freed;
                    }
                    if outcome.modified() {
                        result.files_modified += 1;
                    }
                    if let Some(key) = clean_cache_key(root, path) {
                        cache.mark_clean(key, mtime);
                    }
                }
                Err(e) => result
                    .errors
                    .push(format!("{}: {e}", path.file_name().unwrap_or_default().to_string_lossy())),
            }
            done += 1;
            if done.is_multiple_of(25) {
                on_progress(Progress::new(format!("Processed {done} / {total}…"), done, Some(total)));
            }
        }
    });

    if let Err(e) = cache.save(root) {
        result.errors.push(format!("{CLEAN_CACHE_FILENAME}: {e}"));
    }
    on_progress(Progress::new("Done.", total, Some(total)));
    result
}

/// Cleans one file; returns the outcome, bytes saved and the new mtime.
fn clean_one(path: &Path, opts: &FlacCleanOptions) -> io::Result<(FlacCleanOutcome, u64, i64)> {
    let before = fs::metadata(path)?.len();
    let outcome = clean_flac_file(path, opts)?;
    let meta = fs::metadata(path)?;
    Ok((outcome, before.saturating_sub(meta.len()), mtime_ms(&meta)?))
}

/// Recursive walk (links not followed) collecting `.flac` files, skipping
/// AppleDouble `._*` sidecars.
fn walk_flacs(dir: &Path, out: &mut Vec<PathBuf>) {
    let Ok(rd) = fs::read_dir(dir) else { return };
    let mut entries: Vec<_> = rd.filter_map(|e| e.ok()).collect();
    entries.sort_by_key(|e| e.file_name());
    for e in entries {
        let Ok(ft) = e.file_type() else { continue };
        let path = e.path();
        if ft.is_dir() {
            walk_flacs(&path, out);
        } else if ft.is_file() {
            let name = e.file_name();
            let name = name.to_string_lossy();
            if !name.starts_with("._") && path.extension().is_some_and(|x| x.eq_ignore_ascii_case("flac")) {
                out.push(path);
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn caches_and_skips() {
        let tmp = tempfile::tempdir().unwrap();
        let d = tmp.path().join("A").join("B");
        fs::create_dir_all(&d).unwrap();
        // Not parseable FLAC: clean_flac_file is a no-op success.
        fs::write(d.join("01 x.flac"), b"not flac").unwrap();
        fs::write(d.join("02 y.FLAC"), b"not flac").unwrap();
        fs::write(d.join("._01 x.flac"), b"sidecar").unwrap();
        fs::write(d.join("03 z.mp3"), b"mp3").unwrap();
        let settings = DeviceSettings::new(tmp.path().to_string_lossy());

        let mut phases = Vec::new();
        let r = sanitize_device_tags_blocking(&settings, |p| phases.push(p.phase));
        assert_eq!((r.files_scanned, r.files_skipped, r.files_modified), (2, 0, 0));
        assert!(r.errors.is_empty(), "{:?}", r.errors);
        assert_eq!(phases.last().map(String::as_str), Some("Done."));
        let cache = CleanCache::load(tmp.path());
        assert_eq!(cache.entries.len(), 2);

        let r2 = sanitize_device_tags_blocking(&settings, |_| {});
        assert_eq!((r2.files_scanned, r2.files_skipped), (2, 2));
    }

    #[test]
    fn missing_root() {
        let settings = DeviceSettings::new("/definitely/not/here");
        assert_eq!(sanitize_device_tags_blocking(&settings, |_| {}), TagSanitizeResult::default());
    }
}
