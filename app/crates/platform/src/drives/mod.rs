use dapper_domain::{ConnectedDevice, EjectResult, Result};
use tokio::sync::watch;

#[cfg(target_os = "macos")]
#[path = "macos.rs"]
mod imp;
#[cfg(windows)]
#[path = "windows.rs"]
mod imp;
#[cfg(not(any(target_os = "macos", windows)))]
#[path = "unsupported.rs"]
mod imp;

/// Removable-drive detection and safe unmount.
///
/// macOS is event-driven (DiskArbitration on a private dispatch queue, so no
/// NSApplication run loop is needed); Windows polls every 2 s on a background
/// thread while at least one [`watch`](Self::watch) receiver is alive.
pub struct DriveDetector {
    inner: imp::Detector,
}

impl DriveDetector {
    /// Fails on platforms without drive detection.
    pub fn new() -> Result<Self> {
        Ok(Self {
            inner: imp::Detector::new()?,
        })
    }

    /// Current removable drives. Blocking (volume queries); run off the UI thread.
    pub fn list(&self) -> Vec<ConnectedDevice> {
        self.inner.list()
    }

    /// Receiver holding a fresh snapshot, updated as drives come and go.
    /// Takes one blocking scan; run off the UI thread.
    pub fn watch(&self) -> watch::Receiver<Vec<ConnectedDevice>> {
        self.inner.watch()
    }

    /// Safely unmounts `device_path`, carrying the platform error message on failure.
    pub async fn eject(&self, device_path: &str) -> EjectResult {
        imp::eject(device_path).await
    }
}

/// Process output → [`EjectResult`]: stderr, else stdout (when `use_stdout`),
/// else `<tool> exit <code>`.
#[cfg(any(target_os = "macos", windows, test))]
fn eject_result(
    output: std::io::Result<std::process::Output>,
    tool: &str,
    use_stdout: bool,
) -> EjectResult {
    let output = match output {
        Ok(o) => o,
        Err(e) => return EjectResult::failed(e.to_string()),
    };
    if output.status.success() {
        return EjectResult::ok();
    }
    let stderr = String::from_utf8_lossy(&output.stderr).trim().to_owned();
    let stdout = String::from_utf8_lossy(&output.stdout).trim().to_owned();
    let msg = if !stderr.is_empty() {
        stderr
    } else if use_stdout && !stdout.is_empty() {
        stdout
    } else {
        format!("{tool} exit {}", output.status.code().unwrap_or(-1))
    };
    EjectResult::failed(msg)
}

#[cfg(all(test, unix))]
mod tests {
    use std::os::unix::process::ExitStatusExt;
    use std::process::{ExitStatus, Output};

    use super::*;

    fn out(code: i32, stdout: &str, stderr: &str) -> std::io::Result<Output> {
        Ok(Output {
            status: ExitStatus::from_raw(code << 8),
            stdout: stdout.into(),
            stderr: stderr.into(),
        })
    }

    #[test]
    fn eject_messages() {
        assert_eq!(
            eject_result(out(0, "", ""), "diskutil", true),
            EjectResult::ok()
        );
        assert_eq!(
            eject_result(out(1, "out\n", " busy \n"), "diskutil", true),
            EjectResult::failed("busy")
        );
        assert_eq!(
            eject_result(out(1, " Unmount failed \n", ""), "diskutil", true),
            EjectResult::failed("Unmount failed")
        );
        assert_eq!(
            eject_result(out(1, "x", ""), "powershell", false),
            EjectResult::failed("powershell exit 1")
        );
        assert_eq!(
            eject_result(out(5, "", ""), "diskutil", true),
            EjectResult::failed("diskutil exit 5")
        );
        assert_eq!(
            eject_result(Err(std::io::Error::other("spawn failed")), "diskutil", true),
            EjectResult::failed("spawn failed")
        );
    }
}
