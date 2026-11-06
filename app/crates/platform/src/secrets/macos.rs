use std::collections::HashMap;
use std::ffi::c_void;
use std::path::Path;

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
const LEGACY_SERVICE: &str = "flutter_secure_storage_service";
// Companion items of the plugin's Secure Enclave mode; never user values.
const LEGACY_WRAPPED_PREFIX: &str = "fss.wrapped.";
// CFString values of kSecAttrAccount / kSecValueData in a search result dict.
const ATTR_ACCOUNT: &str = "acct";
const ATTR_DATA: &str = "v_Data";

pub(super) fn native(service: &str) -> Box<dyn SecretBackend> {
    Box::new(Keychain {
        service: service.to_owned(),
        entitled: has_keychain_entitlement(),
    })
}

struct Keychain {
    service: String,
    entitled: bool,
}

impl Keychain {
    fn options(&self, op: &str, key: &str) -> Result<PasswordOptions> {
        if !self.entitled {
            return Err(missing_entitlement(op));
        }
        let mut options = PasswordOptions::new_generic_password(&self.service, key);
        options.use_protected_keychain();
        Ok(options)
    }
}

impl SecretBackend for Keychain {
    fn get(&self, key: &str) -> Result<Option<String>> {
        match generic_password(self.options("read", key)?) {
            Ok(bytes) => String::from_utf8(bytes)
                .map(Some)
                .map_err(|_| AppError::Storage("Keychain item is not valid UTF-8".into())),
            Err(e) if e.code() == ERR_SEC_ITEM_NOT_FOUND => Ok(None),
            Err(e) => Err(storage_error("read", e)),
        }
    }

    fn set(&self, key: &str, value: &str) -> Result<()> {
        set_generic_password_options(value.as_bytes(), self.options("write", key)?)
            .map_err(|e| storage_error("write", e))
    }

    fn delete(&self, key: &str) -> Result<()> {
        match delete_generic_password_options(self.options("delete", key)?) {
            Ok(()) => Ok(()),
            Err(e) if e.code() == ERR_SEC_ITEM_NOT_FOUND => Ok(()),
            Err(e) => Err(storage_error("delete", e)),
        }
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
    fn unsigned_binary_gets_typed_storage_errors() {
        assert!(!has_keychain_entitlement());
        let backend = native("com.dapper.dapper.platform-test");
        let is_entitlement_error = |e: AppError| matches!(&e, AppError::Storage(m) if m.contains("missing keychain entitlement"));
        assert!(is_entitlement_error(backend.get("k").unwrap_err()));
        assert!(is_entitlement_error(backend.set("k", "v").unwrap_err()));
        assert!(is_entitlement_error(backend.delete("k").unwrap_err()));
        assert!(is_entitlement_error(
            read_legacy(Path::new("/nonexistent")).unwrap_err()
        ));
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
