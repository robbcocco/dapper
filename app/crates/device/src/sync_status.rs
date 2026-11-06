//! Device sync status for albums and artists (ports of
//! `album_sync_provider.dart` `scanAlbumFolders` and
//! `artist_sync_provider.dart` `_runScan`), plus per-song presence. All
//! functions here are blocking filesystem walks; call them off the UI /
//! async executor (e.g. `spawn_blocking`).

use std::collections::HashMap;
use std::fs;
use std::path::{Path, PathBuf};

use dapper_domain::{Album, AlbumSyncStatus, Artist, ArtistSyncStatus, DeviceSettings, FolderStructure, Song};
use dapper_paths::{artist_folder, build_album_folder};

use crate::manifest::{AlbumManifest, MANIFEST_FILENAME, is_audio_file, read_manifest, song_exists_on_device};

fn entries(dir: &Path, want_dir: bool) -> Vec<PathBuf> {
    fs::read_dir(dir)
        .map(|rd| {
            rd.filter_map(|e| e.ok())
                .filter(|e| e.file_type().is_ok_and(|t| if want_dir { t.is_dir() } else { t.is_file() }))
                .map(|e| e.path())
                .collect()
        })
        .unwrap_or_default()
}

/// Walks `<root>/<artist>/<album>` and returns each album folder's status
/// keyed by folder path. `folder_expected` supplies the library song count
/// per folder, used when a manifest lacks `expectedSongCount`. Folders with
/// no songs are absent from the map. Manifests are read uncached.
pub fn scan_album_folders(root: &Path, folder_expected: &HashMap<String, i64>) -> HashMap<String, AlbumSyncStatus> {
    let mut out = HashMap::new();
    for artist in entries(root, true) {
        for album in entries(&artist, true) {
            let key = album.to_string_lossy().into_owned();
            if let Some(s) = folder_status(&album, folder_expected.get(&key).copied()) {
                out.insert(key, s);
            }
        }
    }
    out
}

fn status(count: i64, expected: i64) -> AlbumSyncStatus {
    if expected > 0 && count >= expected { AlbumSyncStatus::Full } else { AlbumSyncStatus::Partial }
}

fn folder_status(folder: &Path, expected_fallback: Option<i64>) -> Option<AlbumSyncStatus> {
    // A corrupt manifest falls back to counting files.
    if let Some(m) = fs::read(folder.join(MANIFEST_FILENAME)).ok().and_then(|b| AlbumManifest::parse(&b)) {
        let count = m.songs.len() as i64;
        if count == 0 {
            return None;
        }
        return Some(status(count, m.expected_song_count.or(expected_fallback).unwrap_or(0)));
    }
    let files = entries(folder, false).iter().filter(|p| is_audio_file(p)).count() as i64;
    if files == 0 {
        return None;
    }
    Some(status(files, expected_fallback.unwrap_or(0)))
}

/// Album id → sync status for `albums` on the device; albums not on the
/// device are absent. Only artist/album layouts have per-album folders, so
/// other structures yield an empty map.
pub fn album_sync_statuses(settings: &DeviceSettings, albums: &[Album]) -> HashMap<String, AlbumSyncStatus> {
    if !matches!(settings.folder_structure, FolderStructure::ArtistAlbum | FolderStructure::ArtistAlbumYear) {
        return HashMap::new();
    }
    let folders: Vec<(&Album, String)> = albums
        .iter()
        .filter_map(|a| build_album_folder(a.artist.as_deref(), &a.name, a.year, settings).map(|f| (a, f)))
        .collect();
    let folder_expected: HashMap<String, i64> = folders.iter().map(|(a, f)| (f.clone(), a.song_count)).collect();
    let by_folder = scan_album_folders(Path::new(&settings.resolved_music_root()), &folder_expected);
    folders.into_iter().filter_map(|(a, f)| by_folder.get(&f).map(|s| (a.id.clone(), *s))).collect()
}

