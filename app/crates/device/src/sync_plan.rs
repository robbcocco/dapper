//! Library-vs-device diff (port of `library_sync.dart`
//! `buildLibrarySyncPlan`).

use dapper_domain::{Album, AlbumSyncStatus, DeviceSettings, FolderStructure, LibraryReader, Result};
use serde::Serialize;

use crate::manifest::album_sync_on_device;
use crate::scan::blocking;

/// Progress is reported every this many albums (and once at the end).
const PROGRESS_EVERY: usize = 500;

/// types.ts `LibrarySyncPlan`: every library album absent from or only
/// partially on the device.
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct LibrarySyncPlan {
    pub unsynced: Vec<Album>,
    pub missing_songs: i64,
    pub missing_albums: usize,
    #[serde(skip)]
    pub albums_scanned: usize,
}

/// Classifies every album from `reader.all_albums()` (cache-backed, no
/// re-paging) against the manifest caches. Flat / artist-only layouts and
/// custom templates without `{album}` have no per-album folder and yield an
/// empty plan. The classification touches the filesystem; it runs via
/// `block_in_place` on a multi-threaded runtime (inline otherwise).
/// `on_progress` receives the number of albums scanned so far.
pub async fn build_library_sync_plan(
    reader: &dyn LibraryReader,
    settings: &DeviceSettings,
    mut on_progress: impl FnMut(usize),
) -> Result<LibrarySyncPlan> {
    if matches!(settings.folder_structure, FolderStructure::Flat | FolderStructure::ArtistOnly)
        || (settings.folder_structure == FolderStructure::Custom && !settings.custom_folder_template.contains("{album}"))
    {
        return Ok(LibrarySyncPlan::default());
    }
    let albums = reader.all_albums().await?;
    Ok(blocking(|| {
        let mut plan = LibrarySyncPlan::default();
        for album in albums {
            plan.albums_scanned += 1;
            let status = album_sync_on_device(album.artist.as_deref(), &album.name, album.year, album.song_count, settings);
            if status != AlbumSyncStatus::Full {
                plan.missing_songs += album.song_count;
                plan.unsynced.push(album);
            }
            if plan.albums_scanned.is_multiple_of(PROGRESS_EVERY) {
                on_progress(plan.albums_scanned);
            }
        }
        plan.missing_albums = plan.unsynced.len();
        on_progress(plan.albums_scanned);
        plan
    }))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::manifest::{AlbumManifest, ManifestSong, write_manifest};
    use crate::test_support::{FakeReader, album, song};

    #[tokio::test]
    async fn lists_absent_and_partial() {
        let t = tempfile::tempdir().unwrap();
        let settings = DeviceSettings::new(t.path().to_string_lossy());
        for (name, n) in [("Full", 1), ("Part", 1)] {
            let d = t.path().join("Art").join(name);
            std::fs::create_dir_all(&d).unwrap();
            let songs = (0..n).map(|i| ManifestSong::for_song(&song(&format!("{name}{i}"), "t", "Art", name), None)).collect();
            write_manifest(&d, AlbumManifest { songs, expected_song_count: Some(if name == "Full" { 1 } else { 3 }) }).unwrap();
        }
        let mk = |id: &str, name: &str, n| {
            let mut a = album(id, "Art", name);
            a.song_count = n;
            a
        };
        let reader = FakeReader { albums: vec![mk("f", "Full", 1), mk("p", "Part", 3), mk("x", "Absent", 4)], ..Default::default() };
        let mut last = 0;
        let plan = build_library_sync_plan(&reader, &settings, |n| last = n).await.unwrap();
        assert_eq!(last, 3);
        assert_eq!(plan.unsynced.iter().map(|a| a.id.as_str()).collect::<Vec<_>>(), ["p", "x"]);
        assert_eq!((plan.missing_songs, plan.missing_albums), (7, 2));
        let j = serde_json::to_value(&plan).unwrap();
        assert_eq!(j["missingAlbums"], 2);
        assert!(j.get("albumsScanned").is_none());

        let mut flat = settings.clone();
        flat.folder_structure = FolderStructure::Flat;
        assert_eq!(build_library_sync_plan(&reader, &flat, |_| {}).await.unwrap(), LibrarySyncPlan::default());
    }
}
