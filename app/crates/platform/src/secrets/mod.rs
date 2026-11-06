//! OS secret storage plus a read-only importer for the Flutter app's
//! `flutter_secure_storage` data. All functions block; call from
//! `spawn_blocking`. Every failure is `AppError::Storage` (callers fall back
//! to the credential file on it); a missing item is `Ok(None)` / `Ok(())`.

use std::collections::HashMap;
use std::path::Path;

use dapper_domain::Result;

#[cfg(target_os = "macos")]
#[path = "macos.rs"]
mod imp;
#[cfg(windows)]
#[path = "windows.rs"]
mod imp;
#[cfg(not(any(target_os = "macos", windows)))]
#[path = "unsupported.rs"]
mod imp;

pub trait SecretBackend: Send + Sync {
    fn get(&self, key: &str) -> Result<Option<String>>;
    fn set(&self, key: &str, value: &str) -> Result<()>;
    fn delete(&self, key: &str) -> Result<()>;
}

/// macOS: data-protection keychain generic passwords (service = `service`,
/// account = key). Unsigned/ad-hoc builds lack the keychain entitlement and
/// get `AppError::Storage` (errSecMissingEntitlement -34018) on every call.
/// Windows: Credential Manager generic credentials named `<service>/<key>`.
pub fn native_secret_backend(service: &str) -> Box<dyn SecretBackend> {
    imp::native(service)
}

/// Every value the Flutter app stored through `flutter_secure_storage`.
///
/// macOS: generic passwords with service `flutter_secure_storage_service` in
/// the data-protection keychain (account = key); `legacy_support_dir` is
/// unused. Windows: the DPAPI-protected `<legacy_support_dir>/flutter_secure_storage.dat`
/// JSON map, plus pre-DPAPI Credential Manager entries (the file wins on
/// conflicts, as in the plugin). Nothing is modified. No legacy data → empty map.
pub fn read_legacy_flutter_secrets(legacy_support_dir: &Path) -> Result<HashMap<String, String>> {
    imp::read_legacy(legacy_support_dir)
}
