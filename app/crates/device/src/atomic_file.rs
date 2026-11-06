use std::fs;
use std::io::{self, Write};
use std::path::{Path, PathBuf};

/// `<path>.tmp`, the sibling written before the rename.
pub(crate) fn tmp_path(path: &Path) -> PathBuf {
    let mut name = path.file_name().unwrap_or_default().to_os_string();
    name.push(".tmp");
    path.with_file_name(name)
}

/// Replaces `path` with `contents` via a synced sibling temp file and a
/// rename (atomic on POSIX, NTFS and FAT32), so a crash or unplug mid-write
/// leaves the previous file intact. On macOS the AppleDouble `._` sidecar
/// the OS creates on FAT/exFAT is removed afterwards.
pub(crate) fn write_atomic(path: &Path, contents: &[u8]) -> io::Result<()> {
    let tmp = tmp_path(path);
    let res = (|| {
        let mut f = fs::File::create(&tmp)?;
        f.write_all(contents)?;
        f.sync_all()?;
        drop(f);
        fs::rename(&tmp, path)
    })();
    if res.is_err() {
        let _ = fs::remove_file(&tmp);
        return res;
    }
    dapper_platform::remove_macos_sidecar(path);
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn writes_atomically_without_leftovers() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join(".dapper.json");
        fs::write(&path, "old").unwrap();
        write_atomic(&path, b"new").unwrap();
        assert_eq!(fs::read(&path).unwrap(), b"new");
        assert!(!tmp_path(&path).exists());
    }

    #[cfg(target_os = "macos")]
    #[test]
    fn removes_appledouble_sidecar() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join(".dapper.json");
        let sidecar = dir.path().join("._.dapper.json");
        fs::write(&sidecar, "appledouble").unwrap();
        write_atomic(&path, b"{}").unwrap();
        assert!(!sidecar.exists());
        assert_eq!(fs::read(&path).unwrap(), b"{}");
    }
}
