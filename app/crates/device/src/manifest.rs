//! `.dapper.json` per-album manifests, their in-memory caches, and the
//! on-device presence checks built on them.

use std::collections::{HashMap, HashSet};
use std::fs;
use std::io;
use std::num::NonZeroUsize;
use std::path::{Path, PathBuf};
use std::sync::{Arc, LazyLock};

use dapper_domain::{AlbumSyncStatus, DeviceSettings, FolderStructure, Song};
use lru::LruCache;
use parking_lot::Mutex;
use serde::Serialize;
use serde_json::Value;

use crate::atomic_file::write_atomic;

/// Filename of the per-album manifest written on the device.
pub const MANIFEST_FILENAME: &str = ".dapper.json";

pub const AUDIO_EXTENSIONS: [&str; 12] =
    ["mp3", "flac", "m4a", "aac", "ogg", "wav", "opus", "wma", "ape", "aiff", "dsf", "dff"];
pub const PLAYLIST_EXTENSIONS: [&str; 2] = ["m3u", "m3u8"];

const MANIFEST_CACHE_CAP: usize = 4096;
const FOLDER_EXISTS_CACHE_CAP: usize = 8192;

fn has_extension_in(path: &Path, set: &[&str]) -> bool {
    let Some(name) = path.file_name() else { return false };
    if name.to_string_lossy().starts_with("._") {
        return false;
    }
    path.extension().is_some_and(|e| set.contains(&e.to_string_lossy().to_lowercase().as_str()))
}

/// Audio file by extension; AppleDouble `._*` sidecars never count.
pub fn is_audio_file(path: &Path) -> bool {
    has_extension_in(path, &AUDIO_EXTENSIONS)
}

/// `.m3u` / `.m3u8` by extension; AppleDouble `._*` sidecars never count.
pub fn is_playlist_file(path: &Path) -> bool {
    has_extension_in(path, &PLAYLIST_EXTENSIONS)
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct ManifestSong {
    pub id: String,
    pub title: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub artist: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub album: Option<String>,
    /// Exact basename as written to disk, used for reliable deletion during prune.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub filename: Option<String>,
}

impl ManifestSong {
    /// The entry recorded when `song` lands on the device as `filename`.
    pub fn for_song(song: &Song, filename: Option<String>) -> Self {
        Self {
            id: song.id.clone(),
            title: song.title.clone(),
            artist: song.album_artist.clone().or_else(|| song.artist.clone()),
            album: song.album.clone(),
            filename,
        }
    }

    /// Dart `ManifestSong.fromJson`: `None` where Dart's casts would throw.
    fn from_json(j: &serde_json::Map<String, Value>) -> Option<Self> {
        fn opt(j: &serde_json::Map<String, Value>, key: &str) -> Option<Option<String>> {
            match j.get(key) {
                None | Some(Value::Null) => Some(None),
                Some(Value::String(s)) => Some(Some(s.clone())),
                Some(_) => None,
            }
        }
        Some(Self {
            id: j.get("id")?.as_str()?.to_owned(),
            title: j.get("title")?.as_str()?.to_owned(),
            artist: opt(j, "artist")?,
            album: opt(j, "album")?,
            filename: opt(j, "filename")?,
        })
    }
}

#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct AlbumManifest {
    pub songs: Vec<ManifestSong>,
    /// Total songs the album should have according to the library, written
    /// at transfer or scan time.
    pub expected_song_count: Option<i64>,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct ManifestWire<'a> {
    version: u8,
    #[serde(skip_serializing_if = "Option::is_none")]
    expected_song_count: Option<i64>,
    songs: &'a [ManifestSong],
}

impl AlbumManifest {
    /// Dart `AlbumManifest.fromJson` over a decoded document: a non-object
    /// document or any mistyped field rejects the whole manifest, while a
    /// non-list `songs` yields an empty manifest.
    pub fn from_json(v: &Value) -> Option<Self> {
        let j = v.as_object()?;
        let Some(Value::Array(raw_songs)) = j.get("songs") else {
            return Some(Self::default());
        };
        let songs = raw_songs
            .iter()
            .filter_map(Value::as_object)
            .map(ManifestSong::from_json)
            .collect::<Option<Vec<_>>>()?;
        let expected_song_count = match j.get("expectedSongCount") {
            None | Some(Value::Null) => None,
            Some(Value::Number(n)) => Some(n.as_i64()?),
            Some(_) => return None,
        };
        Some(Self { songs, expected_song_count })
    }

    /// Parses manifest file bytes; `None` for anything Dart would reject.
    /// Dart's UTF-8 decoder drops a leading BOM.
    pub fn parse(bytes: &[u8]) -> Option<Self> {
        let text = std::str::from_utf8(bytes).ok()?;
        Self::from_json(&serde_json::from_str(text.strip_prefix('\u{FEFF}').unwrap_or(text)).ok()?)
    }

    /// Byte-identical to Dart's `JsonEncoder.withIndent('  ')` output.
    pub fn to_json_string(&self) -> String {
        let wire = ManifestWire { version: 1, expected_song_count: self.expected_song_count, songs: &self.songs };
        serde_json::to_string_pretty(&wire).expect("manifest serialisation is infallible")
    }

