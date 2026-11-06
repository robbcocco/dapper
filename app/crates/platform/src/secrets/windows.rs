use std::collections::HashMap;
use std::ffi::c_void;
use std::path::Path;

use dapper_domain::{AppError, Result};
use windows::Win32::Foundation::{ERROR_NOT_FOUND, HLOCAL, LocalFree};
use windows::Win32::Security::Credentials::{
    CRED_PERSIST_LOCAL_MACHINE, CRED_TYPE_GENERIC, CREDENTIALW, CredDeleteW, CredEnumerateW,
    CredFree, CredReadW, CredWriteW,
};
use windows::Win32::Security::Cryptography::{CRYPT_INTEGER_BLOB, CryptUnprotectData};
use windows::core::{HSTRING, PWSTR};

use super::SecretBackend;

const LEGACY_FILE: &str = "flutter_secure_storage.dat";
// flutter_secure_storage_windows' native plugin names credentials
// `${BINARY_NAME}_VGhpcyBpcyB0aGUgcHJlZml4IGZv_<key>`; Dapper's BINARY_NAME is "dapper".
const LEGACY_CRED_PREFIX: &str = "dapper_VGhpcyBpcyB0aGUgcHJlZml4IGZv_";

pub(super) fn native(service: &str) -> Box<dyn SecretBackend> {
    Box::new(CredentialManager {
        service: service.to_owned(),
    })
}

struct CredentialManager {
    service: String,
}

impl CredentialManager {
    fn target(&self, key: &str) -> String {
        format!("{}/{key}", self.service)
    }
}

fn is_not_found(e: &windows::core::Error) -> bool {
    e.code() == ERROR_NOT_FOUND.to_hresult()
}

fn storage_error(op: &str, e: impl std::fmt::Display) -> AppError {
    AppError::Storage(format!("Credential Manager {op} failed: {e}"))
}

fn wide(s: &str) -> Vec<u16> {
    s.encode_utf16().chain(std::iter::once(0)).collect()
}

/// # Safety
/// `cred` must point to a valid CREDENTIALW.
unsafe fn blob(cred: &CREDENTIALW) -> &[u8] {
    if cred.CredentialBlob.is_null() || cred.CredentialBlobSize == 0 {
        return &[];
    }
    // SAFETY: the API guarantees CredentialBlobSize readable bytes.
    unsafe { std::slice::from_raw_parts(cred.CredentialBlob, cred.CredentialBlobSize as usize) }
}

impl SecretBackend for CredentialManager {
    fn get(&self, key: &str) -> Result<Option<String>> {
        let target = HSTRING::from(self.target(key));
        let mut cred: *mut CREDENTIALW = std::ptr::null_mut();
        // SAFETY: valid target string and out-pointer.
        match unsafe { CredReadW(&target, CRED_TYPE_GENERIC, None, &mut cred) } {
            Err(e) if is_not_found(&e) => Ok(None),
            Err(e) => Err(storage_error("read", e)),
            Ok(()) => {
                // SAFETY: CredReadW succeeded, so `cred` is valid until CredFree.
                let bytes = unsafe { blob(&*cred) }.to_vec();
                // SAFETY: allocated by CredReadW.
                unsafe { CredFree(cred as *const c_void) };
                String::from_utf8(bytes)
                    .map(Some)
                    .map_err(|_| AppError::Storage("Credential is not valid UTF-8".into()))
            }
        }
    }

    fn set(&self, key: &str, value: &str) -> Result<()> {
        let mut target = wide(&self.target(key));
        let mut user = wide(key);
        let mut data = value.as_bytes().to_vec();
        let size =
            u32::try_from(data.len()).map_err(|_| AppError::Storage("Secret too large".into()))?;
        let cred = CREDENTIALW {
            Type: CRED_TYPE_GENERIC,
            TargetName: PWSTR(target.as_mut_ptr()),
            UserName: PWSTR(user.as_mut_ptr()),
            CredentialBlobSize: size,
            CredentialBlob: data.as_mut_ptr(),
            Persist: CRED_PERSIST_LOCAL_MACHINE,
            ..Default::default()
        };
        // SAFETY: every pointer in `cred` outlives the call.
        unsafe { CredWriteW(&cred, 0) }.map_err(|e| storage_error("write", e))
    }

