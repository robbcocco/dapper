use std::collections::{HashMap, HashSet};
use std::fs::{self, File};
use std::io::{self, BufWriter, Read, Write};
use std::path::{Component, Path, PathBuf};
use std::time::{Duration, Instant};

use dapper_domain::{DeviceSettings, Song};
use tokio::sync::mpsc;
use tokio_util::sync::CancellationToken;

pub(crate) const PROGRESS_INTERVAL: Duration = Duration::from_millis(200);
const COPY_BUFFER: usize = 1024 * 1024;

pub(crate) fn staging_dir(support: &Path) -> PathBuf {
    support.join("staging")
}

pub(crate) fn tmp_dir(support: &Path) -> PathBuf {
    support.join("tmp")
}

/// `<support>/staging/<taskId><.ext of target>`.
pub(crate) fn staging_path_for(support: &Path, task_id: &str, target: &str) -> PathBuf {
    let ext = Path::new(target)
        .extension()
        .map(|e| format!(".{}", e.to_string_lossy()))
        .unwrap_or_default();
    staging_dir(support).join(format!("{task_id}{ext}"))
}

pub(crate) fn remove_quietly(path: &Path) {
    match fs::remove_file(path) {
        Ok(()) => {}
        Err(e) if e.kind() == io::ErrorKind::NotFound => {}
        Err(e) => tracing::debug!("could not remove {}: {e}", path.display()),
    }
}

/// Startup cleanup of zip temps and staged files left by a crash or forced
/// quit; their tasks were reset to queued and re-download.
pub(crate) fn clean_leftovers(support: &Path) {
    if let Ok(rd) = fs::read_dir(tmp_dir(support)) {
        for e in rd.flatten() {
            let name = e.file_name().to_string_lossy().into_owned();
            if e.path().is_file() && name.starts_with("zip_") && name.ends_with(".zip") {
                remove_quietly(&e.path());
            }
        }
    }
    if let Ok(rd) = fs::read_dir(staging_dir(support)) {
        for e in rd.flatten() {
            if e.path().is_file() {
                remove_quietly(&e.path());
            }
        }
    }
}

pub(crate) fn is_permission_error(e: &io::Error) -> bool {
    e.kind() == io::ErrorKind::PermissionDenied
        || matches!(e.raw_os_error(), Some(1 | 13))
        || is_permission_message(&e.to_string())
}

pub(crate) fn is_permission_message(msg: &str) -> bool {
    msg.contains("os error 1)")
        || msg.contains("os error 13)")
        || msg.contains("Operation not permitted")
        || msg.contains("Permission denied")
}

/// Task error text: `permission_denied` (the UI offers a fix) or the message.
pub(crate) fn failure_message(msg: String) -> String {
    if is_permission_message(&msg) {
        "permission_denied".into()
    } else {
        msg
    }
}

#[cfg(test)]
pub(crate) static DEVICE_WRITES: std::sync::LazyLock<parking_lot::Mutex<HashMap<PathBuf, u32>>> =
    std::sync::LazyLock::new(Default::default);

/// `create_dir_all` that also strips the macOS AppleDouble sidecar and
/// xattrs of every directory it creates (FAT32/exFAT would otherwise keep a
/// `._<dir>` next to each new artist/album folder).
pub(crate) fn create_dirs_clean(dir: &Path) -> io::Result<()> {
    let created: Vec<&Path> = dir
        .ancestors()
        .take_while(|d| !d.as_os_str().is_empty() && !d.exists())
        .collect();
    fs::create_dir_all(dir)?;
    for d in created.iter().rev() {
        dapper_platform::remove_macos_sidecar(d);
    }
    Ok(())
}