    /// Dart `addSongsToManifestAsync` merge: entries replace existing songs
    /// with the same id and are appended in order; an explicit count wins
    /// over the stored one.
    fn merged(existing: Option<&Self>, entries: Vec<ManifestSong>, expected_song_count: Option<i64>) -> Self {
        let new_ids: HashSet<&str> = entries.iter().map(|e| e.id.as_str()).collect();
        let mut songs: Vec<ManifestSong> = existing
            .map(|m| m.songs.iter().filter(|s| !new_ids.contains(s.id.as_str())).cloned().collect())
            .unwrap_or_default();
        songs.extend(entries);
        Self { songs, expected_song_count: expected_song_count.or(existing.and_then(|m| m.expected_song_count)) }
    }
}

fn read_manifest_file(folder: &Path) -> Option<AlbumManifest> {
    AlbumManifest::parse(&fs::read(folder.join(MANIFEST_FILENAME)).ok()?)
}

fn write_manifest_file(folder: &Path, manifest: &AlbumManifest) -> io::Result<()> {
    write_atomic(&folder.join(MANIFEST_FILENAME), manifest.to_json_string().as_bytes())
}

struct LruState<V> {
    lru: LruCache<PathBuf, V>,
    /// Bumped by every put/clear; a disk load only populates the cache if no
    /// write landed while it ran, so a slow read can't overwrite a newer value.
    generation: u64,
}

struct PathCache<V> {
    state: Mutex<LruState<V>>,
}

impl<V: Clone> PathCache<V> {
    fn new(cap: usize) -> Self {
        let lru = LruCache::new(NonZeroUsize::new(cap).expect("cache cap is non-zero"));
        Self { state: Mutex::new(LruState { lru, generation: 0 }) }
    }

    /// Cached value, else `load()` run without holding the lock (disk reads
    /// on a slow device must not stall other lookups).
    fn get_or_load(&self, key: &Path, load: impl FnOnce() -> V) -> V {
        let generation = {
            let mut s = self.state.lock();
            if let Some(v) = s.lru.get(key) {
                return v.clone();
            }
            s.generation
        };
        let loaded = load();
        let mut s = self.state.lock();
        if let Some(v) = s.lru.get(key) {
            return v.clone();
        }
        if s.generation == generation {
            s.lru.put(key.to_path_buf(), loaded.clone());
        }
        loaded
    }

    fn put(&self, key: &Path, value: V) {
        let mut s = self.state.lock();
        s.generation += 1;
        s.lru.put(key.to_path_buf(), value);
    }

    fn clear(&self) {
        let mut s = self.state.lock();
        s.generation += 1;
        s.lru.clear();
    }
}

/// LRU caches of parsed manifests and album-folder existence, keyed by
/// absolute folder path. Hit by every song row and album card on every
/// transfer-status change, so negative results are cached too; writers
/// update the cache together with disk.
pub struct DeviceCaches {
    manifests: PathCache<Option<Arc<AlbumManifest>>>,
    folders: PathCache<bool>,
}

static GLOBAL_CACHES: LazyLock<Arc<DeviceCaches>> = LazyLock::new(Arc::default);

impl Default for DeviceCaches {
    fn default() -> Self {
        Self::new()
    }
}

impl DeviceCaches {
    pub fn new() -> Self {
        Self { manifests: PathCache::new(MANIFEST_CACHE_CAP), folders: PathCache::new(FOLDER_EXISTS_CACHE_CAP) }
    }

    /// The process-wide caches used by the free functions in this module.
    pub fn global() -> &'static Arc<Self> {
        &GLOBAL_CACHES
    }

    /// Cached manifest of `folder`; `None` when absent or unreadable.
    pub fn read_manifest(&self, folder: &Path) -> Option<Arc<AlbumManifest>> {
        self.manifests.get_or_load(folder, || read_manifest_file(folder).map(Arc::new))
    }

    /// Cached `folder.is_dir()`; a manifest write marks the folder existing.
    pub fn folder_exists(&self, folder: &Path) -> bool {
        self.folders.get_or_load(folder, || folder.is_dir())
    }

    /// Call on device plug-out/change so a new device mounted at the same
    /// path never sees the previous one's entries.
    pub fn clear(&self) {
        self.manifests.clear();
        self.folders.clear();
    }

    pub fn write_manifest(&self, folder: &Path, manifest: AlbumManifest) -> io::Result<()> {
        write_manifest_file(folder, &manifest)?;
        self.manifests.put(folder, Some(Arc::new(manifest)));
        self.folders.put(folder, true);
        Ok(())
    }

    /// Reads the manifest from disk once, replaces existing entries by id,
    /// appends every entry and writes once. No-op for empty `entries`.
    /// Concurrent callers on one folder must be serialised ([`ManifestWriter`]).
    pub fn add_songs_to_manifest(
        &self,
        folder: &Path,
        entries: Vec<ManifestSong>,
        expected_song_count: Option<i64>,
    ) -> io::Result<()> {
        if entries.is_empty() {
            return Ok(());
        }
        let existing = read_manifest_file(folder);
        self.write_manifest(folder, AlbumManifest::merged(existing.as_ref(), entries, expected_song_count))
    }
}