    fn delete(&self, key: &str) -> Result<()> {
        let target = HSTRING::from(self.target(key));
        // SAFETY: valid target string.
        match unsafe { CredDeleteW(&target, CRED_TYPE_GENERIC, None) } {
            Ok(()) => Ok(()),
            Err(e) if is_not_found(&e) => Ok(()),
            Err(e) => Err(storage_error("delete", e)),
        }
    }
}

pub(super) fn read_legacy(legacy_support_dir: &Path) -> Result<HashMap<String, String>> {
    let mut map = read_dpapi_file(&legacy_support_dir.join(LEGACY_FILE))?;
    for (key, value) in read_legacy_credentials()? {
        map.entry(key).or_insert(value);
    }
    Ok(map)
}

/// DPAPI (current user, no entropy) over UTF-8 JSON `{key: value}`.
fn read_dpapi_file(path: &Path) -> Result<HashMap<String, String>> {
    let mut encrypted = match std::fs::read(path) {
        Ok(bytes) => bytes,
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => return Ok(HashMap::new()),
        Err(e) => {
            return Err(AppError::Storage(format!(
                "Reading {} failed: {e}",
                path.display()
            )));
        }
    };
    let input = CRYPT_INTEGER_BLOB {
        cbData: u32::try_from(encrypted.len())
            .map_err(|_| AppError::Storage("Legacy secrets file too large".into()))?,
        pbData: encrypted.as_mut_ptr(),
    };
    let mut output = CRYPT_INTEGER_BLOB::default();
    // SAFETY: valid input blob; output is LocalAlloc'd by the API and freed below.
    unsafe { CryptUnprotectData(&input, None, None, None, None, 0, &mut output) }
        .map_err(|e| storage_error("DPAPI decrypt", e))?;
    let plain = if output.pbData.is_null() {
        Vec::new()
    } else {
        // SAFETY: CryptUnprotectData returned cbData bytes at pbData.
        let bytes =
            unsafe { std::slice::from_raw_parts(output.pbData, output.cbData as usize) }.to_vec();
        // SAFETY: pbData was allocated with LocalAlloc.
        unsafe { LocalFree(Some(HLOCAL(output.pbData as *mut c_void))) };
        bytes
    };
    let json: serde_json::Value = serde_json::from_slice(&plain)
        .map_err(|e| AppError::Storage(format!("Legacy secrets file is not JSON: {e}")))?;
    let serde_json::Value::Object(object) = json else {
        return Err(AppError::Storage(
            "Legacy secrets file is not a JSON object".into(),
        ));
    };
    Ok(object
        .into_iter()
        .filter_map(|(k, v)| match v {
            serde_json::Value::String(s) => Some((k, s)),
            _ => None,
        })
        .collect())
}

/// Pre-DPAPI plugin storage: values are NUL-terminated C strings in the blob.
fn read_legacy_credentials() -> Result<Vec<(String, String)>> {
    let filter = HSTRING::from(format!("{LEGACY_CRED_PREFIX}*"));
    let mut count = 0u32;
    let mut creds: *mut *mut CREDENTIALW = std::ptr::null_mut();
    // SAFETY: valid filter and out-pointers.
    match unsafe { CredEnumerateW(&filter, None, &mut count, &mut creds) } {
        Ok(()) => {}
        Err(e) if is_not_found(&e) => return Ok(Vec::new()),
        Err(e) => return Err(storage_error("legacy enumerate", e)),
    }
    let mut entries = Vec::with_capacity(count as usize);
    for i in 0..count as usize {
        // SAFETY: CredEnumerateW returned `count` valid credential pointers.
        let cred = unsafe { &**creds.add(i) };
        // SAFETY: TargetName is a NUL-terminated wide string.
        let Ok(target) = (unsafe { cred.TargetName.to_string() }) else {
            continue;
        };
        let Some(key) = target.strip_prefix(LEGACY_CRED_PREFIX) else {
            continue;
        };
        // SAFETY: `cred` is valid until CredFree below.
        let bytes = unsafe { blob(cred) };
        let end = bytes.iter().position(|&b| b == 0).unwrap_or(bytes.len());
        entries.push((
            key.to_owned(),
            String::from_utf8_lossy(&bytes[..end]).into_owned(),
        ));
    }
    // SAFETY: allocated by CredEnumerateW.
    unsafe { CredFree(creds as *const c_void) };
    Ok(entries)
}
