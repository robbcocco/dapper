//! AudioScrobbler 1.1 logs written by DAPs that scrobble offline (Rockbox,
//! some HiBy / FiiO / Cowon firmwares):
//!
//! ```text
//! #AUDIOSCROBBLER/1.1
//! #TZ/UTC
//! #CLIENT/<name>
//! artist\talbum\ttitle\ttrackNumber\tlengthSeconds\trating\ttimestamp\tmusicBrainzId
//! ```
//!
//! Rating `L` is a full listen, `S` a skip. Timestamps are unix seconds and
//! treated as UTC: the log carries no offset information.

use std::fs;
use std::io;
use std::path::{Path, PathBuf};

use crate::atomic_file::write_atomic;

/// Recognised log names, matched case-insensitively. Rockbox uses
/// `.scrobbler.log`; other firmwares drop the dot or use a `lastfm` prefix.
const CANDIDATE_NAMES: [&str; 4] = [".scrobbler.log", "scrobbler.log", "lastfm.log", "lastfm-scrobbler.log"];

// DateTime.fromMillisecondsSinceEpoch's range (±8.64e15 ms).
const MAX_TIMESTAMP_SECS: i64 = 8_640_000_000_000;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ScrobblerLogEntry {
    pub artist: String,
    pub album: String,
    pub title: String,
    pub track_number: Option<i64>,
    pub length_seconds: Option<i64>,
    /// Unix seconds, UTC.
    pub timestamp: i64,
    pub music_brainz_id: Option<String>,
    /// The CR-stripped source line, so a rewrite can keep rows that were not
    /// submitted instead of losing them.
    pub raw: String,
}

fn matches_candidate(path: &Path) -> bool {
    path.file_name().is_some_and(|n| {
        let n = n.to_string_lossy().to_lowercase();
        CANDIDATE_NAMES.contains(&n.as_str())
    })
}

/// First log file at `device_root` or one directory below it (listing
/// order). Every known firmware writes it there, so deeper trees are not
/// walked. Symlinks are not followed. Blocking.
pub fn find_scrobbler_log(device_root: &Path) -> Option<PathBuf> {
    let entries = match fs::read_dir(device_root) {
        Ok(e) => e,
        Err(e) => {
            if device_root.exists() {
                tracing::warn!("find_scrobbler_log: scan of {} failed: {e}", device_root.display());
            }
            return None;
        }
    };
    for entry in entries {
        let Ok(entry) = entry else { break };
        let Ok(ty) = entry.file_type() else { continue };
        let path = entry.path();
        if ty.is_file() && matches_candidate(&path) {
            return Some(path);
        }
        if ty.is_dir() {
            // Unreadable inner directories are skipped.
            let Ok(inner) = fs::read_dir(&path) else { continue };
            for inner in inner.flatten() {
                if inner.file_type().is_ok_and(|t| t.is_file()) && matches_candidate(&inner.path()) {
                    return Some(inner.path());
                }
            }
        }
    }
    None
}

/// Reads the log as Dart's `readAsString` does: strict UTF-8 (malformed
/// bytes are an `InvalidData` error) with a leading BOM dropped, so the
/// header survives a rewrite. Blocking.
pub fn read_scrobbler_log(path: &Path) -> io::Result<String> {
    let text = String::from_utf8(fs::read(path)?).map_err(|e| io::Error::new(io::ErrorKind::InvalidData, e))?;
    Ok(match text.strip_prefix('\u{FEFF}') {
        Some(rest) => rest.to_owned(),
        None => text,
    })
}

fn is_dart_whitespace(c: char) -> bool {
    c.is_whitespace() || c == '\u{FEFF}'
}

fn dart_trim(s: &str) -> &str {
    s.trim_matches(is_dart_whitespace)
}

/// Dart `int.tryParse`: optional sign, decimal or `0x` hex, surrounding
/// whitespace allowed; out-of-range is `None`.
fn dart_int_try_parse(s: &str) -> Option<i64> {
    let s = dart_trim(s);
    let (neg, digits) = match s.as_bytes().first()? {
        b'-' => (true, &s[1..]),
        b'+' => (false, &s[1..]),
        _ => (false, s),
    };
    let (radix, digits) = match digits.get(..2) {
        Some("0x" | "0X") => (16, &digits[2..]),
        _ => (10, digits),
    };
    if digits.is_empty() || !digits.chars().all(|c| c.is_digit(radix)) {
        return None;
    }
    let mag = i128::from_str_radix(digits, radix).ok()?;
    i64::try_from(if neg { -mag } else { mag }).ok()
}