/// Streams `src` onto the device at `dst` (truncating), creating its folder,
/// then strips macOS sidecars. `on_progress(written, total)` fires at most
/// every 200 ms. This is the only device write per file.
pub(crate) fn copy_to_device(
    src: &Path,
    dst: &Path,
    mut on_progress: impl FnMut(i64, i64),
) -> io::Result<()> {
    if let Some(parent) = dst.parent() {
        create_dirs_clean(parent)?;
    }
    #[cfg(test)]
    {
        *DEVICE_WRITES.lock().entry(dst.to_path_buf()).or_default() += 1;
    }
    let total = fs::metadata(src)?.len() as i64;
    let mut reader = File::open(src)?;
    let mut writer = File::create(dst)?;
    let mut buf = vec![0u8; COPY_BUFFER];
    let mut written = 0i64;
    let mut last = Instant::now();
    loop {
        let n = reader.read(&mut buf)?;
        if n == 0 {
            break;
        }
        writer.write_all(&buf[..n])?;
        written += n as i64;
        if total > 0 && last.elapsed() >= PROGRESS_INTERVAL {
            last = Instant::now();
            on_progress(written.min(total), total);
        }
    }
    writer.flush()?;
    drop(writer);
    dapper_platform::remove_macos_sidecar(dst);
    Ok(())
}

/// Lexical `p.normalize`: resolves `.`/`..` without touching the disk.
fn normalize(path: &Path) -> PathBuf {
    let mut out = PathBuf::new();
    for c in path.components() {
        match c {
            Component::CurDir => {}
            Component::ParentDir => {
                if !out.pop() {
                    out.push("..");
                }
            }
            other => out.push(other.as_os_str()),
        }
    }
    out
}

/// `p.isWithin(parent, child)`: strictly inside, after normalisation.
fn is_within(parent: &Path, child: &Path) -> bool {
    let (p, c) = (normalize(parent), normalize(child));
    c != p && c.starts_with(&p)
}

fn parent_str(path: &str) -> String {
    Path::new(path)
        .parent()
        .map(|p| p.to_string_lossy().into_owned())
        .unwrap_or_default()
}

/// One outcome of [`extract_zip_entries`], in archive order.
pub(crate) enum Extracted {
    /// Entry streamed to a local staging file, ready for post-process + copy.
    Staged {
        song: usize,
        entry: String,
        staging: PathBuf,
        target: String,
        expected: Option<i64>,
    },
    /// Target already on device and overwrite is off: nothing to write.
    Existing {
        song: usize,
        target: String,
        expected: Option<i64>,
    },
    /// Matched entry that could not be staged.
    Failed { song: usize, reason: String },
}

