//! Device prune (port of `device_prune.dart`): deletes files whose song ids
//! are no longer in the library and rewrites each album manifest.

use std::collections::HashSet;
use std::fs;
use std::path::{Path, PathBuf};

use dapper_domain::{DeviceSettings, FolderStructure, LibraryReader, Result};
use dapper_paths::{basename_without_extension, to_safe_filename};
use serde::Serialize;

use crate::manifest::{AlbumManifest, is_audio_file, read_manifest, write_manifest};
use crate::scan::{Progress, blocking};

/// types.ts `PruneResult`.
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct PruneResult {
    /// Only songs whose file was actually deleted.
    pub songs_removed: u64,
    pub bytes_freed: u64,
    pub errors: Vec<String>,
}

/// Removes orphaned songs from `<root>/<artist>/<album>` folders. No-op for
/// flat and artist-only layouts (no per-album manifests). Fetches the library
/// ids, then does the blocking walk via `block_in_place` on a multi-threaded
/// runtime (inline otherwise).
pub async fn prune_device(
    settings: &DeviceSettings,
    reader: &dyn LibraryReader,
    mut on_progress: impl FnMut(Progress),
) -> Result<PruneResult> {
    if matches!(settings.folder_structure, FolderStructure::Flat | FolderStructure::ArtistOnly) {
        return Ok(PruneResult::default());
    }
    on_progress(Progress::new("Loading library…", 0, None));
    let ids = reader.all_song_ids().await?;
    on_progress(Progress::new(format!("Loaded {} songs from library…", ids.len()), 0, None));
    Ok(blocking(|| prune_folders(Path::new(&settings.resolved_music_root()), &ids, on_progress)))
}

/// Blocking walk of `root/<artist>/<album>` pruning manifest orphans.
pub fn prune_folders(root: &Path, library_ids: &HashSet<String>, mut on_progress: impl FnMut(Progress)) -> PruneResult {
    let mut result = PruneResult::default();
    if !root.is_dir() {
        return result;
    }
    on_progress(Progress::new("Scanning device…", 0, None));
    let mut done = 0;
    for artist in subdirs(root) {
        for album in subdirs(&artist) {
            done += 1;
            let name = album.file_name().map(|n| n.to_string_lossy().into_owned()).unwrap_or_default();
            on_progress(Progress::new(format!("Checking {name}…"), done, None));
            prune_folder(&album, library_ids, &mut result);
        }
    }
    result
}

fn subdirs(dir: &Path) -> Vec<PathBuf> {
    let mut v: Vec<PathBuf> = fs::read_dir(dir)
        .map(|rd| {
            rd.filter_map(|e| e.ok()).filter(|e| e.file_type().is_ok_and(|t| t.is_dir())).map(|e| e.path()).collect()
        })
        .unwrap_or_default();
    v.sort();
    v
}

fn prune_folder(folder: &Path, library_ids: &HashSet<String>, result: &mut PruneResult) {
    let Some(manifest) = read_manifest(folder) else { return };
    if manifest.songs.is_empty() {
        return;
    }
    let (keep, orphans): (Vec<_>, Vec<_>) = manifest.songs.iter().cloned().partition(|s| library_ids.contains(&s.id));
    if orphans.is_empty() {
        return;
    }
    // Files belonging to kept songs are never deleted by the title fallback.
    let keep_filenames: HashSet<&str> = keep.iter().filter_map(|s| s.filename.as_deref()).collect();

    // Listing cached so the title fallback stays O(files), not O(orphans × files).
    let mut audio_files: Option<Vec<PathBuf>> = None;

    for orphan in &orphans {
        // A recorded filename must be a bare name in this folder (a crafted
        // manifest must not reach `../x`) and never a kept song's file.
        let mut target = orphan
            .filename
            .as_deref()
            .filter(|f| Path::new(f).file_name().is_some_and(|n| n == *f) && !keep_filenames.contains(f))
            .map(|f| folder.join(f))
            .filter(|c| c.is_file());

        // Legacy manifests lack `filename`: match the EXACT title portion so
        // orphan "Live" never deletes "Live at Wembley.flac".
        if target.is_none() {
            let safe_title = to_safe_filename(&orphan.title);
            if !safe_title.is_empty() {
                let files = audio_files.get_or_insert_with(|| {
                    let mut v: Vec<PathBuf> = fs::read_dir(folder)
                        .map(|rd| {
                            rd.filter_map(|e| e.ok())
                                .filter(|e| e.file_type().is_ok_and(|t| t.is_file()))
                                .map(|e| e.path())
                                .filter(|p| is_audio_file(p))
                                .collect()
                        })
                        .unwrap_or_default();
                    v.sort();
                    v
                });
                target = files
                    .iter()
                    .find(|f| {
                        let name = f.file_name().map(|n| n.to_string_lossy()).unwrap_or_default();
                        !keep_filenames.contains(name.as_ref())
                            && title_portion(&basename_without_extension(&name)) == safe_title
                    })
                    .cloned();
            }
        }

        // Count only files actually deleted from disk.
        if let Some(t) = target.filter(|t| t.is_file()) {
            let res = fs::metadata(&t).and_then(|m| {
                fs::remove_file(&t)?;
                Ok(m.len())
            });
            match res {
                Ok(len) => {
                    result.bytes_freed += len;
                    result.songs_removed += 1;
                }
                Err(e) => result.errors.push(format!("{}: {e}", t.file_name().unwrap_or_default().to_string_lossy())),
            }
        }
    }

    // Preserve expectedSongCount so sync status keeps working after a prune.
    if let Err(e) = write_manifest(folder, AlbumManifest { songs: keep, expected_song_count: manifest.expected_song_count }) {
        result.errors.push(format!("{}: {e}", crate::MANIFEST_FILENAME));
    }
}