/// Parses log `contents`, skipping headers (`#...`), non-`L` rows and rows
/// that are malformed (DAPs truncate lines when the battery dies mid-write).
pub fn parse_scrobbler_log(contents: &str) -> Vec<ScrobblerLogEntry> {
    let mut out = Vec::new();
    for raw in contents.split('\n') {
        let line = raw.replace('\r', "");
        if line.is_empty() || line.starts_with('#') {
            continue;
        }
        let parts: Vec<&str> = line.split('\t').collect();
        // Spec says 8 fields; some firmwares omit the MusicBrainz column.
        if parts.len() < 7 {
            continue;
        }
        if dart_trim(parts[5]).to_uppercase() != "L" {
            continue;
        }
        let Some(ts) = dart_int_try_parse(parts[6]).filter(|&t| t > 0 && t <= MAX_TIMESTAMP_SECS) else {
            continue;
        };
        let artist = dart_trim(parts[0]);
        let title = dart_trim(parts[2]);
        if artist.is_empty() || title.is_empty() {
            continue;
        }
        let mbid = parts.get(7).map(|s| dart_trim(s)).filter(|s| !s.is_empty());
        out.push(ScrobblerLogEntry {
            artist: artist.to_owned(),
            album: dart_trim(parts[1]).to_owned(),
            title: title.to_owned(),
            track_number: dart_int_try_parse(parts[3]),
            length_seconds: dart_int_try_parse(parts[4]),
            timestamp: ts,
            music_brainz_id: mbid.map(str::to_owned),
            raw: line.clone(),
        });
    }
    out
}

/// The text [`rewrite_scrobbler_log`] writes: the leading `#` header lines of
/// `original` (some firmwares only append when the header is present) then
/// `keep_raws`, each newline-terminated.
pub fn rewritten_scrobbler_log(original: &str, keep_raws: &[String]) -> String {
    let mut buf = String::new();
    for raw in original.split('\n') {
        let line = raw.replace('\r', "");
        if !line.starts_with('#') {
            break;
        }
        buf.push_str(&line);
        buf.push('\n');
    }
    for r in keep_raws {
        buf.push_str(r);
        buf.push('\n');
    }
    buf
}

