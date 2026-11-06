use std::ffi::c_void;
use std::mem::ManuallyDrop;
use std::ptr::NonNull;
use std::sync::Arc;
use std::time::Duration;

use dapper_domain::{AppError, ConnectedDevice, EjectResult, Result};
use dispatch2::{DispatchQueue, DispatchRetained, DispatchTime};
use objc2::rc::autoreleasepool;
use objc2_core_foundation::{CFArray, CFRetained};
use objc2_disk_arbitration::{
    DADisk, DARegisterDiskDescriptionChangedCallback, DARegisterDiskDisappearedCallback, DASession,
    DAUnregisterCallback, kDADiskDescriptionWatchVolumePath,
};
use objc2_foundation::{
    NSArray, NSFileManager, NSNumber, NSString, NSURL, NSURLResourceKey,
    NSURLVolumeAvailableCapacityKey, NSURLVolumeIsEjectableKey, NSURLVolumeIsRemovableKey,
    NSURLVolumeLocalizedNameKey, NSURLVolumeTotalCapacityKey, NSVolumeEnumerationOptions,
};
use tokio::sync::watch;

type Sender = watch::Sender<Vec<ConnectedDevice>>;

// DiskArbitration reports a new volume path a few tens of milliseconds
// before NSFileManager lists the volume, so each event also schedules a few
// short-delay rescans (deduplicated by `publish`).
const FOLLOW_UP_RESCANS: [Duration; 3] = [
    Duration::from_millis(200),
    Duration::from_secs(1),
    Duration::from_secs(3),
];

struct Shared {
    tx: Sender,
    // Serial queue: DiskArbitration callbacks and explicit refreshes all
    // rescan here, so an older snapshot can never overwrite a newer one.
    queue: DispatchRetained<DispatchQueue>,
}

impl Shared {
    /// Must run on `queue`.
    fn on_event(self: &Arc<Self>) {
        publish(&self.tx, scan());
        for delay in FOLLOW_UP_RESCANS {
            let Ok(when) = DispatchTime::try_from(delay) else {
                continue;
            };
            let shared = Arc::clone(self);
            let _ = self.queue.after(when, move || publish(&shared.tx, scan()));
        }
    }
}

pub(super) struct Detector {
    shared: Arc<Shared>,
    session: CFRetained<DASession>,
    // Arc<Shared> leaked as the DA callback context; reclaimed in Drop.
    context: *const Shared,
}

// SAFETY: `context` is an Arc-owned Shared (Sync); DASession is a
// thread-safe CF object only touched in new() and drop().
unsafe impl Send for Detector {}
unsafe impl Sync for Detector {}

impl Detector {
    pub fn new() -> Result<Self> {
        let shared = Arc::new(Shared {
            tx: watch::channel(scan()).0,
            queue: DispatchQueue::new("com.dapper.drive-detector", None),
        });
        // SAFETY: default allocator.
        let session = unsafe { DASession::new(None) }
            .ok_or_else(|| AppError::Other("DiskArbitration session unavailable".into()))?;
        let context = Arc::into_raw(Arc::clone(&shared));
        // Mount and unmount both change a disk's volume path; ejecting removes
        // the disk. This replaces NSWorkspace did(Un)Mount, which needs an
        // AppKit run loop.
        // SAFETY: callbacks match DA's signatures; `context` outlives the
        // registrations (unregistered and drained before release in Drop).
        unsafe {
            DARegisterDiskDescriptionChangedCallback(
                &session,
                None,
                Some(kDADiskDescriptionWatchVolumePath),
                Some(on_description_changed),
                context as *mut c_void,
            );
            DARegisterDiskDisappearedCallback(
                &session,
                None,
                Some(on_disappeared),
                context as *mut c_void,
            );
            session.set_dispatch_queue(Some(&shared.queue));
        }
        Ok(Self {
            shared,
            session,
            context,
        })
    }

    pub fn list(&self) -> Vec<ConnectedDevice> {
        scan()
    }

    pub fn watch(&self) -> watch::Receiver<Vec<ConnectedDevice>> {
        let tx = &self.shared.tx;
        self.shared.queue.exec_sync(|| publish(tx, scan()));
        tx.subscribe()
    }
}

