//! Device file browser and folder picker listings (ports of
//! `device_file_browser.dart` / `device_folder_picker_dialog.dart`), plus
//! guarded file deletion. All functions are blocking; call them off the UI /
//! async executor.

use std::fs;
use std::io;
use std::path::{Path, PathBuf};

use serde::Serialize;

/// The browser's audio set (wider than the manifest's: `aif`, `wv`; no `wma`).
pub const BROWSER_AUDIO_EXTENSIONS: [&str; 13] =
    ["flac", "mp3", "aac", "m4a", "ogg", "opus", "wav", "aiff", "aif", "ape", "wv", "dsf", "dff"];
pub const BROWSER_PLAYLIST_EXTENSIONS: [&str; 2] = ["m3u", "m3u8"];

/// types.ts `DeviceEntryKind`.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub enum DeviceEntryKind {
    Dir,
    Audio,
    Playlist,
    Other,
}

/// types.ts `DeviceEntry`.
#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct DeviceEntry {
    pub name: String,
    pub path: String,
    pub is_dir: bool,
    /// File size; `None` for directories and links.
    pub size: Option<u64>,
    pub kind: DeviceEntryKind,
}

fn classify(name: &str) -> DeviceEntryKind {
    if name.starts_with("._") {
        return DeviceEntryKind::Other;
    }
    let ext = Path::new(name).extension().map(|e| e.to_string_lossy().to_lowercase()).unwrap_or_default();
    if BROWSER_AUDIO_EXTENSIONS.contains(&ext.as_str()) {
        DeviceEntryKind::Audio
    } else if BROWSER_PLAYLIST_EXTENSIONS.contains(&ext.as_str()) {
        DeviceEntryKind::Playlist
    } else {
        DeviceEntryKind::Other
    }
}

/// Children of `dir` for the file browser: dot-entries (including `._*`
/// sidecars) hidden, directories first, then case-insensitive by name. Links
/// are not followed (listed as `other`).
pub fn list_device_dir(dir: &Path) -> io::Result<Vec<DeviceEntry>> {
    let mut out = Vec::new();
    for e in fs::read_dir(dir)? {
        let e = e?;
        let name = e.file_name().to_string_lossy().into_owned();
        if name.starts_with('.') {
            continue;
        }
        let ft = e.file_type()?;
        let is_dir = ft.is_dir();
        let size = if ft.is_file() { e.metadata().ok().map(|m| m.len()) } else { None };
        let kind = if is_dir { DeviceEntryKind::Dir } else { classify(&name) };
        out.push(DeviceEntry { path: e.path().to_string_lossy().into_owned(), name, is_dir, size, kind });
    }
    out.sort_by(|a, b| b.is_dir.cmp(&a.is_dir).then_with(|| a.name.to_lowercase().cmp(&b.name.to_lowercase())));
    Ok(out)
}

/// Subfolders of `dir` for the folder picker: non-dot directories only,
/// case-insensitive by name.
pub fn list_device_folders(dir: &Path) -> io::Result<Vec<DeviceEntry>> {
    let mut v = list_device_dir(dir)?;
    v.retain(|e| e.is_dir);
    Ok(v)
}

