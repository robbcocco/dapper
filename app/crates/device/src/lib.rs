//! On-device file formats and maintenance: manifests, M3U, scrobbler log, FLAC clean/shrink, scan, prune, tag-clean, sync status, scrobble import.

mod atomic_file;
mod browse;
mod clean_cache;
mod flac;
mod m3u;
mod manifest;
mod prune;
mod scan;
mod scrobble_import;
mod scrobbler_log;
mod sync_plan;
mod sync_status;
mod tag_clean;
#[cfg(test)]
mod test_support;

pub use clean_cache::{CLEAN_CACHE_FILENAME, CleanCache, clean_cache_key, mtime_ms};
pub use flac::{
    DEFAULT_PICTURE_JPEG_QUALITY, DEFAULT_PICTURE_MAX_EDGE, FlacCleanOptions, FlacCleanOutcome, clean_flac_bytes,
    clean_flac_copy, clean_flac_file, is_flac_path, sanitize_flac_tags, shrink_flac_embedded_picture,
};
pub use m3u::{playlist_exists_on_device, render_m3u, write_playlist_m3u};
pub use manifest::{
    AUDIO_EXTENSIONS, AlbumManifest, DeviceCaches, MANIFEST_FILENAME, ManifestSong, ManifestWriter, PLAYLIST_EXTENSIONS,
    add_songs_to_manifest, album_exists_on_device, album_sync_on_device, artist_folder_exists_on_device,
    clear_device_caches, folder_exists_cached, is_audio_file, is_playlist_file, read_manifest,
    song_exists_on_device, song_file_exists_on_device, write_manifest,
};
pub use scrobbler_log::{
    ScrobblerLogEntry, find_scrobbler_log, parse_scrobbler_log, read_scrobbler_log, rewrite_scrobbler_log,
    rewritten_scrobbler_log,
};
pub use browse::{
    BROWSER_AUDIO_EXTENSIONS, BROWSER_PLAYLIST_EXTENSIONS, DeviceEntry, DeviceEntryKind, delete_files,
    list_device_dir, list_device_folders,
};
pub use prune::{PruneResult, prune_device, prune_folders};
pub use scan::{DeviceDuplicate, FileDuplicate, Progress, ScanReport, scan_device};
pub use scrobble_import::{SCROBBLE_SUBMIT_CONCURRENCY, ScrobbleImportResult, import_scrobbles};
pub use sync_plan::{LibrarySyncPlan, build_library_sync_plan};
pub use sync_status::{album_sync_statuses, artist_sync_statuses, scan_album_folders, song_presence};
pub use tag_clean::{TAG_CLEAN_CONCURRENCY, TagSanitizeResult, sanitize_device_tags, sanitize_device_tags_blocking};