pub fn read_manifest(folder: impl AsRef<Path>) -> Option<Arc<AlbumManifest>> {
    DeviceCaches::global().read_manifest(folder.as_ref())
}

pub fn folder_exists_cached(folder: impl AsRef<Path>) -> bool {
    DeviceCaches::global().folder_exists(folder.as_ref())
}

pub fn clear_device_caches() {
    DeviceCaches::global().clear();
}

pub fn write_manifest(folder: impl AsRef<Path>, manifest: AlbumManifest) -> io::Result<()> {
    DeviceCaches::global().write_manifest(folder.as_ref(), manifest)
}

pub fn add_songs_to_manifest(
    folder: impl AsRef<Path>,
    entries: Vec<ManifestSong>,
    expected_song_count: Option<i64>,
) -> io::Result<()> {
    DeviceCaches::global().add_songs_to_manifest(folder.as_ref(), entries, expected_song_count)
}

type FolderLocks = Mutex<HashMap<PathBuf, (Arc<tokio::sync::Mutex<()>>, usize)>>;

/// A registered interest in one folder's lock; the map entry is removed when
/// the last lease drops, however its holder ended (done, cancelled, panicked).
struct FolderLease {
    locks: Arc<FolderLocks>,
    folder: PathBuf,
    lock: Arc<tokio::sync::Mutex<()>>,
}

impl FolderLease {
    fn new(locks: &Arc<FolderLocks>, folder: PathBuf) -> Self {
        let lock = {
            let mut map = locks.lock();
            let (lock, users) = map.entry(folder.clone()).or_default();
            *users += 1;
            lock.clone()
        };
        Self { locks: locks.clone(), folder, lock }
    }
}

impl Drop for FolderLease {
    fn drop(&mut self) {
        let mut map = self.locks.lock();
        if let Some((_, users)) = map.get_mut(&self.folder) {
            *users -= 1;
            if *users == 0 {
                map.remove(&self.folder);
            }
        }
    }
}

/// Serialises manifest appends per folder (concurrent downloads finishing in
/// one album) while different folders proceed in parallel. File work runs on
/// the blocking pool and keeps the folder locked until it finishes, even if
/// the awaiting future is dropped.
pub struct ManifestWriter {
    caches: Arc<DeviceCaches>,
    locks: Arc<FolderLocks>,
}

impl Default for ManifestWriter {
    fn default() -> Self {
        Self::new()
    }
}

impl ManifestWriter {
    pub fn new() -> Self {
        Self::with_caches(DeviceCaches::global().clone())
    }

    pub fn with_caches(caches: Arc<DeviceCaches>) -> Self {
        Self { caches, locks: Arc::default() }
    }

    pub async fn add_songs(
        &self,
        folder: PathBuf,
        entries: Vec<ManifestSong>,
        expected_song_count: Option<i64>,
    ) -> io::Result<()> {
        let caches = self.caches.clone();
        self.run_locked(folder, move |folder| caches.add_songs_to_manifest(folder, entries, expected_song_count)).await
    }

    /// Runs `work` on the blocking pool while holding `folder`'s lock.
    async fn run_locked<T: Send + 'static>(
        &self,
        folder: PathBuf,
        work: impl FnOnce(&Path) -> io::Result<T> + Send + 'static,
    ) -> io::Result<T> {
        let lease = FolderLease::new(&self.locks, folder);
        let guard = lease.lock.clone().lock_owned().await;
        tokio::task::spawn_blocking(move || {
            let res = work(&lease.folder);
            drop(guard);
            drop(lease);
            res
        })
        .await
        .unwrap_or_else(|e| Err(io::Error::other(e)))
    }
}

fn count_audio_files(folder: &Path) -> io::Result<usize> {
    let mut n = 0;
    for entry in fs::read_dir(folder)? {
        let entry = entry?;
        let path = entry.path();
        // Directory listings follow links in Dart, so a symlinked file counts.
        let is_file = match entry.file_type()? {
            t if t.is_symlink() => path.is_file(),
            t => t.is_file(),
        };
        if is_file && is_audio_file(&path) {
            n += 1;
        }
    }
    Ok(n)
}

fn album_folder(album_artist: Option<&str>, album_name: &str, year: Option<i32>, settings: &DeviceSettings) -> Option<PathBuf> {
    dapper_paths::build_album_folder(album_artist, album_name, year, settings).map(PathBuf::from)
}

