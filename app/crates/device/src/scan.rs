//! Device scan (port of `device_scan.dart`): rebuilds album manifests from
//! files already on the device and reports cross-folder and intra-folder
//! duplicates.

use std::collections::{HashMap, HashSet};
use std::fs;
use std::path::Path;

use dapper_domain::{DeviceSettings, FilenameFormat, FolderStructure, LibraryReader, Result, Song};
use dapper_paths::{basename_without_extension, build_album_folder, render_filename_template, to_safe_filename};
use indexmap::IndexMap;
use serde::Serialize;

use crate::manifest::{AlbumManifest, ManifestSong, is_audio_file, read_manifest, write_manifest};
use crate::{PruneResult, TagSanitizeResult};

/// Progress tick for long device operations (types.ts `ScanProgress`).
#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Progress {
    pub phase: String,
    pub done: u64,
    pub total: Option<u64>,
}

impl Progress {
    pub fn new(phase: impl Into<String>, done: u64, total: Option<u64>) -> Self {
        Self { phase: phase.into(), done, total }
    }
}

/// Runs blocking filesystem work from async code. On a multi-threaded tokio
/// runtime this uses `block_in_place` (so borrowed data and non-`'static`
/// callbacks are allowed); elsewhere it runs inline.
pub(crate) fn blocking<T>(f: impl FnOnce() -> T) -> T {
    match tokio::runtime::Handle::try_current() {
        Ok(h) if h.runtime_flavor() == tokio::runtime::RuntimeFlavor::MultiThread => tokio::task::block_in_place(f),
        _ => f(),
    }
}

/// A song id found in two or more album folders.
#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct DeviceDuplicate {
    pub song_id: String,
    pub title: String,
    pub folder_paths: Vec<String>,
}

/// Several audio files sharing a track-number prefix in one folder.
/// `correct_filename` is the one whose title matches the manifest, if known.
#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct FileDuplicate {
    pub folder_path: String,
    pub filenames: Vec<String>,
    pub correct_filename: Option<String>,
}

impl FileDuplicate {
    pub fn can_resolve(&self) -> bool {
        self.correct_filename.is_some()
    }

    /// Every filename except the correct one; empty when unresolvable.
    pub fn deletable(&self) -> Vec<String> {
        match &self.correct_filename {
            None => Vec::new(),
            Some(c) => self.filenames.iter().filter(|f| *f != c).cloned().collect(),
        }
    }
}

/// `DeviceScanResult` plus the optional prune / tag-clean results the caller
/// ran alongside it (types.ts `ScanReport`).
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ScanReport {
    pub albums_scanned: u64,
    pub albums_matched: u64,
    pub songs_matched: u64,
    /// Distinct song ids on the device after the scan.
    pub songs_total: u64,
    pub manifest_duplicates: Vec<DeviceDuplicate>,
    pub file_duplicates: Vec<FileDuplicate>,
    pub prune: Option<PruneResult>,
    pub clean: Option<TagSanitizeResult>,
}

impl ScanReport {
    pub fn has_duplicates(&self) -> bool {
        !self.manifest_duplicates.is_empty() || !self.file_duplicates.is_empty()
    }

    pub fn without_file_duplicate(mut self, dup: &FileDuplicate) -> Self {
        self.file_duplicates.retain(|d| d != dup);
        self
    }
}