/// Artist id → sync status; absent means not on the device. Artist/album
/// layouts are `Full` when at least `album_count` album folders are complete;
/// artist-only layouts mark any artist folder holding files `Partial`; flat
/// and custom layouts yield nothing. `albums` supplies the fallback expected
/// song count for manifests without one.
pub fn artist_sync_statuses(
    settings: &DeviceSettings,
    artists: &[Artist],
    albums: &[Album],
) -> HashMap<String, ArtistSyncStatus> {
    let mut out = HashMap::new();
    match settings.folder_structure {
        FolderStructure::ArtistAlbum | FolderStructure::ArtistAlbumYear => {
            let folder_song_count: HashMap<String, i64> = albums
                .iter()
                .filter_map(|a| build_album_folder(a.artist.as_deref(), &a.name, a.year, settings).map(|f| (f, a.song_count)))
                .collect();
            for artist in artists {
                let dir = PathBuf::from(artist_folder(settings, &artist.name));
                if !dir.is_dir() {
                    continue;
                }
                let (mut green, mut any) = (0i64, 0i64);
                for sub in entries(&dir, true) {
                    let manifest = read_manifest(&sub);
                    let audio = entries(&sub, false).iter().filter(|p| is_audio_file(p)).count();
                    let count = manifest.as_ref().map_or(audio, |m| m.songs.len());
                    if count == 0 {
                        continue;
                    }
                    any += 1;
                    let expected = manifest
                        .as_ref()
                        .and_then(|m| m.expected_song_count)
                        .or_else(|| folder_song_count.get(sub.to_string_lossy().as_ref()).copied());
                    match (expected, &manifest) {
                        (Some(e), _) => green += i64::from(count as i64 >= e),
                        (None, Some(m)) if !m.songs.is_empty() => green += i64::from(m.songs.len() >= audio),
                        _ => {}
                    }
                }
                if any == 0 {
                    continue;
                }
                let s = if artist.album_count > 0 && green >= artist.album_count {
                    ArtistSyncStatus::Full
                } else {
                    ArtistSyncStatus::Partial
                };
                out.insert(artist.id.clone(), s);
            }
        }
        FolderStructure::ArtistOnly => {
            for artist in artists {
                let dir = PathBuf::from(artist_folder(settings, &artist.name));
                if dir.is_dir() && !entries(&dir, false).is_empty() {
                    out.insert(artist.id.clone(), ArtistSyncStatus::Partial);
                }
            }
        }
        FolderStructure::Flat | FolderStructure::Custom => {}
    }
    out
}