/// Sync status of an album on the device. Prefers the manifest (and its
/// `expectedSongCount` over `song_count`); without one, counts audio files.
pub fn album_sync_on_device(
    album_artist: Option<&str>,
    album_name: &str,
    year: Option<i32>,
    song_count: i64,
    settings: &DeviceSettings,
) -> AlbumSyncStatus {
    let Some(folder) = album_folder(album_artist, album_name, year, settings) else {
        return AlbumSyncStatus::Absent;
    };
    if !folder_exists_cached(&folder) {
        return AlbumSyncStatus::Absent;
    }
    if let Some(m) = read_manifest(&folder) {
        let count = m.songs.len() as i64;
        if count == 0 {
            return AlbumSyncStatus::Absent;
        }
        let expected = m.expected_song_count.unwrap_or(song_count);
        return if expected > 0 && count >= expected { AlbumSyncStatus::Full } else { AlbumSyncStatus::Partial };
    }
    // Slow path for pre-manifest albums or externally managed folders.
    let files = count_audio_files(&folder).unwrap_or(0) as i64;
    if files == 0 {
        AlbumSyncStatus::Absent
    } else if song_count > 0 && files >= song_count {
        AlbumSyncStatus::Full
    } else {
        AlbumSyncStatus::Partial
    }
}

/// True if the album folder exists and holds at least one audio file.
pub fn album_exists_on_device(
    album_artist: Option<&str>,
    album_name: &str,
    year: Option<i32>,
    settings: &DeviceSettings,
) -> bool {
    let Some(folder) = album_folder(album_artist, album_name, year, settings) else { return false };
    if !folder_exists_cached(&folder) {
        return false;
    }
    match read_manifest(&folder) {
        Some(m) => !m.songs.is_empty(),
        None => count_audio_files(&folder).is_ok_and(|n| n > 0),
    }
}

/// True if the song's file is at its expected path. Bypasses the manifest so
/// a stale entry can't make the transfer engine skip a download.
pub fn song_file_exists_on_device(song: &Song, settings: &DeviceSettings) -> bool {
    Path::new(&dapper_paths::build_song_path(song, settings)).is_file()
}

/// True if the song is on the device: by id in the album manifest when there
/// is one (robust to filename changes), else by its expected path.
pub fn song_exists_on_device(song: &Song, settings: &DeviceSettings) -> bool {
    let folder = album_folder(
        song.album_artist.as_deref().or(song.artist.as_deref()),
        song.album.as_deref().unwrap_or("Unknown Album"),
        song.year,
        settings,
    );
    if let Some(m) = folder.and_then(read_manifest) {
        return m.songs.iter().any(|s| s.id == song.id);
    }
    song_file_exists_on_device(song, settings)
}

