use std::collections::{BTreeMap, HashMap};
use std::ffi::c_void;
use std::path::Path;
use std::sync::Mutex;

use dapper_domain::{AppError, Result};
use objc2_core_foundation::CFString;
use security_framework::base::Error as SecError;
use security_framework::item::{ItemClass, ItemSearchOptions, Limit};
use security_framework::passwords::{
    PasswordOptions, delete_generic_password_options, generic_password,
    set_generic_password_options,
};

use super::SecretBackend;

const ERR_SEC_ITEM_NOT_FOUND: i32 = -25300;
const ERR_SEC_MISSING_ENTITLEMENT: i32 = -34018;
/// Account of the single keychain item holding every secret as a JSON map.
const ITEM_ACCOUNT: &str = "credentials";
const LEGACY_SERVICE: &str = "flutter_secure_storage_service";
// Companion items of the plugin's Secure Enclave mode; never user values.
const LEGACY_WRAPPED_PREFIX: &str = "fss.wrapped.";
// CFString values of kSecAttrAccount / kSecValueData in a search result dict.
const ATTR_ACCOUNT: &str = "acct";
const ATTR_DATA: &str = "v_Data";

pub(super) fn native(service: &str) -> Box<dyn SecretBackend> {
    Box::new(Keychain {
        service: service.to_owned(),
        cache: Mutex::new(None),
    })
}

/// Login (file-based) keychain: unlike the data-protection keychain it needs
/// no team-signed entitlement, so unsigned and ad-hoc builds can use it. Its
/// ACL trusts the creating binary; another signature (each ad-hoc rebuild or
/// update) gets one "allow access" prompt, so all secrets share one item to
/// keep that to a single prompt.
struct Keychain {
    service: String,
    cache: Mutex<Option<BTreeMap<String, String>>>,
}

impl Keychain {
    fn options(&self) -> PasswordOptions {
        PasswordOptions::new_generic_password(&self.service, ITEM_ACCOUNT)
    }

    fn load(&self) -> Result<BTreeMap<String, String>> {
        match generic_password(self.options()) {
            Ok(bytes) => serde_json::from_slice(&bytes)
                .map_err(|_| AppError::Storage("Keychain item is not a credential map".into())),
            Err(e) if e.code() == ERR_SEC_ITEM_NOT_FOUND => Ok(BTreeMap::new()),
            Err(e) => Err(storage_error("read", e)),
        }
    }

    fn save(&self, map: &BTreeMap<String, String>) -> Result<()> {
        if map.is_empty() {
            return match delete_generic_password_options(self.options()) {
                Err(e) if e.code() != ERR_SEC_ITEM_NOT_FOUND => Err(storage_error("delete", e)),
                _ => Ok(()),
            };
        }
        let json = serde_json::to_vec(map).expect("string map serialisation cannot fail");
        set_generic_password_options(&json, self.options()).map_err(|e| storage_error("write", e))
    }

    /// Runs `f` on the cached map (loaded on first use); a `Some` result is
    /// persisted before it replaces the cache.
    fn with_map<T>(
        &self,
        f: impl FnOnce(&BTreeMap<String, String>) -> (T, Option<BTreeMap<String, String>>),
    ) -> Result<T> {
        let mut guard = self.cache.lock().unwrap_or_else(|e| e.into_inner());
        if guard.is_none() {
            *guard = Some(self.load()?);
        }
        let map = guard.as_mut().expect("loaded above");
        let (out, next) = f(map);
        if let Some(next) = next {
            self.save(&next)?;
            *map = next;
        }
        Ok(out)
    }
}

impl SecretBackend for Keychain {
    fn get(&self, key: &str) -> Result<Option<String>> {
        self.with_map(|m| (m.get(key).cloned(), None))
    }

    fn set(&self, key: &str, value: &str) -> Result<()> {
        self.with_map(|m| {
            if m.get(key).map(String::as_str) == Some(value) {
                return ((), None);
            }
            let mut next = m.clone();
            next.insert(key.to_owned(), value.to_owned());
            ((), Some(next))
        })
    }

    fn delete(&self, key: &str) -> Result<()> {
        self.with_map(|m| {
            if !m.contains_key(key) {
                return ((), None);
            }
            let mut next = m.clone();
            next.remove(key);
            ((), Some(next))
        })
    }
}

