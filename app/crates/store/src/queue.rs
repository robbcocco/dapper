//! Transfer-queue file, byte-compatible with Flutter's `transfer_queue.json`
//! (`lib/application/transfer/queue_persistence.dart`).

use std::path::Path;

use dapper_domain::{Result, Song, TransferStatus, TransferTask};
use serde::{Deserialize, Serialize};

use crate::db::{enum_name, parse_enum};
use crate::fsutil;

// Zip-group tags are deliberately not persisted: a group interrupted at close
// could restore with its leader already completed (and so not saved), leaving
// followers that never become ready. Restored tasks are plain per-song
// downloads.
#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct TaskOut<'a> {
    id: &'a str,
    song: SongOut<'a>,
    device_path: &'a str,
    status: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    error_message: Option<&'a str>,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct SongOut<'a> {
    id: &'a str,
    title: &'a str,
    #[serde(skip_serializing_if = "Option::is_none")]
    album_id: Option<&'a str>,
    #[serde(skip_serializing_if = "Option::is_none")]
    artist_id: Option<&'a str>,
    #[serde(skip_serializing_if = "Option::is_none")]
    album: Option<&'a str>,
    #[serde(skip_serializing_if = "Option::is_none")]
    artist: Option<&'a str>,
    #[serde(skip_serializing_if = "Option::is_none")]
    duration: Option<i64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    bit_rate: Option<i32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    content_type: Option<&'a str>,
    #[serde(skip_serializing_if = "Option::is_none")]
    suffix: Option<&'a str>,
    #[serde(skip_serializing_if = "Option::is_none")]
    size: Option<i64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    cover_art_id: Option<&'a str>,
    #[serde(skip_serializing_if = "Option::is_none")]
    track: Option<i32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    disc_number: Option<i32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    year: Option<i32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    genre: Option<&'a str>,
    #[serde(skip_serializing_if = "Option::is_none")]
    album_artist: Option<&'a str>,
}

impl<'a> From<&'a TransferTask> for TaskOut<'a> {
    fn from(t: &'a TransferTask) -> Self {
        let s = &t.song;
        Self {
            id: &t.id,
            song: SongOut {
                id: &s.id,
                title: &s.title,
                album_id: s.album_id.as_deref(),
                artist_id: s.artist_id.as_deref(),
                album: s.album.as_deref(),
                artist: s.artist.as_deref(),
                duration: s.duration,
                bit_rate: s.bit_rate,
                content_type: s.content_type.as_deref(),
                suffix: s.suffix.as_deref(),
                size: s.size,
                cover_art_id: s.cover_art_id.as_deref(),
                track: s.track,
                disc_number: s.disc_number,
                year: s.year,
                genre: s.genre.as_deref(),
                album_artist: s.album_artist.as_deref(),
            },
            device_path: &t.device_path,
            status: enum_name(t.status),
            error_message: t.error_message.as_deref(),
        }
    }
}

// Strict typing mirrors Dart's `as String` / `as int?` casts: any mistyped
// field fails the whole load, exactly like the Dart catch-all.
#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct TaskIn {
    id: String,
    song: SongIn,
    device_path: String,
    status: Option<String>,
    error_message: Option<String>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct SongIn {
    id: String,
    title: String,
    album_id: Option<String>,
    artist_id: Option<String>,
    album: Option<String>,
    artist: Option<String>,
    duration: Option<i64>,
    bit_rate: Option<i32>,
    content_type: Option<String>,
    suffix: Option<String>,
    size: Option<i64>,
    cover_art_id: Option<String>,
    track: Option<i32>,
    disc_number: Option<i32>,
    year: Option<i32>,
    genre: Option<String>,
    album_artist: Option<String>,
}

impl From<TaskIn> for TransferTask {
    fn from(j: TaskIn) -> Self {
        let mut status = parse_enum(
            j.status.as_deref().unwrap_or("queued"),
            TransferStatus::Queued,
        );
        // Tasks that were mid-flight when the app closed restart from scratch.
        if status == TransferStatus::InProgress {
            status = TransferStatus::Queued;
        }
        let s = j.song;
        TransferTask {
            id: j.id,
            song: Song {
                id: s.id,
                title: s.title,
                album_id: s.album_id,
                artist_id: s.artist_id,
                album: s.album,
                artist: s.artist,
                duration: s.duration,
                bit_rate: s.bit_rate,
                content_type: s.content_type,
                suffix: s.suffix,
                size: s.size,
                cover_art_id: s.cover_art_id,
                track: s.track,
                disc_number: s.disc_number,
                year: s.year,
                genre: s.genre,
                album_artist: s.album_artist,
                ..Default::default()
            },
            device_path: j.device_path,
            status,
            error_message: j.error_message,
            ..Default::default()
        }
    }
}

