use std::path::Path;

/// On macOS, removes the AppleDouble sidecar (`._<name>`) the OS writes when
/// storing extended attributes on FAT32/exFAT volumes, then strips every
/// xattr from the file so the sidecar is not recreated. Failures are logged
/// and ignored; no-op elsewhere.
pub fn remove_macos_sidecar(path: &Path) {
    #[cfg(target_os = "macos")]
    {
        remove_sidecar_file(path);
        clear_xattrs(path);
    }
    #[cfg(not(target_os = "macos"))]
    let _ = path;
}

/// Batch form of [`remove_macos_sidecar`] used after zip extraction.
pub fn remove_macos_sidecars<P: AsRef<Path>>(paths: impl IntoIterator<Item = P>) {
    for path in paths {
        remove_macos_sidecar(path.as_ref());
    }
}

#[cfg(target_os = "macos")]
fn remove_sidecar_file(path: &Path) {
    let (Some(dir), Some(name)) = (path.parent(), path.file_name()) else {
        return;
    };
    let mut sidecar_name = std::ffi::OsString::from("._");
    sidecar_name.push(name);
    let sidecar = dir.join(sidecar_name);
    match std::fs::remove_file(&sidecar) {
        Ok(()) => {}
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => {}
        Err(e) => tracing::debug!(
            "remove_macos_sidecar: could not delete {} — {e}",
            sidecar.display()
        ),
    }
}

// Equivalent of `xattr -c` (which follows symlinks). Common to fail on
// read-only volumes; without it the OS recreates the sidecar on next read.
#[cfg(target_os = "macos")]
fn clear_xattrs(path: &Path) {
    let names = match xattr::list_deref(path) {
        Ok(names) => names,
        Err(e) => {
            tracing::debug!(
                "remove_macos_sidecar: listing xattrs on {} failed — {e}",
                path.display()
            );
            return;
        }
    };
    for name in names {
        if let Err(e) = xattr::remove_deref(path, &name) {
            tracing::debug!(
                "remove_macos_sidecar: removing xattr {name:?} from {} failed — {e}",
                path.display()
            );
        }
    }
}

#[cfg(all(test, target_os = "macos"))]
mod tests {
    use super::*;

    // The kernel-managed com.apple.provenance xattr survives `xattr -c` too.
    fn user_xattrs(path: &Path) -> Vec<std::ffi::OsString> {
        xattr::list(path)
            .unwrap()
            .filter(|n| n != "com.apple.provenance")
            .collect()
    }

    #[test]
    fn removes_sidecar_and_xattrs() {
        let dir = tempfile::tempdir().unwrap();
        let file = dir.path().join("01 Song.flac");
        let sidecar = dir.path().join("._01 Song.flac");
        std::fs::write(&file, b"x").unwrap();
        std::fs::write(&sidecar, b"apple double").unwrap();
        xattr::set(&file, "com.apple.quarantine", b"0081;0;dapper;").unwrap();
        xattr::set(&file, "user.dapper", b"1").unwrap();

        remove_macos_sidecar(&file);

        assert!(file.exists());
        assert!(!sidecar.exists());
        assert!(user_xattrs(&file).is_empty());
    }

    #[test]
    fn batch_and_missing_files_are_ignored() {
        let dir = tempfile::tempdir().unwrap();
        let a = dir.path().join("a.mp3");
        let b = dir.path().join("b.mp3");
        std::fs::write(&a, b"a").unwrap();
        std::fs::write(dir.path().join("._a.mp3"), b"s").unwrap();
        xattr::set(&a, "user.k", b"v").unwrap();

        remove_macos_sidecars([&a, &b, &dir.path().join("missing.mp3")]);

        assert!(!dir.path().join("._a.mp3").exists());
        assert!(user_xattrs(&a).is_empty());
        assert!(!b.exists());
    }
}