fn missing_entitlement(op: &str) -> AppError {
    AppError::Storage(format!(
        "Keychain {op} failed: missing keychain entitlement (unsigned or ad-hoc build) ({ERR_SEC_MISSING_ENTITLEMENT})"
    ))
}

fn storage_error(op: &str, e: SecError) -> AppError {
    let code = e.code();
    if code == ERR_SEC_MISSING_ENTITLEMENT {
        missing_entitlement(op)
    } else {
        AppError::Storage(format!("Keychain {op} failed: {e} ({code})"))
    }
}

#[link(name = "Security", kind = "framework")]
unsafe extern "C" {
    fn SecTaskCreateFromSelf(allocator: *const c_void) -> *mut c_void;
    fn SecTaskCopyValueForEntitlement(
        task: *mut c_void,
        entitlement: &CFString,
        error: *mut *mut c_void,
    ) -> *mut c_void;
}

#[link(name = "CoreFoundation", kind = "framework")]
unsafe extern "C" {
    fn CFRelease(cf: *const c_void);
}

// Without an access-group entitlement the data-protection keychain reports
// reads as "not found" (only writes fail with -34018), which would silently
// hide credentials kept in the fallback file. Probe up front instead.
fn has_keychain_entitlement() -> bool {
    // SAFETY: plain CF create/copy calls; every non-null result is released.
    unsafe {
        let task = SecTaskCreateFromSelf(std::ptr::null());
        if task.is_null() {
            return false;
        }
        let entitled = ["keychain-access-groups", "com.apple.application-identifier"]
            .iter()
            .any(|name| {
                let value = SecTaskCopyValueForEntitlement(
                    task,
                    &CFString::from_str(name),
                    std::ptr::null_mut(),
                );
                if value.is_null() {
                    return false;
                }
                CFRelease(value);
                true
            });
        CFRelease(task);
        entitled
    }
}

pub(super) fn read_legacy(_legacy_support_dir: &Path) -> Result<HashMap<String, String>> {
    if !has_keychain_entitlement() {
        return Err(missing_entitlement("legacy read"));
    }
    let results = match ItemSearchOptions::new()
        .class(ItemClass::generic_password())
        .service(LEGACY_SERVICE)
        .ignore_legacy_keychains()
        .load_attributes(true)
        .load_data(true)
        .limit(Limit::All)
        .search()
    {
        Ok(results) => results,
        Err(e) if e.code() == ERR_SEC_ITEM_NOT_FOUND => return Ok(HashMap::new()),
        Err(e) => return Err(storage_error("legacy read", e)),
    };
    Ok(results
        .iter()
        .filter_map(|item| {
            let mut attrs = item.simplify_dict()?;
            let key = attrs.remove(ATTR_ACCOUNT)?;
            if key.starts_with(LEGACY_WRAPPED_PREFIX) {
                return None;
            }
            Some((key, attrs.remove(ATTR_DATA)?))
        })
        .collect())
}

#[cfg(test)]
mod tests {
    use super::*;

    // `cargo test` binaries are unsigned, so they carry no keychain entitlement.
    #[test]
    fn unsigned_binary_cannot_read_flutter_keychain() {
        assert!(!has_keychain_entitlement());
        assert!(matches!(
            read_legacy(Path::new("/nonexistent")).unwrap_err(),
            AppError::Storage(m) if m.contains("missing keychain entitlement")
        ));
    }

    /// Touches the real login keychain (service `com.dapper.dapper.platform-test`),
    /// so it only runs on demand: `cargo test -p dapper-platform -- --ignored`.
    #[test]
    #[ignore]
    fn unsigned_binary_round_trips_through_login_keychain() {
        let service = "com.dapper.dapper.platform-test";
        let backend = native(service);
        backend.set("a", "1").unwrap();
        backend.set("b", "2").unwrap();
        backend.delete("a").unwrap();
        let fresh = native(service);
        assert_eq!(fresh.get("a").unwrap(), None);
        assert_eq!(fresh.get("b").unwrap().as_deref(), Some("2"));
        fresh.delete("b").unwrap();
        assert_eq!(native(service).get("b").unwrap(), None);
    }

    #[test]
    fn raw_missing_entitlement_status_maps_to_storage() {
        let e = storage_error("write", SecError::from_code(ERR_SEC_MISSING_ENTITLEMENT));
        assert!(matches!(&e, AppError::Storage(m) if m.contains("-34018")));
        assert!(matches!(
            storage_error("read", SecError::from_code(-25308)),
            AppError::Storage(_)
        ));
    }
}