/// True if the artist folder exists. Always false for flat and custom
/// layouts, where no path component reliably names the artist.
pub fn artist_folder_exists_on_device(artist_name: &str, settings: &DeviceSettings) -> bool {
    if matches!(settings.folder_structure, FolderStructure::Flat | FolderStructure::Custom) {
        return false;
    }
    Path::new(&dapper_paths::artist_folder(settings, artist_name)).is_dir()
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    fn song(id: &str, title: &str) -> Song {
        Song { id: id.into(), title: title.into(), album: Some("Alb".into()), artist: Some("Art".into()), ..Default::default() }
    }

    fn ms(id: &str, title: &str) -> ManifestSong {
        ManifestSong { id: id.into(), title: title.into(), artist: None, album: None, filename: None }
    }

    fn entry(s: &Song, filename: Option<&str>) -> Vec<ManifestSong> {
        vec![ManifestSong::for_song(s, filename.map(Into::into))]
    }

    #[test]
    fn audio_extensions() {
        for p in ["/x/foo.mp3", "/x/foo.MP3", "/x/foo.flac", "/x/foo.opus"] {
            assert!(is_audio_file(Path::new(p)), "{p}");
        }
        for p in ["/x/._foo.mp3", "/x/cover.jpg", "/x/notes.txt", "/x/no-ext", "/x/.mp3"] {
            assert!(!is_audio_file(Path::new(p)), "{p}");
        }
    }

    #[test]
    fn playlist_extensions() {
        assert!(is_playlist_file(Path::new("/x/p.m3u")));
        assert!(is_playlist_file(Path::new("/x/p.M3U8")));
        assert!(!is_playlist_file(Path::new("/x/foo.mp3")));
        assert!(!is_playlist_file(Path::new("/x/._a.m3u")));
    }

    #[test]
    fn json_round_trip() {
        let m = AlbumManifest {
            songs: vec![
                ManifestSong {
                    id: "s1".into(),
                    title: "T1".into(),
                    artist: Some("A".into()),
                    album: Some("B".into()),
                    filename: Some("01.mp3".into()),
                },
                ms("s2", "T2"),
            ],
            expected_song_count: Some(5),
        };
        let back = AlbumManifest::parse(m.to_json_string().as_bytes()).unwrap();
        assert_eq!(back, m);
    }

    #[test]
    fn dart_pretty_format() {
        let m = AlbumManifest {
            songs: vec![ManifestSong { artist: Some("Bjö\"rk\u{1}".into()), ..ms("s", "T") }],
            expected_song_count: Some(3),
        };
        assert_eq!(
            m.to_json_string(),
            "{\n  \"version\": 1,\n  \"expectedSongCount\": 3,\n  \"songs\": [\n    {\n      \"id\": \"s\",\n      \
             \"title\": \"T\",\n      \"artist\": \"Bjö\\\"rk\\u0001\"\n    }\n  ]\n}"
        );
        assert_eq!(AlbumManifest::default().to_json_string(), "{\n  \"version\": 1,\n  \"songs\": []\n}");
    }

    #[test]
    fn omits_null_optionals() {
        let v: Value = serde_json::from_str(&AlbumManifest { songs: vec![ms("s", "T")], expected_song_count: None }.to_json_string()).unwrap();
        let s = v["songs"][0].as_object().unwrap();
        assert!(!s.contains_key("artist") && !s.contains_key("album") && !s.contains_key("filename"));
        assert!(!v.as_object().unwrap().contains_key("expectedSongCount"));
    }

    #[test]
    fn tolerant_parsing_like_dart() {
        assert_eq!(AlbumManifest::from_json(&json!({"version": 1, "songs": "not-a-list"})), Some(AlbumManifest::default()));
        // A non-list `songs` drops the count as well.
        assert_eq!(AlbumManifest::from_json(&json!({"songs": 1, "expectedSongCount": 4})), Some(AlbumManifest::default()));
        // Non-object entries are skipped.
        let m = AlbumManifest::from_json(&json!({"songs": [1, "x", {"id": "a", "title": "A", "artist": null}]})).unwrap();
        assert_eq!(m.songs, vec![ms("a", "A")]);
        // Mistyped fields reject the whole manifest.
        assert_eq!(AlbumManifest::from_json(&json!({"songs": [{"id": 1, "title": "A"}]})), None);
        assert_eq!(AlbumManifest::from_json(&json!({"songs": [{"id": "a"}]})), None);
        assert_eq!(AlbumManifest::from_json(&json!({"songs": [{"id": "a", "title": "A", "album": 3}]})), None);
        assert_eq!(AlbumManifest::from_json(&json!({"songs": [], "expectedSongCount": 2.5})), None);
        assert_eq!(AlbumManifest::from_json(&json!({"songs": [], "expectedSongCount": "2"})), None);
        assert_eq!(AlbumManifest::from_json(&json!([])), None);
        assert_eq!(AlbumManifest::parse(b"\xff{}"), None);
    }

    #[test]
    fn read_missing_malformed_and_valid() {
        let c = DeviceCaches::new();
        let a = tempfile::tempdir().unwrap();
        assert!(c.read_manifest(a.path()).is_none());
        let b = tempfile::tempdir().unwrap();
        fs::write(b.path().join(MANIFEST_FILENAME), "{not valid json").unwrap();
        assert!(c.read_manifest(b.path()).is_none());
        let d = tempfile::tempdir().unwrap();
        fs::write(d.path().join(MANIFEST_FILENAME), json!({"version": 1, "songs": [{"id": "x", "title": "X"}]}).to_string()).unwrap();
        assert_eq!(c.read_manifest(d.path()).unwrap().songs[0].id, "x");
    }

    #[test]
    fn write_overwrites_atomically() {
        let c = DeviceCaches::new();
        let t = tempfile::tempdir().unwrap();
        c.write_manifest(t.path(), AlbumManifest { songs: vec![ms("a", "A")], expected_song_count: None }).unwrap();
        let raw: Value = serde_json::from_slice(&fs::read(t.path().join(MANIFEST_FILENAME)).unwrap()).unwrap();
        assert_eq!(raw["version"], 1);
        c.write_manifest(t.path(), AlbumManifest { songs: vec![ms("b", "B")], expected_song_count: None }).unwrap();
        c.clear();
        assert_eq!(c.read_manifest(t.path()).unwrap().songs[0].id, "b");
        assert!(!t.path().join(".dapper.json.tmp").exists());
    }

    #[test]
    fn add_creates_replaces_appends() {
        let c = DeviceCaches::new();
        let t = tempfile::tempdir().unwrap();
        c.add_songs_to_manifest(t.path(), entry(&song("s1", "old"), Some("old.mp3")), Some(3)).unwrap();
        let m = c.read_manifest(t.path()).unwrap();
        assert_eq!((m.songs.len(), m.songs[0].filename.as_deref(), m.expected_song_count), (1, Some("old.mp3"), Some(3)));
        assert_eq!(m.songs[0].artist.as_deref(), Some("Art"));

        c.add_songs_to_manifest(t.path(), entry(&song("s1", "new"), Some("new.mp3")), None).unwrap();
        let m = c.read_manifest(t.path()).unwrap();
        assert_eq!(m.songs.len(), 1);
        assert_eq!(m.songs[0].title, "new");
        assert_eq!(m.songs[0].filename.as_deref(), Some("new.mp3"));
        assert_eq!(m.expected_song_count, Some(3), "count kept when not overridden");

        for id in ["b", "c"] {
            c.add_songs_to_manifest(t.path(), entry(&song(id, "x"), None), None).unwrap();
        }
        c.add_songs_to_manifest(t.path(), entry(&song("d", "x"), None), Some(99)).unwrap();
        let m = c.read_manifest(t.path()).unwrap();
        assert_eq!(m.songs.iter().map(|s| s.id.as_str()).collect::<Vec<_>>(), ["s1", "b", "c", "d"]);
        assert_eq!(m.expected_song_count, Some(99));
    }

    #[test]
    fn add_prefers_album_artist_and_batches() {
        let c = DeviceCaches::new();
        let t = tempfile::tempdir().unwrap();
        let a = Song { album_artist: Some("AA".into()), ..song("a", "A") };
        c.add_songs_to_manifest(t.path(), vec![ManifestSong::for_song(&song("x", "X"), None)], None).unwrap();
        c.add_songs_to_manifest(
            t.path(),
            vec![ManifestSong::for_song(&a, Some("a.flac".into())), ManifestSong::for_song(&song("x", "X2"), None)],
            Some(2),
        )
        .unwrap();
        let m = c.read_manifest(t.path()).unwrap();
        assert_eq!(m.songs.iter().map(|s| (s.id.as_str(), s.title.as_str())).collect::<Vec<_>>(), [("a", "A"), ("x", "X2")]);
        assert_eq!(m.songs[0].artist.as_deref(), Some("AA"));
        c.add_songs_to_manifest(t.path(), Vec::new(), Some(7)).unwrap();
        assert_eq!(c.read_manifest(t.path()).unwrap().expected_song_count, Some(2));
    }

    #[tokio::test(flavor = "multi_thread", worker_threads = 4)]
    async fn writer_serialises_concurrent_appends() {
        let caches = Arc::new(DeviceCaches::new());
        let writer = Arc::new(ManifestWriter::with_caches(caches.clone()));
        let t = tempfile::tempdir().unwrap();
        let other = tempfile::tempdir().unwrap();
        let mut handles = Vec::new();
        for i in 0..20 {
            let w = writer.clone();
            let folder = if i % 2 == 0 { t.path() } else { other.path() }.to_path_buf();
            handles.push(tokio::spawn(async move {
                w.add_songs(folder, entry(&song(&format!("s{i}"), "x"), None), None).await
            }));
        }
        for h in handles {
            h.await.unwrap().unwrap();
        }
        caches.clear();
        assert_eq!(caches.read_manifest(t.path()).unwrap().songs.len(), 10);
        assert_eq!(caches.read_manifest(other.path()).unwrap().songs.len(), 10);
        assert!(writer.locks.lock().is_empty());
    }

    #[tokio::test(flavor = "multi_thread", worker_threads = 4)]
    async fn cancelled_writer_keeps_folder_locked_until_its_work_ends() {
        let writer = Arc::new(ManifestWriter::with_caches(Arc::new(DeviceCaches::new())));
        let folder = PathBuf::from("/virtual/album");
        let (started_tx, started_rx) = tokio::sync::oneshot::channel();
        let (release_tx, release_rx) = std::sync::mpsc::channel::<()>();
        let first = tokio::spawn({
            let w = writer.clone();
            let folder = folder.clone();
            async move {
                w.run_locked(folder, move |_| {
                    started_tx.send(()).unwrap();
                    release_rx.recv().unwrap();
                    Ok(())
                })
                .await
            }
        });
        started_rx.await.unwrap();
        first.abort();
        assert!(first.await.unwrap_err().is_cancelled());

        let second_ran = Arc::new(std::sync::atomic::AtomicBool::new(false));
        let second = tokio::spawn({
            let (w, folder, ran) = (writer.clone(), folder.clone(), second_ran.clone());
            async move {
                w.run_locked(folder, move |_| {
                    ran.store(true, std::sync::atomic::Ordering::SeqCst);
                    Ok(())
                })
                .await
            }
        });
        tokio::time::sleep(std::time::Duration::from_millis(100)).await;
        assert!(!second_ran.load(std::sync::atomic::Ordering::SeqCst), "second writer must wait for the first's work");
        release_tx.send(()).unwrap();
        second.await.unwrap().unwrap();
        assert!(second_ran.load(std::sync::atomic::Ordering::SeqCst));
        assert!(writer.locks.lock().is_empty());
    }

    #[tokio::test]
    async fn writer_cancelled_while_queued_releases_its_map_entry() {
        let writer = ManifestWriter::with_caches(Arc::new(DeviceCaches::new()));
        let folder = PathBuf::from("/virtual/album");
        let holder = FolderLease::new(&writer.locks, folder.clone());
        let guard = holder.lock.clone().lock_owned().await;
        {
            let queued = writer.run_locked(folder.clone(), |_| Ok(()));
            tokio::pin!(queued);
            assert!(poll_once(queued.as_mut()).await.is_none());
            assert_eq!(writer.locks.lock()[&folder].1, 2);
        }
        assert_eq!(writer.locks.lock()[&folder].1, 1);
        drop(guard);
        drop(holder);
        assert!(writer.locks.lock().is_empty());
    }

    async fn poll_once<F: Future + Unpin>(mut f: F) -> Option<F::Output> {
        use std::task::Poll;
        std::future::poll_fn(|cx| {
            Poll::Ready(match std::pin::Pin::new(&mut f).poll(cx) {
                Poll::Ready(v) => Some(v),
                Poll::Pending => None,
            })
        })
        .await
    }

    #[test]
    fn load_racing_a_write_never_caches_stale_data() {
        let cache: PathCache<&str> = PathCache::new(4);
        let key = Path::new("/a");
        // A write lands while the disk read is in flight.
        let got = cache.get_or_load(key, || {
            cache.put(key, "new");
            "old"
        });
        assert_eq!(got, "new");
        assert_eq!(cache.get_or_load(key, || "disk"), "new");

        // The written entry is gone again (eviction/clear) before the load ends.
        let other = Path::new("/b");
        let got = cache.get_or_load(other, || {
            cache.put(other, "new");
            cache.clear();
            "old"
        });
        assert_eq!(got, "old");
        assert_eq!(cache.get_or_load(other, || "reloaded"), "reloaded");
    }

    #[test]
    fn concurrent_reads_and_writes_end_consistent() {
        let c = Arc::new(DeviceCaches::new());
        let t = tempfile::tempdir().unwrap();
        let folder = t.path().to_path_buf();
        std::thread::scope(|s| {
            for _ in 0..4 {
                s.spawn(|| {
                    for _ in 0..200 {
                        c.read_manifest(&folder);
                        c.folder_exists(&folder);
                    }
                });
            }
            s.spawn(|| {
                for i in 0..50 {
                    c.write_manifest(&folder, AlbumManifest { songs: vec![ms(&i.to_string(), "t")], expected_song_count: None })
                        .unwrap();
                }
            });
        });
        assert_eq!(c.read_manifest(&folder).unwrap().songs[0].id, "49");
        assert!(c.folder_exists(&folder));
    }

    #[test]
    fn cache_serves_stale_until_cleared() {
        let c = DeviceCaches::new();
        let t = tempfile::tempdir().unwrap();
        let file = t.path().join(MANIFEST_FILENAME);
        let b = json!({"version": 1, "songs": [{"id": "b", "title": "B"}]}).to_string();
        c.write_manifest(t.path(), AlbumManifest { songs: vec![ms("a", "A")], expected_song_count: None }).unwrap();
        fs::write(&file, &b).unwrap();
        assert_eq!(c.read_manifest(t.path()).unwrap().songs[0].id, "a");
        c.clear();
        assert_eq!(c.read_manifest(t.path()).unwrap().songs[0].id, "b");
    }

    #[test]
    fn add_is_visible_through_cache() {
        let c = DeviceCaches::new();
        let t = tempfile::tempdir().unwrap();
        assert!(c.read_manifest(t.path()).is_none());
        c.add_songs_to_manifest(t.path(), entry(&song("a", "A"), None), None).unwrap();
        assert_eq!(c.read_manifest(t.path()).unwrap().songs[0].id, "a");
    }

    #[test]
    fn caches_negative_lookup() {
        let c = DeviceCaches::new();
        let t = tempfile::tempdir().unwrap();
        assert!(c.read_manifest(t.path()).is_none());
        fs::write(t.path().join(MANIFEST_FILENAME), json!({"version": 1, "songs": [{"id": "a", "title": "A"}]}).to_string()).unwrap();
        assert!(c.read_manifest(t.path()).is_none());
        c.clear();
        assert_eq!(c.read_manifest(t.path()).unwrap().songs[0].id, "a");
    }

    #[test]
    fn folder_exists_is_cached() {
        let c = DeviceCaches::new();
        let t = tempfile::tempdir().unwrap();
        let dir = t.path().join("d");
        fs::create_dir(&dir).unwrap();
        assert!(c.folder_exists(&dir));
        fs::remove_dir(&dir).unwrap();
        assert!(c.folder_exists(&dir));
        assert!(!c.folder_exists(&t.path().join("does-not-exist")));
        let sub = t.path().join("sub");
        fs::create_dir(&sub).unwrap();
        c.write_manifest(&sub, AlbumManifest { songs: vec![ms("s", "T")], expected_song_count: None }).unwrap();
        fs::remove_dir_all(&sub).unwrap();
        assert!(c.folder_exists(&sub), "write marks the folder existing");
    }

    #[test]
    fn lru_evicts_least_recent() {
        let c = DeviceCaches::new();
        let t = tempfile::tempdir().unwrap();
        let first = t.path().join("0");
        assert!(!c.folder_exists(&first));
        for i in 1..FOLDER_EXISTS_CACHE_CAP {
            c.folder_exists(&t.path().join(i.to_string()));
        }
        // Promote `first`, then overflow by one: `1` is evicted instead.
        assert!(!c.folder_exists(&first));
        c.folder_exists(&t.path().join("overflow"));
        let state = c.folders.state.lock();
        let folders = &state.lru;
        assert!(folders.contains(&first));
        assert!(!folders.contains(&t.path().join("1")));
        assert_eq!(folders.len(), FOLDER_EXISTS_CACHE_CAP);
    }

    fn settings(root: &Path) -> DeviceSettings {
        DeviceSettings::new(root.to_string_lossy())
    }

    #[test]
    fn album_sync_absent_without_folder() {
        let t = tempfile::tempdir().unwrap();
        assert_eq!(album_sync_on_device(Some("Some Artist"), "Some Album", None, 10, &settings(t.path())), AlbumSyncStatus::Absent);
        assert!(!album_exists_on_device(Some("Some Artist"), "Some Album", None, &settings(t.path())));
    }

    fn album_dir(s: &DeviceSettings) -> PathBuf {
        let folder = album_folder(Some("A"), "B", None, s).unwrap();
        fs::create_dir_all(&folder).unwrap();
        folder
    }

    #[test]
    fn album_sync_full_from_manifest() {
        let t = tempfile::tempdir().unwrap();
        let s = settings(t.path());
        let folder = album_dir(&s);
        let songs = (0..3).map(|i| ms(&format!("s{i}"), "t")).collect();
        write_manifest(&folder, AlbumManifest { songs, expected_song_count: Some(3) }).unwrap();
        assert_eq!(album_sync_on_device(Some("A"), "B", None, 3, &s), AlbumSyncStatus::Full);
        assert!(album_exists_on_device(Some("A"), "B", None, &s));
    }

    #[test]
    fn album_sync_partial_below_expected() {
        let t = tempfile::tempdir().unwrap();
        let s = settings(t.path());
        let folder = album_dir(&s);
        write_manifest(&folder, AlbumManifest { songs: vec![ms("s1", "t1")], expected_song_count: Some(5) }).unwrap();
        assert_eq!(album_sync_on_device(Some("A"), "B", None, 5, &s), AlbumSyncStatus::Partial);
    }

    #[test]
    fn album_sync_empty_manifest_is_absent() {
        let t = tempfile::tempdir().unwrap();
        let s = settings(t.path());
        let folder = album_dir(&s);
        fs::write(folder.join("a.mp3"), "").unwrap();
        write_manifest(&folder, AlbumManifest::default()).unwrap();
        assert_eq!(album_sync_on_device(Some("A"), "B", None, 1, &s), AlbumSyncStatus::Absent);
        assert!(!album_exists_on_device(Some("A"), "B", None, &s));
    }

    #[test]
    fn album_sync_counts_files_without_manifest() {
        let t = tempfile::tempdir().unwrap();
        let s = settings(t.path());
        let folder = album_dir(&s);
        fs::write(folder.join("a.mp3"), "").unwrap();
        fs::write(folder.join("b.flac"), "").unwrap();
        assert_eq!(album_sync_on_device(Some("A"), "B", None, 2, &s), AlbumSyncStatus::Full);
        assert_eq!(album_sync_on_device(Some("A"), "B", None, 3, &s), AlbumSyncStatus::Partial);
        assert_eq!(album_sync_on_device(Some("A"), "B", None, 0, &s), AlbumSyncStatus::Partial);
    }

    #[test]
    fn album_sync_ignores_sidecars() {
        let t = tempfile::tempdir().unwrap();
        let s = settings(t.path());
        let folder = album_dir(&s);
        fs::write(folder.join("a.mp3"), "").unwrap();
        fs::write(folder.join("._a.mp3"), "").unwrap();
        assert_eq!(album_sync_on_device(Some("A"), "B", None, 1, &s), AlbumSyncStatus::Full);
    }

    #[test]
    fn song_existence_prefers_manifest() {
        let t = tempfile::tempdir().unwrap();
        let s = settings(t.path());
        let a = Song { album_artist: Some("A".into()), album: Some("B".into()), ..song("a", "One") };
        let b = Song { id: "b".into(), ..a.clone() };
        assert!(!song_exists_on_device(&a, &s));
        assert!(!song_file_exists_on_device(&a, &s));

        let path = PathBuf::from(dapper_paths::build_song_path(&a, &s));
        fs::create_dir_all(path.parent().unwrap()).unwrap();
        fs::write(&path, "x").unwrap();
        assert!(song_file_exists_on_device(&a, &s));
        // `a`'s folder was cached as manifest-less above, so the path decides.
        assert!(song_exists_on_device(&a, &s));
        // With a manifest only the listed ids count, whatever is on disk.
        write_manifest(path.parent().unwrap(), AlbumManifest { songs: vec![ms("b", "x")], expected_song_count: None }).unwrap();
        assert!(!song_exists_on_device(&a, &s));
        assert!(song_exists_on_device(&b, &s));
    }

    #[test]
    fn artist_folder_existence() {
        let t = tempfile::tempdir().unwrap();
        let mut s = settings(t.path());
        assert!(!artist_folder_exists_on_device("AC/DC", &s));
        fs::create_dir(PathBuf::from(dapper_paths::artist_folder(&s, "AC/DC"))).unwrap();
        assert!(artist_folder_exists_on_device("AC/DC", &s));
        s.folder_structure = FolderStructure::Flat;
        assert!(!artist_folder_exists_on_device("AC/DC", &s));
        s.folder_structure = FolderStructure::Custom;
        assert!(!artist_folder_exists_on_device("AC/DC", &s));
    }
}