impl Drop for Detector {
    fn drop(&mut self) {
        let ctx = self.context as *mut c_void;
        // SAFETY: unregisters exactly the (callback, context) pairs registered in new().
        unsafe {
            DAUnregisterCallback(
                &self.session,
                fn_ptr(on_description_changed as *const ()),
                ctx,
            );
            DAUnregisterCallback(&self.session, fn_ptr(on_disappeared as *const ()), ctx);
            self.session.set_dispatch_queue(None);
        }
        // Let any callback already queued finish before the context is freed
        // (delayed rescans own their own Arc).
        self.shared.queue.exec_sync(|| {});
        // SAFETY: balances the Arc::into_raw in new(); no callback can run anymore.
        drop(unsafe { Arc::from_raw(self.context) });
    }
}

fn fn_ptr(f: *const ()) -> NonNull<c_void> {
    NonNull::new(f as *mut c_void).expect("function pointer is non-null")
}

/// # Safety
/// `context` must be the live `Arc<Shared>` pointer registered in `Detector::new`.
unsafe fn on_event(context: *mut c_void) {
    // SAFETY: borrowed without taking ownership of the leaked reference.
    let shared = ManuallyDrop::new(unsafe { Arc::from_raw(context as *const Shared) });
    shared.on_event();
}

unsafe extern "C-unwind" fn on_description_changed(
    _disk: NonNull<DADisk>,
    _keys: NonNull<CFArray>,
    context: *mut c_void,
) {
    // SAFETY: DA passes back the context registered in Detector::new.
    unsafe { on_event(context) }
}

unsafe extern "C-unwind" fn on_disappeared(_disk: NonNull<DADisk>, context: *mut c_void) {
    // SAFETY: as above.
    unsafe { on_event(context) }
}

fn publish(tx: &Sender, drives: Vec<ConnectedDevice>) {
    tx.send_if_modified(|current| {
        if *current == drives {
            return false;
        }
        *current = drives;
        true
    });
}

/// Mounted, non-hidden volumes that are removable or ejectable (USB, SD,
/// external SSDs) — the same filter as the Flutter Swift plugin.
fn scan() -> Vec<ConnectedDevice> {
    autoreleasepool(|_| {
        // SAFETY: Foundation's immutable NSString key constants.
        let keys: [&NSURLResourceKey; 5] = unsafe {
            [
                NSURLVolumeIsRemovableKey,
                NSURLVolumeIsEjectableKey,
                NSURLVolumeLocalizedNameKey,
                NSURLVolumeTotalCapacityKey,
                NSURLVolumeAvailableCapacityKey,
            ]
        };
        let key_array = NSArray::from_slice(&keys);
        let Some(urls) = NSFileManager::defaultManager()
            .mountedVolumeURLsIncludingResourceValuesForKeys_options(
                Some(&key_array),
                NSVolumeEnumerationOptions::SkipHiddenVolumes,
            )
        else {
            return Vec::new();
        };
        urls.iter()
            .filter_map(|url| device_for(&url, &key_array, &keys))
            .collect()
    })
}

fn device_for(
    url: &NSURL,
    key_array: &NSArray<NSURLResourceKey>,
    keys: &[&NSURLResourceKey; 5],
) -> Option<ConnectedDevice> {
    let [removable, ejectable, name, total, available] = *keys;
    let values = url.resourceValuesForKeys_error(key_array).ok()?;
    let number = |key: &NSURLResourceKey| {
        values
            .objectForKey(key)
            .and_then(|v| v.downcast::<NSNumber>().ok())
    };
    let flag = |key| number(key).is_some_and(|n| n.boolValue());
    if !flag(removable) && !flag(ejectable) {
        return None;
    }
    let path = url.path()?.to_string();
    if path.is_empty() {
        return None;
    }
    let label = values
        .objectForKey(name)
        .and_then(|v| v.downcast::<NSString>().ok())
        .or_else(|| url.lastPathComponent())
        .map(|s| s.to_string())
        .unwrap_or_else(|| "USB Device".into());
    let bytes = |key| number(key).map_or(0, |n| n.longLongValue());
    Some(ConnectedDevice {
        path,
        label,
        total_bytes: bytes(total),
        available_bytes: bytes(available),
    })
}

pub(super) async fn eject(device_path: &str) -> EjectResult {
    let output = tokio::process::Command::new("diskutil")
        .arg("eject")
        .arg(device_path)
        .output()
        .await;
    super::eject_result(output, "diskutil", true)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn watch_starts_with_current_snapshot() {
        let detector = Detector::new().unwrap();
        let rx = detector.watch();
        assert_eq!(*rx.borrow(), detector.list());
        for d in detector.list() {
            assert!(!d.path.is_empty());
            assert!(d.total_bytes >= d.available_bytes);
        }
        drop(rx);
        drop(detector);
    }
}