/// Scans the device: phase 1 rebuilds manifests for album folders (artist /
/// album layouts and custom) from the library, phase 2 walks the music root
/// for same-prefix files. Blocking filesystem work runs via `block_in_place`
/// on a multi-threaded runtime (inline otherwise). Albums whose songs fail to
/// load are skipped; a failing `all_albums` is returned as the error.
pub async fn scan_device(
    settings: &DeviceSettings,
    reader: &dyn LibraryReader,
    mut on_progress: impl FnMut(Progress),
) -> Result<ScanReport> {
    let mut song_folders: IndexMap<String, Vec<String>> = IndexMap::new();
    let mut song_titles: HashMap<String, String> = HashMap::new();
    let mut report = ScanReport::default();

    if !matches!(settings.folder_structure, FolderStructure::Flat | FolderStructure::ArtistOnly) {
        let mut track = |ms: &ManifestSong, folder: &str| {
            song_titles.entry(ms.id.clone()).or_insert_with(|| ms.title.clone());
            song_folders.entry(ms.id.clone()).or_default().push(folder.to_owned());
        };
        on_progress(Progress::new("Loading albums…", 0, None));
        let albums = reader.all_albums().await?;
        let total = albums.len() as u64;
        for album in &albums {
            report.albums_scanned += 1;
            let Some(folder) = build_album_folder(album.artist.as_deref(), &album.name, album.year, settings) else {
                continue;
            };
            let listing = blocking(|| {
                let path = Path::new(&folder);
                if !path.is_dir() {
                    return None;
                }
                Some((read_manifest(path), audio_basenames(path)))
            });
            let Some((existing, audio_files)) = listing else { continue };
            for ms in existing.iter().flat_map(|m| m.songs.iter()) {
                track(ms, &folder);
            }
            let existing_ids: HashSet<&str> =
                existing.iter().flat_map(|m| m.songs.iter().map(|s| s.id.as_str())).collect();
            if audio_files.is_empty() {
                continue;
            }
            report.albums_matched += 1;
            if (existing_ids.len() as i64) >= album.song_count {
                continue;
            }
            on_progress(Progress::new(format!("Scanning \"{}\"…", album.name), report.albums_scanned, Some(total)));
            let Ok(songs) = reader.album_songs(&album.id).await else { continue };
            let mut new_entries = Vec::new();
            for song in &songs {
                if existing_ids.contains(song.id.as_str()) {
                    continue;
                }
                if audio_files.contains(&filename_without_ext(song, settings)) {
                    let ms = ManifestSong::for_song(song, None);
                    track(&ms, &folder);
                    new_entries.push(ms);
                }
            }
            let write = if !new_entries.is_empty() {
                report.songs_matched += new_entries.len() as u64;
                let mut songs = existing.as_ref().map(|m| m.songs.clone()).unwrap_or_default();
                songs.extend(new_entries);
                Some(AlbumManifest { songs, expected_song_count: Some(album.song_count) })
            } else {
                existing.as_ref().filter(|m| m.expected_song_count != Some(album.song_count)).map(|m| AlbumManifest {
                    songs: m.songs.clone(),
                    expected_song_count: Some(album.song_count),
                })
            };
            if let Some(m) = write
                && let Err(e) = blocking(|| write_manifest(&folder, m))
            {
                tracing::warn!("scan_device: manifest write in {folder} failed: {e}");
            }
        }
    }

    report.songs_total = song_folders.len() as u64;
    report.manifest_duplicates = song_folders
        .into_iter()
        .filter(|(_, f)| f.len() > 1)
        .map(|(id, folder_paths)| DeviceDuplicate {
            title: song_titles.get(&id).cloned().unwrap_or_else(|| id.clone()),
            song_id: id,
            folder_paths,
        })
        .collect();

    on_progress(Progress::new("Checking for file duplicates…", report.albums_scanned, None));
    report.file_duplicates = blocking(|| {
        let mut out = Vec::new();
        let root = settings.resolved_music_root();
        if Path::new(&root).is_dir() {
            collect_file_duplicates(Path::new(&root), &mut out, settings, &mut HashSet::new());
        }
        out
    });
    Ok(report)
}

/// Basenames (no extension) of regular audio files directly in `folder`.
fn audio_basenames(folder: &Path) -> HashSet<String> {
    sorted_entries(folder)
        .into_iter()
        .filter(|(p, ft)| ft.is_file() && is_audio_file(p))
        .map(|(p, _)| basename_without_extension(&p.to_string_lossy()))
        .collect()
}

/// Directory entries sorted by name for determinism. Like Dart's `listSync`
/// (and `count_audio_files`), links are followed: a symlink reports its
/// target's type; dangling links are dropped.
fn sorted_entries(dir: &Path) -> Vec<(std::path::PathBuf, fs::FileType)> {
    let mut v: Vec<_> = match fs::read_dir(dir) {
        Ok(rd) => rd
            .filter_map(|e| e.ok())
            .filter_map(|e| {
                let path = e.path();
                let ft = match e.file_type().ok()? {
                    t if t.is_symlink() => fs::metadata(&path).ok()?.file_type(),
                    t => t,
                };
                Some((path, ft))
            })
            .collect(),
        Err(_) => Vec::new(),
    };
    v.sort_by(|a, b| a.0.cmp(&b.0));
    v
}

fn file_name(p: &Path) -> String {
    p.file_name().map(|n| n.to_string_lossy().into_owned()).unwrap_or_default()
}

