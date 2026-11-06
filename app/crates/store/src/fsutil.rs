use std::fs::{self, OpenOptions};
use std::io::Write;
use std::path::{Path, PathBuf};

use dapper_domain::Result;

/// Fresh, unpredictable sibling of `path` (same directory, so rename is atomic).
fn unique_tmp_path(path: &Path) -> PathBuf {
    let name = path
        .file_name()
        .map(|n| n.to_string_lossy().into_owned())
        .unwrap_or_default();
    path.with_file_name(format!(".{name}.{}.tmp", uuid::Uuid::new_v4().simple()))
}

/// Exclusive create (`O_CREAT|O_EXCL`, which never follows a symlink);
/// `private` makes it owner-only (0600) from the moment it exists.
pub(crate) fn create_new_file(path: &Path, private: bool) -> std::io::Result<fs::File> {
    let mut opts = OpenOptions::new();
    opts.write(true).create_new(true);
    #[cfg(unix)]
    if private {
        use std::os::unix::fs::OpenOptionsExt;
        opts.mode(0o600);
    }
    #[cfg(not(unix))]
    let _ = private;
    opts.open(path)
}

/// Unique tmp + fsync + rename so readers never see a half-written file.
pub(crate) fn write_atomic(path: &Path, bytes: &[u8], private: bool) -> Result<()> {
    let tmp = unique_tmp_path(path);
    let res = (|| {
        let mut f = create_new_file(&tmp, private)?;
        f.write_all(bytes)?;
        f.sync_all()?;
        // Closed before rename: Windows refuses to rename an open file.
        drop(f);
        fs::rename(&tmp, path)
    })();
    if res.is_err() {
        let _ = fs::remove_file(&tmp);
    }
    Ok(res?)
}

pub(crate) fn remove_if_exists(path: &Path) -> Result<()> {
    match fs::remove_file(path) {
        Err(e) if e.kind() != std::io::ErrorKind::NotFound => Err(e.into()),
        _ => Ok(()),
    }
}
