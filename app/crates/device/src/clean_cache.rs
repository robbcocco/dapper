//! `.dapper-clean.json` at a device's music root: relative path → file mtime
//! (ms since epoch) when it was last tag-cleaned / cover-shrunk, so repeat
//! runs skip files that haven't changed since.

use std::fs;
use std::io;
use std::path::Path;
use std::time::UNIX_EPOCH;

use indexmap::IndexMap;
use serde_json::Value;

use crate::atomic_file::write_atomic;

pub const CLEAN_CACHE_FILENAME: &str = ".dapper-clean.json";

/// Insertion-ordered like the Dart map so rewrites keep the file's order.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct CleanCache {
    pub entries: IndexMap<String, i64>,
}

impl CleanCache {
    /// Loads the cache from `music_root`. A missing or malformed file is an
    /// empty cache; non-integer values are ignored. A leading BOM is dropped
    /// as Dart's UTF-8 decoder does.
    pub fn load(music_root: &Path) -> Self {
        let entries = fs::read(music_root.join(CLEAN_CACHE_FILENAME))
            .ok()
            .and_then(|b| {
                let b = b.strip_prefix(b"\xEF\xBB\xBF").unwrap_or(&b);
                serde_json::from_slice::<IndexMap<String, Value>>(b).ok()
            })
            .map(|m| m.into_iter().filter_map(|(k, v)| v.as_i64().map(|v| (k, v))).collect())
            .unwrap_or_default();
        Self { entries }
    }

    /// Compact JSON, as Dart's `jsonEncode`.
    pub fn to_json_string(&self) -> String {
        serde_json::to_string(&self.entries).expect("clean cache serialisation is infallible")
    }

    /// Atomic (temp file + rename) so an unplug mid-save keeps the old cache.
    pub fn save(&self, music_root: &Path) -> io::Result<()> {
        write_atomic(&music_root.join(CLEAN_CACHE_FILENAME), self.to_json_string().as_bytes())
    }

    /// True when `rel_path` was cleaned at or after `mtime_ms`.
    pub fn is_clean(&self, rel_path: &str, mtime_ms: i64) -> bool {
        self.entries.get(rel_path).is_some_and(|&cached| mtime_ms <= cached)
    }

    pub fn mark_clean(&mut self, rel_path: String, mtime_ms: i64) {
        self.entries.insert(rel_path, mtime_ms);
    }
}

/// Key for `file` under `music_root` (platform separators, like Dart's
/// `p.relative`); `None` if `file` is outside the root.
pub fn clean_cache_key(music_root: &Path, file: &Path) -> Option<String> {
    file.strip_prefix(music_root).ok().map(|p| p.to_string_lossy().into_owned())
}

/// Modification time in whole milliseconds since the epoch.
pub fn mtime_ms(meta: &fs::Metadata) -> io::Result<i64> {
    let t = meta.modified()?;
    Ok(match t.duration_since(UNIX_EPOCH) {
        Ok(d) => d.as_millis() as i64,
        Err(e) => -(e.duration().as_micros().div_ceil(1000) as i64),
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn load_ignores_malformed_and_non_int_values() {
        let dir = tempfile::tempdir().unwrap();
        assert!(CleanCache::load(dir.path()).entries.is_empty());
        fs::write(dir.path().join(CLEAN_CACHE_FILENAME), "{not json").unwrap();
        assert!(CleanCache::load(dir.path()).entries.is_empty());
        fs::write(dir.path().join(CLEAN_CACHE_FILENAME), "[1,2]").unwrap();
        assert!(CleanCache::load(dir.path()).entries.is_empty());
        fs::write(dir.path().join(CLEAN_CACHE_FILENAME), r#"{"a.flac":5,"b.flac":"x","c.flac":1.5,"d.flac":7}"#).unwrap();
        let c = CleanCache::load(dir.path());
        assert_eq!(c.entries.iter().map(|(k, v)| (k.as_str(), *v)).collect::<Vec<_>>(), [("a.flac", 5), ("d.flac", 7)]);
    }

    #[test]
    fn save_round_trips_in_insertion_order() {
        let dir = tempfile::tempdir().unwrap();
        let mut c = CleanCache::default();
        c.mark_clean("z/b.flac".into(), 20);
        c.mark_clean("a/a.flac".into(), 10);
        c.mark_clean("z/b.flac".into(), 30);
        c.save(dir.path()).unwrap();
        assert!(!dir.path().join(".dapper-clean.json.tmp").exists());
        assert_eq!(fs::read_to_string(dir.path().join(CLEAN_CACHE_FILENAME)).unwrap(), r#"{"z/b.flac":30,"a/a.flac":10}"#);
        assert_eq!(CleanCache::load(dir.path()), c);
        assert!(c.is_clean("a/a.flac", 10));
        assert!(!c.is_clean("a/a.flac", 11));
        assert!(!c.is_clean("missing", 0));
    }

    #[test]
    fn key_and_mtime() {
        let dir = tempfile::tempdir().unwrap();
        let f = dir.path().join("A").join("x.flac");
        assert_eq!(clean_cache_key(dir.path(), &f).unwrap(), Path::new("A").join("x.flac").to_string_lossy());
        assert_eq!(clean_cache_key(Path::new("/elsewhere"), &f), None);
        fs::write(dir.path().join("f"), "x").unwrap();
        let ms = mtime_ms(&fs::metadata(dir.path().join("f")).unwrap()).unwrap();
        let now = std::time::SystemTime::now().duration_since(UNIX_EPOCH).unwrap().as_millis() as i64;
        assert!((now - ms).abs() < 60_000);
    }
}
