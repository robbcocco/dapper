use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex, MutexGuard, PoisonError};
use std::thread::{self, Thread};
use std::time::Duration;

use dapper_domain::{ConnectedDevice, EjectResult, Result};
use tokio::sync::watch;
use windows::Win32::Storage::FileSystem::{
    GetDiskFreeSpaceExW, GetDriveTypeW, GetLogicalDrives, GetVolumeInformationW,
};
use windows::Win32::System::WindowsProgramming::DRIVE_REMOVABLE;
use windows::core::HSTRING;

const POLL_INTERVAL: Duration = Duration::from_secs(2);
const MAX_PATH: usize = 260;
// Keeps powershell from flashing a console window from the GUI process.
const CREATE_NO_WINDOW: u32 = 0x0800_0000;

type Sender = watch::Sender<Vec<ConnectedDevice>>;

#[derive(Default)]
struct State {
    tx: Option<Sender>,
    poller: Option<Thread>,
}

#[derive(Default)]
struct Shared {
    state: Mutex<State>,
    stopped: AtomicBool,
}

impl Shared {
    fn lock(&self) -> MutexGuard<'_, State> {
        self.state.lock().unwrap_or_else(PoisonError::into_inner)
    }
}

/// One shared channel so every receiver coalesces onto a single poll thread;
/// the thread exits once the last receiver is dropped and restarts (with a
/// fresh dedupe baseline) on the next `watch()`.
pub(super) struct Detector {
    shared: Arc<Shared>,
}

impl Detector {
    pub fn new() -> Result<Self> {
        Ok(Self {
            shared: Arc::default(),
        })
    }

    pub fn list(&self) -> Vec<ConnectedDevice> {
        scan()
    }

    pub fn watch(&self) -> watch::Receiver<Vec<ConnectedDevice>> {
        let mut state = self.shared.lock();
        if let Some(tx) = &state.tx {
            return tx.subscribe();
        }
        // Immediate first scan so receivers don't wait a poll interval.
        let (tx, rx) = watch::channel(scan());
        let shared = Arc::clone(&self.shared);
        match thread::Builder::new()
            .name("dapper-drive-poll".into())
            .spawn(move || poll(&shared))
        {
            Ok(handle) => {
                *state = State {
                    tx: Some(tx),
                    poller: Some(handle.thread().clone()),
                }
            }
            Err(e) => tracing::warn!("drive detector: could not start poll thread — {e}"),
        }
        rx
    }
}

impl Drop for Detector {
    fn drop(&mut self) {
        self.shared.stopped.store(true, Ordering::Release);
        let state = std::mem::take(&mut *self.shared.lock());
        if let Some(poller) = state.poller {
            poller.unpark();
        }
    }
}

fn poll(shared: &Shared) {
    loop {
        thread::park_timeout(POLL_INTERVAL);
        if shared.stopped.load(Ordering::Acquire) {
            return;
        }
        let current = scan();
        let mut state = shared.lock();
        let Some(tx) = &state.tx else { return };
        if tx.receiver_count() == 0 {
            *state = State::default();
            return;
        }
        tx.send_if_modified(|last| {
            if same_list(last, &current) {
                return false;
            }
            *last = current;
            true
        });
    }
}

fn same_list(a: &[ConnectedDevice], b: &[ConnectedDevice]) -> bool {
    a.len() == b.len()
        && a.iter()
            .zip(b)
            .all(|(x, y)| x.path == y.path && x.available_bytes == y.available_bytes)
}

fn scan() -> Vec<ConnectedDevice> {
    // SAFETY: no arguments.
    let mask = unsafe { GetLogicalDrives() };
    (0..26u8)
        .filter(|bit| mask & (1 << bit) != 0)
        .filter_map(|bit| {
            let letter = char::from(b'A' + bit);
            let root = format!("{letter}:\\");
            let wide = HSTRING::from(root.as_str());
            // SAFETY: NUL-terminated wide string.
            if unsafe { GetDriveTypeW(&wide) } != DRIVE_REMOVABLE {
                return None;
            }
            Some(query_volume(root, &wide, letter))
        })
        .collect()
}

fn query_volume(root: String, wide: &HSTRING, letter: char) -> ConnectedDevice {
    let mut label = [0u16; MAX_PATH + 1];
    let (mut total, mut free) = (0u64, 0u64);
    // Failures leave the label empty / sizes zero rather than hiding the drive
    // (e.g. a card reader with no media still lists, as in the Flutter app).
    // SAFETY: valid root string, buffer and out-pointers.
    unsafe {
        let _ = GetVolumeInformationW(wide, Some(&mut label), None, None, None, None);
        let _ = GetDiskFreeSpaceExW(wide, None, Some(&mut total), Some(&mut free));
    }
    let len = label.iter().position(|&c| c == 0).unwrap_or(label.len());
    let label = String::from_utf16_lossy(&label[..len]);
    ConnectedDevice {
        path: root,
        label: if label.is_empty() {
            format!("{letter}:")
        } else {
            label
        },
        total_bytes: i64::try_from(total).unwrap_or(i64::MAX),
        available_bytes: i64::try_from(free).unwrap_or(i64::MAX),
    }
}

/// Shell.Application's Eject verb via PowerShell. The verb is asynchronous on
/// the OS side — the drive disappears within a poll cycle. No admin rights.
/// Only a bare drive root (`E:` or `E:\`) is accepted; it's interpolated into
/// a PowerShell command line.
fn eject_script(device_path: &str) -> std::result::Result<String, String> {
    let drive = device_path.strip_suffix('\\').unwrap_or(device_path);
    match drive.as_bytes() {
        [letter, b':'] if letter.is_ascii_alphabetic() => Ok(format!(
            "$sa = New-Object -comObject Shell.Application; $sa.Namespace(17).ParseName('{drive}').InvokeVerb('Eject')"
        )),
        _ => Err(format!("Invalid drive path: {device_path}")),
    }
}

pub(super) async fn eject(device_path: &str) -> EjectResult {
    let script = match eject_script(device_path) {
        Ok(s) => s,
        Err(e) => return EjectResult::failed(e),
    };
    let output = tokio::process::Command::new("powershell")
        .args(["-NoProfile", "-Command", &script])
        .creation_flags(CREATE_NO_WINDOW)
        .output()
        .await;
    super::eject_result(output, "powershell", false)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn dev(path: &str, avail: i64, label: &str) -> ConnectedDevice {
        ConnectedDevice {
            path: path.into(),
            label: label.into(),
            total_bytes: 100,
            available_bytes: avail,
        }
    }

    #[test]
    fn dedupe_compares_path_and_available_only() {
        assert!(same_list(&[dev("E:\\", 1, "A")], &[dev("E:\\", 1, "B")]));
        assert!(!same_list(&[dev("E:\\", 1, "A")], &[dev("E:\\", 2, "A")]));
        assert!(!same_list(&[dev("E:\\", 1, "A")], &[]));
    }

    #[test]
    fn eject_script_validation() {
        assert_eq!(
            eject_script("E:\\").unwrap(),
            "$sa = New-Object -comObject Shell.Application; $sa.Namespace(17).ParseName('E:').InvokeVerb('Eject')"
        );
        assert_eq!(eject_script("e:").unwrap(), eject_script("e:\\").unwrap());
        for bad in [
            "E",
            "\\\\server",
            "E:\\\\",
            "E:\\Music",
            "E:'); Remove-Item C:\\ -Recurse; ('",
            "1:",
            "É:",
            "",
        ] {
            assert_eq!(
                eject_script(bad).unwrap_err(),
                format!("Invalid drive path: {bad}")
            );
        }
    }
}