/// Strict parse; `Err` where Dart's `loadQueue` would have hit its catch-all.
pub(crate) fn try_parse_queue(raw: &str) -> serde_json::Result<Vec<TransferTask>> {
    serde_json::from_str::<Vec<serde_json::Value>>(raw)?
        .into_iter()
        .filter(serde_json::Value::is_object)
        .map(|v| serde_json::from_value::<TaskIn>(v).map(TransferTask::from))
        .collect()
}

/// Parses queue JSON; any malformed content yields `[]` (Dart `loadQueue`).
pub fn parse_queue(raw: &str) -> Vec<TransferTask> {
    try_parse_queue(raw).unwrap_or_else(|e| {
        tracing::warn!("queue: failed to parse queue file — {e}");
        Vec::new()
    })
}

/// Only queued / inProgress / failed tasks are persisted.
pub fn encode_queue(tasks: &[TransferTask]) -> String {
    let out: Vec<TaskOut<'_>> = tasks
        .iter()
        .filter(|t| {
            matches!(
                t.status,
                TransferStatus::Queued | TransferStatus::InProgress | TransferStatus::Failed
            )
        })
        .map(TaskOut::from)
        .collect();
    serde_json::to_string(&out).expect("queue JSON serialisation cannot fail")
}

pub fn load_queue_file(path: &Path) -> Vec<TransferTask> {
    match std::fs::read_to_string(path) {
        Ok(raw) => parse_queue(&raw),
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => Vec::new(),
        Err(e) => {
            tracing::warn!("queue: failed to read {} — {e}", path.display());
            Vec::new()
        }
    }
}