/// Replaces the log with its header plus `keep_raws` (rows not submitted:
/// unmatched plays and failed submissions). Atomic: written to a sibling
/// temp file, then renamed over the log, so an unplug mid-write can't lose
/// rows. Blocking.
pub fn rewrite_scrobbler_log(path: &Path, original: &str, keep_raws: &[String]) -> io::Result<()> {
    write_atomic(path, rewritten_scrobbler_log(original, keep_raws).as_bytes())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn skips_headers_and_parses_l_rows() {
        let log = "#AUDIOSCROBBLER/1.1\n#TZ/UTC\n#CLIENT/Rockbox\n\
                   Pink Floyd\tDark Side of the Moon\tMoney\t6\t383\tL\t1700000000\t\n\
                   Pink Floyd\tDark Side of the Moon\tTime\t4\t421\tL\t1700000500\tmbid-1\n";
        let e = parse_scrobbler_log(log);
        assert_eq!(e.len(), 2);
        assert_eq!(e[0].artist, "Pink Floyd");
        assert_eq!(e[0].title, "Money");
        assert_eq!(e[0].track_number, Some(6));
        assert_eq!(e[0].length_seconds, Some(383));
        assert_eq!(e[0].timestamp, 1_700_000_000);
        assert_eq!(e[0].music_brainz_id, None);
        assert_eq!(e[1].music_brainz_id.as_deref(), Some("mbid-1"));
    }

    #[test]
    fn drops_skipped_rows() {
        let log = "Artist\tAlbum\tListened\t1\t200\tL\t1700000000\t\nArtist\tAlbum\tSkipped\t2\t200\tS\t1700000100\t\n";
        let e = parse_scrobbler_log(log);
        assert_eq!(e.len(), 1);
        assert_eq!(e[0].title, "Listened");
    }

    #[test]
    fn ignores_short_rows() {
        assert!(parse_scrobbler_log("Artist\tAlbum\tTitle\t1\t200\tL\n").is_empty());
    }

    #[test]
    fn ignores_bad_timestamps() {
        let log = "Artist\tAlbum\tTitle\t1\t200\tL\tnope\t\nArtist\tAlbum\tTitle\t1\t200\tL\t0\t\n";
        assert!(parse_scrobbler_log(log).is_empty());
    }

    #[test]
    fn survives_crlf() {
        let e = parse_scrobbler_log("#AUDIOSCROBBLER/1.1\r\nArtist\tAlbum\tTitle\t1\t200\tL\t1700000000\t\r\n");
        assert_eq!(e.len(), 1);
        assert_eq!(e[0].title, "Title");
        assert_eq!(e[0].raw, "Artist\tAlbum\tTitle\t1\t200\tL\t1700000000\t");
    }

    #[test]
    fn accepts_seven_columns() {
        assert_eq!(parse_scrobbler_log("Artist\tAlbum\tTitle\t1\t200\tL\t1700000000\n").len(), 1);
    }

    #[test]
    fn dart_int_parsing() {
        assert_eq!(dart_int_try_parse(" 42 "), Some(42));
        assert_eq!(dart_int_try_parse("+7"), Some(7));
        assert_eq!(dart_int_try_parse("-0x10"), Some(-16));
        assert_eq!(dart_int_try_parse("1.5"), None);
        assert_eq!(dart_int_try_parse(""), None);
        assert_eq!(dart_int_try_parse("99999999999999999999"), None);
    }

    #[test]
    fn find_returns_none_without_candidates() {
        let tmp = tempfile::tempdir().unwrap();
        assert_eq!(find_scrobbler_log(tmp.path()), None);
        assert_eq!(find_scrobbler_log(&tmp.path().join("missing")), None);
    }

    #[test]
    fn find_at_root() {
        let tmp = tempfile::tempdir().unwrap();
        fs::write(tmp.path().join(".scrobbler.log"), "#AUDIOSCROBBLER/1.1\n").unwrap();
        let found = find_scrobbler_log(tmp.path()).unwrap();
        assert_eq!(found.file_name().unwrap(), ".scrobbler.log");
    }

    #[test]
    fn find_one_level_deep() {
        let tmp = tempfile::tempdir().unwrap();
        fs::create_dir(tmp.path().join("Music")).unwrap();
        fs::write(tmp.path().join("Music/scrobbler.log"), "#AUDIOSCROBBLER/1.1\n").unwrap();
        let found = find_scrobbler_log(tmp.path()).unwrap();
        assert_eq!(found.file_name().unwrap(), "scrobbler.log");
    }

    #[test]
    fn find_ignores_two_levels_deep() {
        let tmp = tempfile::tempdir().unwrap();
        fs::create_dir_all(tmp.path().join("a/b")).unwrap();
        fs::write(tmp.path().join("a/b/scrobbler.log"), "").unwrap();
        assert_eq!(find_scrobbler_log(tmp.path()), None);
    }

    #[test]
    fn find_is_case_insensitive() {
        let tmp = tempfile::tempdir().unwrap();
        fs::write(tmp.path().join("LastFM.log"), "#AUDIOSCROBBLER/1.1\n").unwrap();
        assert!(find_scrobbler_log(tmp.path()).is_some());
    }

    #[test]
    fn rewrite_keeps_header_and_kept_rows() {
        let tmp = tempfile::tempdir().unwrap();
        let original = "#AUDIOSCROBBLER/1.1\n#TZ/UTC\n\
                        A\tAl\tSubmitted\t1\t200\tL\t1700000000\t\n\
                        B\tBl\tUnmatched\t2\t200\tL\t1700000100\t\n";
        let f = tmp.path().join(".scrobbler.log");
        fs::write(&f, original).unwrap();
        rewrite_scrobbler_log(&f, original, &["B\tBl\tUnmatched\t2\t200\tL\t1700000100\t".to_owned()]).unwrap();
        let out = fs::read_to_string(&f).unwrap();
        assert_eq!(out, "#AUDIOSCROBBLER/1.1\n#TZ/UTC\nB\tBl\tUnmatched\t2\t200\tL\t1700000100\t\n");
        let parsed = parse_scrobbler_log(&out);
        assert_eq!(parsed.len(), 1);
        assert_eq!(parsed[0].title, "Unmatched");
        assert!(!tmp.path().join(".scrobbler.log.tmp").exists());
    }

    #[test]
    fn rewrite_with_empty_keep_leaves_header() {
        let tmp = tempfile::tempdir().unwrap();
        let original = "#AUDIOSCROBBLER/1.1\nA\tAl\tGone\t1\t200\tL\t1700000000\t\n";
        let f = tmp.path().join(".scrobbler.log");
        fs::write(&f, original).unwrap();
        rewrite_scrobbler_log(&f, original, &[]).unwrap();
        let out = fs::read_to_string(&f).unwrap();
        assert_eq!(out, "#AUDIOSCROBBLER/1.1\n");
        assert!(parse_scrobbler_log(&out).is_empty());
    }

    #[test]
    fn rewrite_without_header_empties_file() {
        let tmp = tempfile::tempdir().unwrap();
        let original = "A\tAl\tGone\t1\t200\tL\t1700000000\t\n";
        let f = tmp.path().join(".scrobbler.log");
        fs::write(&f, original).unwrap();
        rewrite_scrobbler_log(&f, original, &[]).unwrap();
        assert!(f.exists());
        assert_eq!(fs::read_to_string(&f).unwrap(), "");
    }

    #[test]
    fn read_strips_bom_and_rejects_malformed_utf8() {
        let tmp = tempfile::tempdir().unwrap();
        let f = tmp.path().join(".scrobbler.log");
        fs::write(&f, b"\xEF\xBB\xBF#AUDIOSCROBBLER/1.1\nA\tAl\tT\t1\t2\tL\t1700000000\n").unwrap();
        let text = read_scrobbler_log(&f).unwrap();
        assert_eq!(rewritten_scrobbler_log(&text, &[]), "#AUDIOSCROBBLER/1.1\n");
        fs::write(&f, b"#A\n\xff\n").unwrap();
        assert_eq!(read_scrobbler_log(&f).unwrap_err().kind(), io::ErrorKind::InvalidData);
    }
}