/// Deletes regular files on the device. Every path is validated first: its
/// final component must itself be a regular file (a symlink is refused, so a
/// link on the device never deletes its target), and the path — with any
/// symlinked parent directories resolved — must canonicalise to somewhere
/// strictly under the canonical `device_path`. Otherwise nothing is deleted
/// and `InvalidInput` / `PermissionDenied` is returned. On macOS each file's
/// AppleDouble `._` sidecar is removed too. Returns the number deleted.
pub fn delete_files(device_path: &Path, paths: &[impl AsRef<Path>]) -> io::Result<usize> {
    let root = device_path.canonicalize()?;
    let targets = paths
        .iter()
        .map(|p| {
            let p = p.as_ref();
            if !fs::symlink_metadata(p)?.is_file() {
                return Err(io::Error::new(io::ErrorKind::InvalidInput, format!("{} is not a file", p.display())));
            }
            let c = p.canonicalize()?;
            if c == root || !c.starts_with(&root) {
                return Err(io::Error::new(
                    io::ErrorKind::PermissionDenied,
                    format!("{} is outside {}", p.display(), device_path.display()),
                ));
            }
            Ok(c)
        })
        .collect::<io::Result<Vec<PathBuf>>>()?;
    for t in &targets {
        dapper_platform::remove_macos_sidecar(t);
        fs::remove_file(t)?;
    }
    Ok(targets.len())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn lists_sorted_and_classified() {
        let t = tempfile::tempdir().unwrap();
        let r = t.path();
        fs::create_dir(r.join("zeta")).unwrap();
        fs::create_dir(r.join("Alpha")).unwrap();
        fs::create_dir(r.join(".hidden")).unwrap();
        fs::write(r.join("b.FLAC"), "abc").unwrap();
        fs::write(r.join("a.m3u8"), "").unwrap();
        fs::write(r.join("C.wv"), "").unwrap();
        fs::write(r.join("d.wma"), "").unwrap();
        fs::write(r.join("._b.FLAC"), "").unwrap();
        let v = list_device_dir(r).unwrap();
        let names: Vec<_> = v.iter().map(|e| e.name.as_str()).collect();
        assert_eq!(names, ["Alpha", "zeta", "a.m3u8", "b.FLAC", "C.wv", "d.wma"]);
        let kinds: Vec<_> = v.iter().map(|e| e.kind).collect();
        use DeviceEntryKind::*;
        assert_eq!(kinds, [Dir, Dir, Playlist, Audio, Audio, Other]);
        assert_eq!(v[3].size, Some(3));
        assert_eq!(v[0].size, None);
        let j = serde_json::to_value(&v[0]).unwrap();
        assert_eq!(j["isDir"], true);
        assert_eq!(j["kind"], "dir");

        let f: Vec<_> = list_device_folders(r).unwrap().into_iter().map(|e| e.name).collect();
        assert_eq!(f, ["Alpha", "zeta"]);
    }

    #[test]
    fn delete_guards() {
        let t = tempfile::tempdir().unwrap();
        let dev = t.path().join("dev");
        fs::create_dir_all(dev.join("A")).unwrap();
        let ok = dev.join("A").join("x.flac");
        fs::write(&ok, "x").unwrap();
        let outside = t.path().join("outside.flac");
        fs::write(&outside, "x").unwrap();

        let escape = dev.join("A").join("..").join("..").join("outside.flac");
        let e = delete_files(&dev, &[&ok, &escape]).unwrap_err();
        assert_eq!(e.kind(), io::ErrorKind::PermissionDenied);
        assert!(ok.exists() && outside.exists(), "nothing deleted on refusal");

        assert_eq!(delete_files(&dev, &[dev.join("A")]).unwrap_err().kind(), io::ErrorKind::InvalidInput);
        assert_eq!(delete_files(&dev, &[&dev]).unwrap_err().kind(), io::ErrorKind::InvalidInput);

        // A link on the device never deletes its target, inside or outside.
        #[cfg(unix)]
        {
            let out_link = dev.join("A").join("out.flac");
            let in_link = dev.join("A").join("in.flac");
            std::os::unix::fs::symlink(&outside, &out_link).unwrap();
            std::os::unix::fs::symlink(&ok, &in_link).unwrap();
            for l in [&out_link, &in_link] {
                assert_eq!(delete_files(&dev, &[l]).unwrap_err().kind(), io::ErrorKind::InvalidInput);
            }
            assert!(outside.exists() && ok.exists());
        }

        assert_eq!(delete_files(&dev, &[&ok]).unwrap(), 1);
        assert!(!ok.exists());
    }
}