pub fn save_queue_file(path: &Path, tasks: &[TransferTask]) -> Result<()> {
    fsutil::write_atomic(path, encode_queue(tasks).as_bytes(), false)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn song() -> Song {
        Song {
            id: "s1".into(),
            title: "Title".into(),
            album: Some("Album".into()),
            artist: Some("Artist".into()),
            suffix: Some("mp3".into()),
            track: Some(1),
            ..Default::default()
        }
    }

    fn task(id: &str, status: TransferStatus) -> TransferTask {
        TransferTask {
            status,
            ..TransferTask::new(id, song(), "/dev/usb")
        }
    }

    fn setup() -> (tempfile::TempDir, std::path::PathBuf) {
        let tmp = tempfile::tempdir().unwrap();
        let p = tmp.path().join("queue.json");
        (tmp, p)
    }

    fn ids(v: &[TransferTask]) -> Vec<&str> {
        v.iter().map(|t| t.id.as_str()).collect()
    }

    #[test]
    fn load_returns_empty_when_file_missing() {
        let (_t, p) = setup();
        assert!(load_queue_file(&p).is_empty());
    }

    #[test]
    fn round_trip_queued_tasks() {
        let (_t, p) = setup();
        save_queue_file(
            &p,
            &[
                task("a", TransferStatus::Queued),
                task("b", TransferStatus::Queued),
            ],
        )
        .unwrap();
        let loaded = load_queue_file(&p);
        assert_eq!(ids(&loaded), ["a", "b"]);
        assert_eq!(loaded[0].device_path, "/dev/usb");
    }

    #[test]
    fn skips_completed_and_cancelled() {
        let (_t, p) = setup();
        save_queue_file(
            &p,
            &[
                task("queued", TransferStatus::Queued),
                task("inProgress", TransferStatus::InProgress),
                task("failed", TransferStatus::Failed),
                task("completed", TransferStatus::Completed),
                task("cancelled", TransferStatus::Cancelled),
            ],
        )
        .unwrap();
        let mut got = ids(&load_queue_file(&p))
            .into_iter()
            .map(String::from)
            .collect::<Vec<_>>();
        got.sort();
        assert_eq!(got, ["failed", "inProgress", "queued"]);
    }

    #[test]
    fn mid_flight_tasks_restart_as_queued() {
        let (_t, p) = setup();
        let t = TransferTask {
            bytes_received: 10,
            total_bytes: 20,
            ..task("t", TransferStatus::InProgress)
        };
        save_queue_file(&p, &[t]).unwrap();
        let loaded = load_queue_file(&p);
        assert_eq!(loaded[0].status, TransferStatus::Queued);
        assert_eq!(loaded[0].bytes_received, 0);
        assert_eq!(loaded[0].total_bytes, 0);
    }

    #[test]
    fn preserves_error_message() {
        let (_t, p) = setup();
        let t = TransferTask {
            error_message: Some("oops".into()),
            ..task("t", TransferStatus::Failed)
        };
        save_queue_file(&p, &[t]).unwrap();
        assert_eq!(
            load_queue_file(&p)[0].error_message.as_deref(),
            Some("oops")
        );
    }

    #[test]
    fn empty_list_round_trips() {
        let (_t, p) = setup();
        save_queue_file(&p, &[]).unwrap();
        assert_eq!(std::fs::read_to_string(&p).unwrap(), "[]");
        assert!(load_queue_file(&p).is_empty());
    }

    #[test]
    fn malformed_json_yields_empty() {
        let (_t, p) = setup();
        std::fs::write(&p, "{this is not valid").unwrap();
        assert!(load_queue_file(&p).is_empty());
        // A mistyped field fails the whole load, like Dart's cast errors.
        std::fs::write(
            &p,
            r#"[{"id":"a","song":{"id":"s","title":"t","duration":1.5},"devicePath":"/d"}]"#,
        )
        .unwrap();
        assert!(load_queue_file(&p).is_empty());
    }

    #[test]
    fn non_map_entries_skipped_and_status_fallbacks() {
        let raw = r#"[1, "x", {"id":"a","song":{"id":"s","title":"t"},"devicePath":"/d"},
                     {"id":"b","song":{"id":"s","title":"t"},"devicePath":"/d","status":"weird"},
                     {"id":"c","song":{"id":"s","title":"t"},"devicePath":"/d","status":"failed"}]"#;
        let got = parse_queue(raw);
        assert_eq!(ids(&got), ["a", "b", "c"]);
        assert_eq!(got[0].status, TransferStatus::Queued);
        assert_eq!(got[1].status, TransferStatus::Queued);
        assert_eq!(got[2].status, TransferStatus::Failed);
    }

    #[test]
    fn zip_tags_stripped() {
        let (_t, p) = setup();
        let s = |id: &str, title: &str| Song {
            id: id.into(),
            title: title.into(),
            ..Default::default()
        };
        let leader = TransferTask {
            status: TransferStatus::InProgress,
            zip_group_id: Some("g1".into()),
            zip_source_id: Some("album-1".into()),
            ..TransferTask::new("leader", s("s1", "A"), "/dev/usb")
        };
        let follower = TransferTask {
            zip_group_id: Some("g1".into()),
            ..TransferTask::new("follower", s("s2", "B"), "/dev/usb")
        };
        save_queue_file(&p, &[leader, follower]).unwrap();
        let loaded = load_queue_file(&p);
        assert_eq!(loaded.len(), 2);
        for t in loaded {
            assert!(!t.is_zip_member());
            assert!(!t.is_zip_leader());
        }
    }

    #[test]
    fn round_trip_preserves_all_song_fields() {
        let (_t, p) = setup();
        let full = Song {
            id: "s-id".into(),
            title: "Title".into(),
            album_id: Some("alb-1".into()),
            artist_id: Some("art-1".into()),
            album: Some("Album".into()),
            artist: Some("Artist".into()),
            duration: Some(240),
            bit_rate: Some(320),
            content_type: Some("audio/mpeg".into()),
            suffix: Some("mp3".into()),
            size: Some(5_000_000),
            cover_art_id: Some("cov-1".into()),
            track: Some(7),
            disc_number: Some(2),
            year: Some(1999),
            genre: Some("Rock".into()),
            album_artist: Some("Album Artist".into()),
            ..Default::default()
        };
        save_queue_file(&p, &[TransferTask::new("t1", full.clone(), "/dev/usb")]).unwrap();
        assert_eq!(load_queue_file(&p)[0].song, full);
    }

    #[test]
    fn json_shape_matches_dart() {
        let t = TransferTask {
            error_message: Some("e".into()),
            ..task("t", TransferStatus::Failed)
        };
        assert_eq!(
            encode_queue(&[t]),
            r#"[{"id":"t","song":{"id":"s1","title":"Title","album":"Album","artist":"Artist","suffix":"mp3","track":1},"devicePath":"/dev/usb","status":"failed","errorMessage":"e"}]"#
        );
    }
}
