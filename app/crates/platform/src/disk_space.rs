use std::path::Path;

/// Best-effort free-space query for the volume containing `path`: bytes
/// available to the calling process, or `None` when the query fails
/// (unsupported OS, missing path, permission error). Callers treat `None` as
/// "skip the precheck", never as "device is full".
pub fn free_bytes_at(path: &Path) -> Option<u64> {
    match imp::free_bytes(path) {
        Ok(bytes) => Some(bytes),
        Err(e) => {
            tracing::debug!("free_bytes_at: failed for {} — {e}", path.display());
            None
        }
    }
}

#[cfg(unix)]
fn c_path(path: &Path) -> std::io::Result<std::ffi::CString> {
    use std::os::unix::ffi::OsStrExt;
    std::ffi::CString::new(path.as_os_str().as_bytes())
        .map_err(|e| std::io::Error::new(std::io::ErrorKind::InvalidInput, e))
}

// statfs rather than statvfs: Darwin's statvfs block counts are 32-bit and
// clamp on large volumes. This is the same f_bavail × f_bsize that `df`
// reports as "Available" (the Dart parsed `df -k`).
#[cfg(target_os = "macos")]
mod imp {
    use std::path::Path;

    pub fn free_bytes(path: &Path) -> std::io::Result<u64> {
        let c = super::c_path(path)?;
        let mut st = std::mem::MaybeUninit::<libc::statfs>::zeroed();
        // SAFETY: `c` is NUL-terminated and `st` is a valid out-pointer.
        if unsafe { libc::statfs(c.as_ptr(), st.as_mut_ptr()) } != 0 {
            return Err(std::io::Error::last_os_error());
        }
        // SAFETY: statfs succeeded, so the struct is initialised.
        let st = unsafe { st.assume_init() };
        Ok(st.f_bavail.saturating_mul(u64::from(st.f_bsize)))
    }
}

#[cfg(all(unix, not(target_os = "macos")))]
mod imp {
    use std::path::Path;

    pub fn free_bytes(path: &Path) -> std::io::Result<u64> {
        let c = super::c_path(path)?;
        let mut st = std::mem::MaybeUninit::<libc::statvfs>::zeroed();
        // SAFETY: `c` is NUL-terminated and `st` is a valid out-pointer.
        if unsafe { libc::statvfs(c.as_ptr(), st.as_mut_ptr()) } != 0 {
            return Err(std::io::Error::last_os_error());
        }
        // SAFETY: statvfs succeeded, so the struct is initialised.
        let st = unsafe { st.assume_init() };
        #[allow(clippy::unnecessary_cast)]
        Ok((st.f_bavail as u64).saturating_mul(st.f_frsize as u64))
    }
}

#[cfg(windows)]
mod imp {
    use std::path::Path;

    use windows::Win32::Storage::FileSystem::GetDiskFreeSpaceExW;
    use windows::core::HSTRING;

    pub fn free_bytes(path: &Path) -> std::io::Result<u64> {
        let mut free_to_caller = 0u64;
        // SAFETY: valid NUL-terminated wide string and out-pointer.
        unsafe { GetDiskFreeSpaceExW(&HSTRING::from(path), Some(&mut free_to_caller), None, None) }
            .map_err(std::io::Error::other)?;
        Ok(free_to_caller)
    }
}

#[cfg(not(any(unix, windows)))]
mod imp {
    pub fn free_bytes(_: &std::path::Path) -> std::io::Result<u64> {
        Err(std::io::Error::from(std::io::ErrorKind::Unsupported))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reports_free_space_for_existing_dir() {
        let dir = tempfile::tempdir().unwrap();
        let bytes = free_bytes_at(dir.path()).expect("free space");
        assert!(bytes > 0);
    }

    #[test]
    fn missing_path_is_none() {
        let dir = tempfile::tempdir().unwrap();
        assert_eq!(free_bytes_at(&dir.path().join("does/not/exist")), None);
    }

    // Regression guard for the Dart `df` parser bug: the result must be the
    // "Available" column (blocks), never `ifree` (0 on FAT32/exFAT).
    #[cfg(target_os = "macos")]
    #[test]
    fn matches_df_available_column() {
        let dir = tempfile::tempdir().unwrap();
        let out = std::process::Command::new("df")
            .arg("-k")
            .arg(dir.path())
            .output()
            .unwrap();
        let text = String::from_utf8(out.stdout).unwrap();
        let mut lines = text.trim().lines();
        let header: Vec<&str> = lines.next().unwrap().split_whitespace().collect();
        let idx = header
            .iter()
            .position(|h| h.eq_ignore_ascii_case("available"))
            .unwrap();
        let df_kib: u64 = lines
            .last()
            .unwrap()
            .split_whitespace()
            .nth(idx)
            .unwrap()
            .parse()
            .unwrap();
        let ours_kib = free_bytes_at(dir.path()).unwrap() / 1024;
        // Free space moves between the two calls; 1 GiB tolerance is far
        // below any confusion with ifree/capacity columns.
        assert!(
            ours_kib.abs_diff(df_kib) < 1024 * 1024,
            "ours={ours_kib} df={df_kib}"
        );
    }
}