/// `visited` holds canonical directories already walked so symlinked
/// directory cycles terminate.
fn collect_file_duplicates(
    dir: &Path,
    out: &mut Vec<FileDuplicate>,
    settings: &DeviceSettings,
    visited: &mut HashSet<std::path::PathBuf>,
) {
    if !dir.canonicalize().is_ok_and(|c| visited.insert(c)) {
        return;
    }
    let manifest_titles: HashSet<String> =
        read_manifest(dir).map(|m| m.songs.iter().map(|s| to_safe_filename(&s.title)).collect()).unwrap_or_default();

    let mut groups: IndexMap<String, Vec<String>> = IndexMap::new();
    for (path, ft) in sorted_entries(dir) {
        let name = file_name(&path);
        if ft.is_file() && is_audio_file(&path) {
            if let Some(prefix) = track_prefix(&basename_without_extension(&name)) {
                groups.entry(prefix.to_owned()).or_default().push(name);
            }
        } else if ft.is_dir() && !name.starts_with('.') {
            collect_file_duplicates(&path, out, settings, visited);
        }
    }

    for (_, filenames) in groups {
        if filenames.len() < 2 {
            continue;
        }
        let correct = if manifest_titles.is_empty() {
            None
        } else {
            filenames
                .iter()
                .find(|f| {
                    strip_track_prefix(&basename_without_extension(f), settings.filename_format)
                        .is_some_and(|t| manifest_titles.contains(t))
                })
                .cloned()
        };
        out.push(FileDuplicate {
            folder_path: dir.to_string_lossy().into_owned(),
            filenames,
            correct_filename: correct,
        });
    }
}

fn leading_digits(s: &str) -> usize {
    s.bytes().take_while(u8::is_ascii_digit).count()
}

/// Leading `\d+(-\d+)?` track prefix, e.g. "1-06" or "06".
fn track_prefix(name: &str) -> Option<&str> {
    let n = leading_digits(name);
    if n == 0 {
        return None;
    }
    let rest = &name[n..];
    let m = match rest.strip_prefix('-') {
        Some(r) if leading_digits(r) > 0 => n + 1 + leading_digits(r),
        _ => n,
    };
    Some(&name[..m])
}

/// Title portion after the format's track prefix; `None` if absent.
fn strip_track_prefix(name: &str, format: FilenameFormat) -> Option<&str> {
    match format {
        FilenameFormat::DiscTrack => {
            let a = leading_digits(name);
            if a == 0 {
                return None;
            }
            let r = name[a..].strip_prefix('-')?;
            let b = leading_digits(r);
            if b == 0 {
                return None;
            }
            r[b..].strip_prefix(" - ")
        }
        FilenameFormat::Track => {
            let a = leading_digits(name);
            if a == 0 {
                return None;
            }
            name[a..].strip_prefix(' ')
        }
        FilenameFormat::None | FilenameFormat::Custom => Some(name),
    }
}