/// Walks the album zip via its central directory (Navidrome's STORED entries
/// carry data descriptors, so the local headers have no sizes), matches each
/// entry to an expected song and streams it to `<staging>/<taskId>.<ext>`.
/// Never buffers a whole entry in memory. `send` blocks once the consumer is
/// `STAGED_AHEAD` behind, bounding staging disk use. Archive-level failures
/// are returned; per-entry ones are reported through `send`.
pub(crate) fn extract_zip_entries(
    zip_path: &Path,
    songs: &[Song],
    task_ids: &[String],
    settings: &DeviceSettings,
    support: &Path,
    out: mpsc::Sender<Extracted>,
    cancel: CancellationToken,
) -> Result<(), String> {
    let mut expected_per_folder: HashMap<String, i64> = HashMap::new();
    for s in songs {
        let artist = s.album_artist.as_deref().or(s.artist.as_deref());
        let album = s.album.as_deref().unwrap_or("Unknown Album");
        if let Some(folder) = dapper_paths::build_album_folder(artist, album, s.year, settings) {
            *expected_per_folder.entry(folder).or_default() += 1;
        }
    }
    let root = PathBuf::from(settings.resolved_music_root());
    let mut matched: HashSet<usize> = HashSet::new();
    let file = File::open(zip_path).map_err(|e| e.to_string())?;
    let mut archive = zip::ZipArchive::new(file).map_err(|e| e.to_string())?;
    fs::create_dir_all(staging_dir(support)).map_err(|e| e.to_string())?;

    for i in 0..archive.len() {
        if cancel.is_cancelled() {
            break;
        }
        let mut entry = archive.by_index(i).map_err(|e| e.to_string())?;
        if !entry.is_file() {
            continue;
        }
        let name = entry.name().map_err(|e| e.to_string())?.into_owned();
        if name.contains("..") {
            tracing::debug!("zip: parent traversal: {name}");
            continue;
        }
        let Some(song) = dapper_paths::match_zip_entry(&name, songs) else {
            tracing::debug!("zip: no match: {name}");
            continue;
        };
        let idx = songs
            .iter()
            .position(|s| std::ptr::eq(s, song))
            .unwrap_or_default();
        if matched.contains(&idx) {
            continue;
        }
        let target = dapper_paths::build_song_path(song, settings);
        if !is_within(&root, Path::new(&target)) {
            tracing::warn!("zip: escaped music root: {target}");
            continue;
        }
        let expected = expected_per_folder.get(&parent_str(&target)).copied();
        // Reserved now so a duplicate archive entry can't double-write.
        matched.insert(idx);

        let msg = if !settings.overwrite_existing && Path::new(&target).exists() {
            Extracted::Existing {
                song: idx,
                target,
                expected,
            }
        } else {
            let staging = staging_path_for(support, &task_ids[idx], &target);
            let staged = File::create(&staging).and_then(|f| {
                let mut w = BufWriter::with_capacity(COPY_BUFFER, f);
                io::copy(&mut entry, &mut w)?;
                w.flush()
            });
            match staged {
                Ok(()) => Extracted::Staged {
                    song: idx,
                    entry: name,
                    staging,
                    target,
                    expected,
                },
                Err(e) => {
                    remove_quietly(&staging);
                    matched.remove(&idx);
                    Extracted::Failed {
                        song: idx,
                        reason: format!("write failed for {name}: {e}"),
                    }
                }
            }
        };
        if let Err(mpsc::error::SendError(msg)) = out.blocking_send(msg) {
            if let Extracted::Staged { staging, .. } = msg {
                remove_quietly(&staging);
            }
            break;
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn within_root() {
        assert!(is_within(
            Path::new("/v/Music"),
            Path::new("/v/Music/a/b.mp3")
        ));
        assert!(!is_within(Path::new("/v/Music"), Path::new("/v/Music")));
        assert!(!is_within(
            Path::new("/v/Music"),
            Path::new("/v/Music/../x.mp3")
        ));
        assert!(!is_within(
            Path::new("/v/Music"),
            Path::new("/v/MusicX/a.mp3")
        ));
    }

    #[test]
    fn permission_mapping() {
        assert!(is_permission_error(&io::Error::from(
            io::ErrorKind::PermissionDenied
        )));
        assert!(is_permission_error(&io::Error::from_raw_os_error(1)));
        assert!(is_permission_error(&io::Error::from_raw_os_error(13)));
        assert!(!is_permission_error(&io::Error::from_raw_os_error(2)));
        assert_eq!(
            failure_message("Permission denied (os error 13)".into()),
            "permission_denied"
        );
        assert_eq!(failure_message("boom".into()), "boom");
    }

    #[cfg(target_os = "macos")]
    #[test]
    fn created_dirs_lose_their_sidecars() {
        let root = tempfile::tempdir().unwrap();
        let existing_sidecar = root.path().join("._keep");
        fs::create_dir(root.path().join("keep")).unwrap();
        fs::write(&existing_sidecar, b"s").unwrap();
        // Stand-ins for the AppleDouble files FAT32 gets for new folders.
        fs::write(root.path().join("keep/._Artist"), b"s").unwrap();
        let artist = root.path().join("keep/Artist");
        create_dirs_clean(&artist.join("Album")).unwrap();
        fs::write(artist.join("._Album"), b"s").unwrap();
        create_dirs_clean(&artist.join("Album")).unwrap();
        assert!(artist.join("Album").is_dir());
        assert!(!root.path().join("keep/._Artist").exists());
        // Pre-existing folders are left alone.
        assert!(existing_sidecar.exists());
        assert!(artist.join("._Album").exists());
    }

    #[test]
    fn staging_path_keeps_extension() {
        let p = staging_path_for(Path::new("/s"), "t1", "/v/A/B/01 - x.flac");
        assert_eq!(p, PathBuf::from("/s/staging/t1.flac"));
        assert_eq!(
            staging_path_for(Path::new("/s"), "t1", "/v/noext"),
            PathBuf::from("/s/staging/t1")
        );
    }
}