/// Song id → whether it is on the device (manifest id match when the album
/// has a manifest, else the expected file path).
pub fn song_presence(settings: &DeviceSettings, songs: &[Song]) -> HashMap<String, bool> {
    songs.iter().map(|s| (s.id.clone(), song_exists_on_device(s, settings))).collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::test_support::{album, song};
    use serde_json::json;

    fn mk(root: &Path, artist: &str, name: &str) -> PathBuf {
        let d = root.join(artist).join(name);
        fs::create_dir_all(&d).unwrap();
        d
    }

    fn manifest(dir: &Path, ids: &[&str], expected: Option<i64>) {
        let mut j = json!({"version": 1, "songs": ids.iter().map(|i| json!({"id": i, "title": i})).collect::<Vec<_>>()});
        if let Some(e) = expected {
            j["expectedSongCount"] = json!(e);
        }
        fs::write(dir.join(MANIFEST_FILENAME), j.to_string()).unwrap();
    }

    fn key(p: &Path) -> String {
        p.to_string_lossy().into_owned()
    }

    // Ports of test/application/album_sync_test.dart.
    #[test]
    fn manifest_with_expected_full_when_complete() {
        let t = tempfile::tempdir().unwrap();
        let d = mk(t.path(), "Artist", "Full Album");
        manifest(&d, &["a", "b", "c"], Some(3));
        assert_eq!(scan_album_folders(t.path(), &HashMap::new()).get(&key(&d)), Some(&AlbumSyncStatus::Full));
    }

    #[test]
    fn manifest_fewer_than_expected_partial() {
        let t = tempfile::tempdir().unwrap();
        let d = mk(t.path(), "Artist", "Partial Album");
        manifest(&d, &["a", "b"], Some(5));
        assert_eq!(scan_album_folders(t.path(), &HashMap::new()).get(&key(&d)), Some(&AlbumSyncStatus::Partial));
    }

    #[test]
    fn manifest_without_expected_falls_back_to_library_count() {
        let t = tempfile::tempdir().unwrap();
        let d = mk(t.path(), "Artist", "Legacy Album");
        manifest(&d, &["a", "b", "c"], None);
        let m = scan_album_folders(t.path(), &[(key(&d), 3)].into());
        assert_eq!(m.get(&key(&d)), Some(&AlbumSyncStatus::Full));
        let m2 = scan_album_folders(t.path(), &[(key(&d), 6)].into());
        assert_eq!(m2.get(&key(&d)), Some(&AlbumSyncStatus::Partial));
    }

    #[test]
    fn no_manifest_counts_audio_files() {
        let t = tempfile::tempdir().unwrap();
        let d = mk(t.path(), "Artist", "Externally Managed");
        fs::write(d.join("01 One.flac"), "x").unwrap();
        fs::write(d.join("02 Two.flac"), "x").unwrap();
        let m = scan_album_folders(t.path(), &[(key(&d), 2)].into());
        assert_eq!(m.get(&key(&d)), Some(&AlbumSyncStatus::Full));
    }

    #[test]
    fn empty_album_folder_absent() {
        let t = tempfile::tempdir().unwrap();
        let d = mk(t.path(), "Artist", "Empty");
        assert!(!scan_album_folders(t.path(), &HashMap::new()).contains_key(&key(&d)));
    }

    #[test]
    fn missing_root_empty() {
        let t = tempfile::tempdir().unwrap();
        assert!(scan_album_folders(&t.path().join("does-not-exist"), &HashMap::new()).is_empty());
    }

    #[test]
    fn album_and_artist_statuses() {
        let t = tempfile::tempdir().unwrap();
        let settings = DeviceSettings::new(t.path().to_string_lossy());
        let full = mk(t.path(), "Art", "One");
        manifest(&full, &["a"], Some(1));
        let part = mk(t.path(), "Art", "Two");
        manifest(&part, &["b"], Some(2));
        let mut a1 = album("al1", "Art", "One");
        a1.song_count = 1;
        let mut a2 = album("al2", "Art", "Two");
        a2.song_count = 2;
        let a3 = album("al3", "Art", "Missing");
        let albums = vec![a1, a2, a3];
        let m = album_sync_statuses(&settings, &albums);
        assert_eq!(m.get("al1"), Some(&AlbumSyncStatus::Full));
        assert_eq!(m.get("al2"), Some(&AlbumSyncStatus::Partial));
        assert!(!m.contains_key("al3"));

        let artists = vec![
            Artist { id: "ar1".into(), name: "Art".into(), album_count: 1, ..Default::default() },
            Artist { id: "ar2".into(), name: "Art".into(), album_count: 2, ..Default::default() },
            Artist { id: "ar3".into(), name: "Nobody".into(), album_count: 1, ..Default::default() },
        ];
        let s = artist_sync_statuses(&settings, &artists, &albums);
        assert_eq!(s.get("ar1"), Some(&ArtistSyncStatus::Full));
        assert_eq!(s.get("ar2"), Some(&ArtistSyncStatus::Partial));
        assert!(!s.contains_key("ar3"));

        let mut only = settings.clone();
        only.folder_structure = FolderStructure::ArtistOnly;
        assert!(album_sync_statuses(&only, &albums).is_empty());
        assert!(artist_sync_statuses(&only, &artists, &albums).is_empty(), "artist dir holds only folders");
        fs::write(t.path().join("Art").join("x.mp3"), "x").unwrap();
        assert_eq!(artist_sync_statuses(&only, &artists, &albums).get("ar1"), Some(&ArtistSyncStatus::Partial));
    }

    #[test]
    fn presence_by_manifest() {
        let t = tempfile::tempdir().unwrap();
        let settings = DeviceSettings::new(t.path().to_string_lossy());
        let d = mk(t.path(), "Art", "Alb");
        manifest(&d, &["yes"], None);
        let songs = [song("yes", "Y", "Art", "Alb"), song("no", "N", "Art", "Alb")];
        let p = song_presence(&settings, &songs);
        assert_eq!((p["yes"], p["no"]), (true, false));
    }
}