/// Strips a leading "06 ", "06 - " or "1-06 - " prefix.
fn title_portion(base: &str) -> &str {
    let digits = |s: &str| s.bytes().take_while(u8::is_ascii_digit).count();
    let a = digits(base);
    if a == 0 {
        return base;
    }
    let mut i = a;
    if let Some(r) = base[i..].strip_prefix('-') {
        let b = digits(r);
        if b > 0 {
            i += 1 + b;
        }
    }
    let rest = &base[i..];
    rest.strip_prefix(" - ").or_else(|| rest.strip_prefix(' ')).unwrap_or(base)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::manifest::ManifestSong;
    use crate::test_support::FakeReader;

    fn ms(id: &str, title: &str) -> ManifestSong {
        ManifestSong { id: id.into(), title: title.into(), artist: None, album: None, filename: None }
    }

    #[test]
    fn title_portions() {
        assert_eq!(title_portion("06 Live"), "Live");
        assert_eq!(title_portion("06 - Live"), "Live");
        assert_eq!(title_portion("1-06 - Live"), "Live");
        assert_eq!(title_portion("1999"), "1999");
        assert_eq!(title_portion("Live"), "Live");
    }

    // Port of test/application/device_prune_test.dart.
    #[tokio::test]
    async fn title_fallback_never_deletes_kept_song_containing_orphan_title() {
        let tmp = tempfile::tempdir().unwrap();
        let album = tmp.path().join("Artist").join("Album");
        fs::create_dir_all(&album).unwrap();
        let orphan = album.join("Live.flac");
        let kept = album.join("Live at Wembley.flac");
        fs::write(&orphan, "x").unwrap();
        fs::write(&kept, "xy").unwrap();
        write_manifest(
            &album,
            AlbumManifest { songs: vec![ms("orphan", "Live"), ms("keep", "Live at Wembley")], expected_song_count: Some(2) },
        )
        .unwrap();

        let settings = DeviceSettings::new(tmp.path().to_string_lossy());
        let reader = FakeReader { song_ids: ["keep".to_string()].into(), ..Default::default() };
        let r = prune_device(&settings, &reader, |_| {}).await.unwrap();

        assert!(kept.exists(), "kept file must survive");
        assert!(!orphan.exists(), "orphan file removed");
        assert_eq!(r.songs_removed, 1);
        assert_eq!(r.bytes_freed, 1);

        let bytes = fs::read(album.join(crate::MANIFEST_FILENAME)).unwrap();
        let after = AlbumManifest::parse(&bytes).unwrap();
        assert_eq!(after.songs.iter().map(|s| s.id.as_str()).collect::<Vec<_>>(), ["keep"]);
        assert_eq!(after.expected_song_count, Some(2));
    }

    #[tokio::test]
    async fn missing_files_and_recorded_filenames() {
        let tmp = tempfile::tempdir().unwrap();
        let album = tmp.path().join("A").join("B");
        fs::create_dir_all(&album).unwrap();
        fs::write(album.join("01 X.mp3"), "abc").unwrap();
        let mut a = ms("a", "Whatever");
        a.filename = Some("01 X.mp3".into());
        write_manifest(&album, AlbumManifest { songs: vec![a, ms("gone", "Gone")], expected_song_count: None }).unwrap();
        let settings = DeviceSettings::new(tmp.path().to_string_lossy());
        let r = prune_device(&settings, &FakeReader::default(), |_| {}).await.unwrap();
        assert_eq!((r.songs_removed, r.bytes_freed), (1, 3));
        assert!(!album.join("01 X.mp3").exists());
    }

    #[tokio::test]
    async fn recorded_filename_must_be_bare_and_not_kept() {
        let tmp = tempfile::tempdir().unwrap();
        let album = tmp.path().join("A").join("B");
        fs::create_dir_all(&album).unwrap();
        let outside = tmp.path().join("A").join("victim.mp3");
        fs::write(&outside, "v").unwrap();
        fs::write(album.join("kept.mp3"), "k").unwrap();
        let mut escape = ms("o1", "No Match");
        escape.filename = Some("../victim.mp3".into());
        let mut steal = ms("o2", "Also No Match");
        steal.filename = Some("kept.mp3".into());
        let mut keep = ms("keep", "Kept");
        keep.filename = Some("kept.mp3".into());
        write_manifest(&album, AlbumManifest { songs: vec![escape, steal, keep], expected_song_count: None }).unwrap();
        let settings = DeviceSettings::new(tmp.path().to_string_lossy());
        let reader = FakeReader { song_ids: ["keep".to_string()].into(), ..Default::default() };
        let r = prune_device(&settings, &reader, |_| {}).await.unwrap();
        assert_eq!(r.songs_removed, 0);
        assert!(outside.exists() && album.join("kept.mp3").exists());
    }

    #[tokio::test]
    async fn flat_is_noop() {
        let mut settings = DeviceSettings::new("/nonexistent");
        settings.folder_structure = FolderStructure::Flat;
        assert_eq!(prune_device(&settings, &FakeReader::default(), |_| {}).await.unwrap(), PruneResult::default());
    }
}
