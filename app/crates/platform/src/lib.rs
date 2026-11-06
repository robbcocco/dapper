//! Drive detection, eject, free space, macOS sidecar/xattr cleanup and secure storage.

mod disk_space;
mod drives;
pub mod secrets;
mod sidecar;

pub use disk_space::free_bytes_at;
pub use drives::DriveDetector;
pub use secrets::{SecretBackend, native_secret_backend, read_legacy_flutter_secrets};
pub use sidecar::{remove_macos_sidecar, remove_macos_sidecars};