/// Filename stem the transfer engine would have written for `song`.
fn filename_without_ext(song: &Song, settings: &DeviceSettings) -> String {
    let title = to_safe_filename(&song.title);
    if settings.filename_format == FilenameFormat::Custom {
        let safe = to_safe_filename(&render_filename_template(&settings.custom_filename_template, song));
        return if safe.is_empty() { title } else { safe };
    }
    let disc = song.disc_number.unwrap_or(1);
    let prefix = match (settings.filename_format, song.track) {
        (FilenameFormat::Track, Some(t)) => format!("{t:02}"),
        (FilenameFormat::DiscTrack, Some(t)) => format!("{disc}-{t:02}"),
        _ => String::new(),
    };
    let sep = if settings.filename_format == FilenameFormat::DiscTrack { " - " } else { " " };
    if prefix.is_empty() { title } else { format!("{prefix}{sep}{title}") }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::test_support::{FakeReader, album, song};

    fn settings(root: &Path) -> DeviceSettings {
        DeviceSettings::new(root.to_string_lossy())
    }

    #[test]
    fn prefixes() {
        assert_eq!(track_prefix("1-06 - X"), Some("1-06"));
        assert_eq!(track_prefix("06 X"), Some("06"));
        assert_eq!(track_prefix("1- X"), Some("1"));
        assert_eq!(track_prefix("X"), None);
        assert_eq!(strip_track_prefix("1-06 - Title", FilenameFormat::DiscTrack), Some("Title"));
        assert_eq!(strip_track_prefix("06 Title", FilenameFormat::Track), Some("Title"));
        assert_eq!(strip_track_prefix("Title", FilenameFormat::Track), None);
    }

    #[tokio::test(flavor = "multi_thread")]
    async fn rebuilds_manifest_and_finds_duplicates() {
        let tmp = tempfile::tempdir().unwrap();
        let s = settings(tmp.path());
        let dir = tmp.path().join("Art").join("Alb");
        fs::create_dir_all(&dir).unwrap();
        fs::write(dir.join("1-01 - One.flac"), "x").unwrap();
        fs::write(dir.join("1-02 - Two.flac"), "x").unwrap();
        fs::write(dir.join("1-02 - Two (old).flac"), "x").unwrap();
        let mut a = album("al1", "Art", "Alb");
        a.song_count = 3;
        let mut s1 = song("s1", "One", "Art", "Alb");
        s1.track = Some(1);
        let mut s2 = song("s2", "Two", "Art", "Alb");
        s2.track = Some(2);
        let mut s3 = song("s3", "Three", "Art", "Alb");
        s3.track = Some(3);
        let reader = FakeReader { albums: vec![a], album_songs: [("al1".into(), vec![s1, s2, s3])].into(), ..Default::default() };

        let mut ticks = 0;
        let r = scan_device(&s, &reader, |_| ticks += 1).await.unwrap();
        assert!(ticks > 0);
        assert_eq!((r.albums_scanned, r.albums_matched, r.songs_matched, r.songs_total), (1, 1, 2, 2));
        let m = read_manifest(&dir).unwrap();
        assert_eq!(m.songs.iter().map(|s| s.id.as_str()).collect::<Vec<_>>(), ["s1", "s2"]);
        assert_eq!(m.expected_song_count, Some(3));
        assert_eq!(r.file_duplicates.len(), 1);
        let d = &r.file_duplicates[0];
        assert_eq!(d.correct_filename.as_deref(), Some("1-02 - Two.flac"));
        assert_eq!(d.deletable(), ["1-02 - Two (old).flac"]);

        let j = serde_json::to_value(&r).unwrap();
        assert!(j.get("manifestDuplicates").is_some() && j["prune"].is_null() && j["clean"].is_null());
    }

    #[tokio::test]
    async fn cross_folder_manifest_duplicates() {
        let tmp = tempfile::tempdir().unwrap();
        let s = settings(tmp.path());
        let mut albums = Vec::new();
        for name in ["A", "B"] {
            let dir = tmp.path().join("Art").join(name);
            fs::create_dir_all(&dir).unwrap();
            fs::write(dir.join("x.mp3"), "x").unwrap();
            write_manifest(
                &dir,
                AlbumManifest {
                    songs: vec![ManifestSong::for_song(&song("dup", "Dup", "Art", name), None)],
                    expected_song_count: Some(1),
                },
            )
            .unwrap();
            let mut a = album(name, "Art", name);
            a.song_count = 1;
            albums.push(a);
        }
        let reader = FakeReader { albums, ..Default::default() };
        let r = scan_device(&s, &reader, |_| {}).await.unwrap();
        assert_eq!(r.manifest_duplicates.len(), 1);
        assert_eq!(r.manifest_duplicates[0].title, "Dup");
        assert_eq!(r.manifest_duplicates[0].folder_paths.len(), 2);
        assert_eq!(r.songs_total, 1);
    }

    // Links are followed like Dart's listSync; directory cycles terminate.
    #[cfg(unix)]
    #[tokio::test]
    async fn follows_symlinks_and_survives_cycles() {
        let tmp = tempfile::tempdir().unwrap();
        let s = settings(tmp.path());
        let store = tmp.path().join(".store");
        fs::create_dir_all(&store).unwrap();
        fs::write(store.join("1-01 - One.flac"), "x").unwrap();
        let dir = tmp.path().join("Art").join("Alb");
        fs::create_dir_all(&dir).unwrap();
        std::os::unix::fs::symlink(store.join("1-01 - One.flac"), dir.join("1-01 - One.flac")).unwrap();
        fs::write(dir.join("1-01 - Dupe.flac"), "x").unwrap();
        std::os::unix::fs::symlink(tmp.path(), dir.join("loop")).unwrap();
        let mut a = album("al1", "Art", "Alb");
        a.song_count = 1;
        let mut s1 = song("s1", "One", "Art", "Alb");
        s1.track = Some(1);
        let reader = FakeReader { albums: vec![a], album_songs: [("al1".into(), vec![s1])].into(), ..Default::default() };
        let r = scan_device(&s, &reader, |_| {}).await.unwrap();
        assert_eq!((r.albums_matched, r.songs_matched), (1, 1));
        assert_eq!(r.file_duplicates.len(), 1);
        assert_eq!(r.file_duplicates[0].filenames.len(), 2);
    }
}
