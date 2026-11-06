//! Secret storage: OS keychain with a 0600 JSON-file fallback
//! (`lib/data/datasources/local/credential_store.dart`).

use std::collections::BTreeMap;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, Ordering};

use dapper_domain::{AppError, Result};
use dapper_platform::secrets::{SecretBackend, native_secret_backend};
use parking_lot::Mutex;

use crate::fsutil;

/// Keychain service for the Rust app; Flutter's items live under
/// `flutter_secure_storage_service` and are only ever read (legacy import).
pub const KEYCHAIN_SERVICE: &str = "com.dapper.dapper";
pub const CREDENTIALS_FILE: &str = "credentials.v2.json";

/// Blocking key/value secret store. `write(key, None)` deletes the key.
pub trait CredentialStore: Send + Sync {
    fn read(&self, key: &str) -> Result<Option<String>>;
    fn write(&self, key: &str, value: Option<&str>) -> Result<()>;
    fn delete(&self, key: &str) -> Result<()>;
    fn delete_all(&self) -> Result<()>;
}

/// OS keychain (macOS login keychain / Windows Credential Manager).
pub struct NativeCredentialStore {
    backend: Box<dyn SecretBackend>,
}

impl NativeCredentialStore {
    pub fn new() -> Self {
        Self::with_backend(native_secret_backend(KEYCHAIN_SERVICE))
    }

    pub fn with_backend(backend: Box<dyn SecretBackend>) -> Self {
        Self { backend }
    }
}

impl Default for NativeCredentialStore {
    fn default() -> Self {
        Self::new()
    }
}

impl CredentialStore for NativeCredentialStore {
    fn read(&self, key: &str) -> Result<Option<String>> {
        self.backend.get(key)
    }

    fn write(&self, key: &str, value: Option<&str>) -> Result<()> {
        match value {
            Some(v) => self.backend.set(key, v),
            None => self.backend.delete(key),
        }
    }

    fn delete(&self, key: &str) -> Result<()> {
        self.backend.delete(key)
    }

    /// The backend cannot enumerate its items, so this deletes every key the
    /// app ever writes, deriving per-id keys from the stored server/instance
    /// lists.
    fn delete_all(&self) -> Result<()> {
        let mut keys: Vec<String> = crate::keys::STATIC_KEYS
            .iter()
            .map(|k| (*k).to_owned())
            .collect();
        for (list_key, prefix) in [
            (crate::keys::SERVERS, crate::keys::SERVER_PASSWORD_PREFIX),
            (
                crate::keys::LIDARR_INSTANCES,
                crate::keys::LIDARR_API_KEY_PREFIX,
            ),
        ] {
            if let Some(raw) = self.backend.get(list_key)? {
                keys.extend(
                    crate::keys::ids_in_list(&raw)
                        .into_iter()
                        .map(|id| format!("{prefix}{id}")),
                );
            }
        }
        for k in keys {
            self.backend.delete(&k)?;
        }
        Ok(())
    }
}

/// Whole-map JSON file, owner-only (0600) from creation, atomically replaced
/// on every write. Operations are serialised so concurrent writes never drop
/// entries.
pub struct FileCredentialStore {
    path: PathBuf,
    cache: Mutex<Option<BTreeMap<String, String>>>,
}

impl FileCredentialStore {
    /// Creates the file owner-only, or tightens an existing one to 0600 via
    /// its handle. A symlink at `path` is refused rather than followed.
    pub fn open(path: impl Into<PathBuf>) -> Result<Self> {
        use std::io::Write;
        let path = path.into();
        match fsutil::create_new_file(&path, true) {
            Ok(mut f) => {
                f.write_all(b"{}")?;
                f.sync_all()?;
            }
            Err(e) if e.kind() == std::io::ErrorKind::AlreadyExists => {
                #[cfg(unix)]
                {
                    use std::os::unix::fs::{OpenOptionsExt, PermissionsExt};
                    let f = std::fs::OpenOptions::new()
                        .read(true)
                        .custom_flags(libc::O_NOFOLLOW)
                        .open(&path)?;
                    f.set_permissions(std::fs::Permissions::from_mode(0o600))?;
                }
            }
            Err(e) => return Err(e.into()),
        }
        Ok(Self {
            path,
            cache: Mutex::new(None),
        })
    }

    pub fn path(&self) -> &Path {
        &self.path
    }

    pub fn entries(&self) -> BTreeMap<String, String> {
        self.with_map(|m| m.clone())
    }

    fn with_map<T>(&self, f: impl FnOnce(&mut BTreeMap<String, String>) -> T) -> T {
        let mut guard = self.cache.lock();
        let map = guard.get_or_insert_with(|| load_map(&self.path));
        f(map)
    }

    /// Persists a modified copy first; memory changes only once the file did.
    fn mutate(&self, f: impl FnOnce(&mut BTreeMap<String, String>)) -> Result<()> {
        self.with_map(|m| {
            let mut next = m.clone();
            f(&mut next);
            let json = serde_json::to_vec(&next).expect("string map serialisation cannot fail");
            fsutil::write_atomic(&self.path, &json, true)?;
            *m = next;
            Ok(())
        })
    }
}

/// Non-string values are dropped; unparsable files read as empty and are
/// healed by the next write.
pub(crate) fn load_map(path: &Path) -> BTreeMap<String, String> {
    let raw = match std::fs::read_to_string(path) {
        Ok(raw) => raw,
        Err(e) => {
            if e.kind() != std::io::ErrorKind::NotFound {
                tracing::warn!("credentials: failed to read {} — {e}", path.display());
            }
            return BTreeMap::new();
        }
    };
    match serde_json::from_str::<serde_json::Value>(&raw) {
        Ok(serde_json::Value::Object(obj)) => obj
            .into_iter()
            .filter_map(|(k, v)| match v {
                serde_json::Value::String(s) => Some((k, s)),
                _ => None,
            })
            .collect(),
        Ok(_) => BTreeMap::new(),
        Err(e) => {
            tracing::warn!("credentials: failed to parse {} — {e}", path.display());
            BTreeMap::new()
        }
    }
}

impl CredentialStore for FileCredentialStore {
    fn read(&self, key: &str) -> Result<Option<String>> {
        Ok(self.with_map(|m| m.get(key).cloned()))
    }

    fn write(&self, key: &str, value: Option<&str>) -> Result<()> {
        self.mutate(|m| match value {
            Some(v) => {
                m.insert(key.to_owned(), v.to_owned());
            }
            None => {
                m.remove(key);
            }
        })
    }

    fn delete(&self, key: &str) -> Result<()> {
        self.mutate(|m| {
            m.remove(key);
        })
    }

    fn delete_all(&self) -> Result<()> {
        self.mutate(BTreeMap::clear)
    }
}

/// Uses `primary` until it fails with a backend error (`AppError::Storage`,
/// e.g. macOS -34018 errSecMissingEntitlement), then switches to `fallback`
/// for the rest of the session. Other errors propagate untouched.
pub struct FallbackCredentialStore {
    primary: Box<dyn CredentialStore>,
    fallback: Box<dyn CredentialStore>,
    primary_dead: AtomicBool,
}

impl FallbackCredentialStore {
    pub fn new(primary: Box<dyn CredentialStore>, fallback: Box<dyn CredentialStore>) -> Self {
        Self {
            primary,
            fallback,
            primary_dead: AtomicBool::new(false),
        }
    }

    pub fn primary_dead(&self) -> bool {
        self.primary_dead.load(Ordering::Acquire)
    }

    fn with_fallback<T>(&self, op: impl Fn(&dyn CredentialStore) -> Result<T>) -> Result<T> {
        if self.primary_dead() {
            return op(self.fallback.as_ref());
        }
        match op(self.primary.as_ref()) {
            Err(AppError::Storage(cause)) => {
                if !self.primary_dead.swap(true, Ordering::AcqRel) {
                    tracing::warn!(
                        "credentials: primary (keychain) unavailable — switching to file backend for this session. Cause: {cause}"
                    );
                }
                op(self.fallback.as_ref())
            }
            other => other,
        }
    }
}

impl CredentialStore for FallbackCredentialStore {
    fn read(&self, key: &str) -> Result<Option<String>> {
        self.with_fallback(|s| s.read(key))
    }

    fn write(&self, key: &str, value: Option<&str>) -> Result<()> {
        self.with_fallback(|s| s.write(key, value))
    }

    fn delete(&self, key: &str) -> Result<()> {
        self.with_fallback(|s| s.delete(key))
    }

    /// Wipes both backends so a reset really resets. Both are always
    /// attempted; the first failure is returned (and every failure logged).
    fn delete_all(&self) -> Result<()> {
        let primary = self.primary.delete_all();
        if let Err(e) = &primary {
            tracing::warn!("credentials: primary.delete_all failed — {e}");
        }
        let fallback = self.fallback.delete_all();
        if let Err(e) = &fallback {
            tracing::warn!("credentials: fallback.delete_all failed — {e}");
        }
        primary.and(fallback)
    }
}

/// Moves every entry of `file` into `primary` and empties the file. File
/// values win: they were written while `primary` was unavailable. On a
/// `primary` failure the file is left untouched (it stays the fallback).
pub fn move_file_entries(
    file: &FileCredentialStore,
    primary: &dyn CredentialStore,
) -> Result<usize> {
    let entries = file.entries();
    for (key, value) in &entries {
        primary.write(key, Some(value))?;
    }
    if !entries.is_empty() {
        file.delete_all()?;
    }
    Ok(entries.len())
}

/// Keychain first, `credentials.v2.json` in `support_dir` as fallback.
/// Anything left in the file by a session without keychain access is moved
/// into the keychain once it works.
pub fn build_default_credential_store(support_dir: &Path) -> Result<FallbackCredentialStore> {
    let primary = NativeCredentialStore::new();
    let file = FileCredentialStore::open(support_dir.join(CREDENTIALS_FILE))?;
    match move_file_entries(&file, &primary) {
        Ok(0) => {}
        Ok(n) => tracing::info!(
            entries = n,
            "credentials: moved {CREDENTIALS_FILE} into the keychain"
        ),
        Err(e) => {
            tracing::warn!("credentials: keychain unavailable, keeping {CREDENTIALS_FILE}: {e}")
        }
    }
    Ok(FallbackCredentialStore::new(
        Box::new(primary),
        Box::new(file),
    ))
}

#[cfg(test)]
pub(crate) mod tests {
    use super::*;
    use std::collections::HashMap;
    use std::sync::Arc;
    use std::sync::atomic::AtomicUsize;

    /// Stand-in for either backend; optionally fails every call.
    #[derive(Default)]
    pub(crate) struct MemoryStore {
        pub map: Mutex<HashMap<String, String>>,
        pub fail_with: Option<AppError>,
        pub read_calls: AtomicUsize,
        pub write_calls: AtomicUsize,
    }

    impl MemoryStore {
        fn failing(e: AppError) -> Self {
            Self {
                fail_with: Some(e),
                ..Default::default()
            }
        }

        fn check(&self) -> Result<()> {
            self.fail_with.clone().map_or(Ok(()), Err)
        }
    }

    impl CredentialStore for Arc<MemoryStore> {
        fn read(&self, key: &str) -> Result<Option<String>> {
            self.read_calls.fetch_add(1, Ordering::SeqCst);
            self.check()?;
            Ok(self.map.lock().get(key).cloned())
        }

        fn write(&self, key: &str, value: Option<&str>) -> Result<()> {
            self.write_calls.fetch_add(1, Ordering::SeqCst);
            self.check()?;
            match value {
                Some(v) => self.map.lock().insert(key.into(), v.into()),
                None => self.map.lock().remove(key),
            };
            Ok(())
        }

        fn delete(&self, key: &str) -> Result<()> {
            self.check()?;
            self.map.lock().remove(key);
            Ok(())
        }

        fn delete_all(&self) -> Result<()> {
            self.check()?;
            self.map.lock().clear();
            Ok(())
        }
    }

    fn file_store() -> (tempfile::TempDir, PathBuf, FileCredentialStore) {
        let tmp = tempfile::tempdir().unwrap();
        let path = tmp.path().join(CREDENTIALS_FILE);
        let store = FileCredentialStore::open(&path).unwrap();
        (tmp, path, store)
    }

    #[test]
    fn file_read_missing_is_none() {
        let (_t, _p, s) = file_store();
        assert_eq!(s.read("missing").unwrap(), None);
    }

    #[test]
    fn file_write_then_read() {
        let (_t, _p, s) = file_store();
        s.write("k", Some("v")).unwrap();
        assert_eq!(s.read("k").unwrap().as_deref(), Some("v"));
    }

    #[test]
    fn file_write_none_deletes() {
        let (_t, _p, s) = file_store();
        s.write("k", Some("v")).unwrap();
        s.write("k", None).unwrap();
        assert_eq!(s.read("k").unwrap(), None);
    }

    #[test]
    fn file_delete_removes() {
        let (_t, _p, s) = file_store();
        s.write("k", Some("v")).unwrap();
        s.delete("k").unwrap();
        assert_eq!(s.read("k").unwrap(), None);
    }

    #[test]
    fn file_delete_all_clears() {
        let (_t, _p, s) = file_store();
        s.write("a", Some("1")).unwrap();
        s.write("b", Some("2")).unwrap();
        s.delete_all().unwrap();
        assert_eq!(s.read("a").unwrap(), None);
        assert_eq!(s.read("b").unwrap(), None);
    }

    #[test]
    fn file_persists_across_instances() {
        let (_t, p, s) = file_store();
        s.write("k", Some("v")).unwrap();
        let fresh = FileCredentialStore::open(&p).unwrap();
        assert_eq!(fresh.read("k").unwrap().as_deref(), Some("v"));
    }

    #[test]
    fn file_no_tmp_left_behind() {
        let (t, _p, s) = file_store();
        s.write("k", Some("v")).unwrap();
        let names: Vec<_> = std::fs::read_dir(t.path())
            .unwrap()
            .map(|e| e.unwrap().file_name().to_string_lossy().into_owned())
            .collect();
        assert_eq!(names, [CREDENTIALS_FILE]);
    }

    #[cfg(unix)]
    #[test]
    fn file_failed_write_leaves_memory_unchanged() {
        use std::os::unix::fs::PermissionsExt;
        let (t, _p, s) = file_store();
        s.write("k", Some("old")).unwrap();
        let dir_mode = |m| std::fs::set_permissions(t.path(), std::fs::Permissions::from_mode(m));
        dir_mode(0o500).unwrap();
        let res = s.write("k", Some("new"));
        let deleted = s.delete("k");
        dir_mode(0o700).unwrap();
        assert!(res.is_err());
        assert!(deleted.is_err());
        assert_eq!(s.read("k").unwrap().as_deref(), Some("old"));
    }

    #[test]
    fn file_concurrent_writes_keep_every_entry() {
        let (_t, _p, s) = file_store();
        let s = Arc::new(s);
        let handles: Vec<_> = (0..50)
            .map(|i| {
                let s = Arc::clone(&s);
                std::thread::spawn(move || {
                    s.write(&format!("k{i}"), Some(&format!("v{i}"))).unwrap()
                })
            })
            .collect();
        for h in handles {
            h.join().unwrap();
        }
        for i in 0..50 {
            assert_eq!(s.read(&format!("k{i}")).unwrap(), Some(format!("v{i}")));
        }
    }

    #[test]
    fn file_malformed_json_reads_empty_then_heals() {
        let tmp = tempfile::tempdir().unwrap();
        let p = tmp.path().join(CREDENTIALS_FILE);
        std::fs::write(&p, "{not valid json").unwrap();
        let s = FileCredentialStore::open(&p).unwrap();
        assert_eq!(s.read("k").unwrap(), None);
        s.write("k", Some("v")).unwrap();
        assert_eq!(s.read("k").unwrap().as_deref(), Some("v"));
    }

    #[test]
    fn file_is_json_object_after_write() {
        let (_t, p, s) = file_store();
        s.write("k", Some("v")).unwrap();
        let v: serde_json::Value =
            serde_json::from_str(&std::fs::read_to_string(&p).unwrap()).unwrap();
        assert_eq!(v, serde_json::json!({"k": "v"}));
    }

    #[cfg(unix)]
    #[test]
    fn file_mode_is_0600_at_open_and_after_write() {
        use std::os::unix::fs::PermissionsExt;
        let (_t, p, s) = file_store();
        let mode = || std::fs::metadata(&p).unwrap().permissions().mode() & 0o777;
        assert_eq!(mode(), 0o600);
        s.write("k", Some("v")).unwrap();
        assert_eq!(mode(), 0o600);
    }

    #[cfg(unix)]
    #[test]
    fn file_open_tightens_existing_mode() {
        use std::os::unix::fs::PermissionsExt;
        let tmp = tempfile::tempdir().unwrap();
        let p = tmp.path().join(CREDENTIALS_FILE);
        std::fs::write(&p, "{}").unwrap();
        std::fs::set_permissions(&p, std::fs::Permissions::from_mode(0o644)).unwrap();
        FileCredentialStore::open(&p).unwrap();
        assert_eq!(
            std::fs::metadata(&p).unwrap().permissions().mode() & 0o777,
            0o600
        );
    }

    #[cfg(unix)]
    #[test]
    fn file_open_refuses_symlink_and_leaves_target_mode() {
        use std::os::unix::fs::PermissionsExt;
        let tmp = tempfile::tempdir().unwrap();
        let target = tmp.path().join("elsewhere.json");
        std::fs::write(&target, "{}").unwrap();
        std::fs::set_permissions(&target, std::fs::Permissions::from_mode(0o644)).unwrap();
        let link = tmp.path().join(CREDENTIALS_FILE);
        std::os::unix::fs::symlink(&target, &link).unwrap();
        assert!(FileCredentialStore::open(&link).is_err());
        assert_eq!(
            std::fs::metadata(&target).unwrap().permissions().mode() & 0o777,
            0o644
        );
    }

    fn fallback_pair(
        primary: MemoryStore,
    ) -> (Arc<MemoryStore>, Arc<MemoryStore>, FallbackCredentialStore) {
        let primary = Arc::new(primary);
        let fallback = Arc::new(MemoryStore::default());
        let store = FallbackCredentialStore::new(
            Box::new(Arc::clone(&primary)),
            Box::new(Arc::clone(&fallback)),
        );
        (primary, fallback, store)
    }

    #[test]
    fn fallback_uses_primary_while_it_works() {
        let (primary, fallback, store) = fallback_pair(MemoryStore::default());
        store.write("k", Some("v")).unwrap();
        assert_eq!(store.read("k").unwrap().as_deref(), Some("v"));
        assert_eq!(primary.map.lock().get("k").map(String::as_str), Some("v"));
        assert!(fallback.map.lock().get("k").is_none());
    }

    #[test]
    fn fallback_switches_permanently_on_backend_error() {
        let (primary, fallback, store) = fallback_pair(MemoryStore::failing(AppError::Storage(
            "-34018 no ent".into(),
        )));
        store.write("k", Some("v")).unwrap();
        assert_eq!(primary.write_calls.load(Ordering::SeqCst), 1);
        assert_eq!(fallback.map.lock().get("k").map(String::as_str), Some("v"));

        store.write("k2", Some("v2")).unwrap();
        assert_eq!(
            primary.write_calls.load(Ordering::SeqCst),
            1,
            "primary stays dead for the session"
        );
        assert_eq!(
            fallback.map.lock().get("k2").map(String::as_str),
            Some("v2")
        );

        assert_eq!(store.read("k").unwrap().as_deref(), Some("v"));
        assert_eq!(primary.read_calls.load(Ordering::SeqCst), 0);
        assert!(store.primary_dead());
    }

    #[test]
    fn fallback_propagates_non_backend_errors() {
        let (_primary, fallback, store) = fallback_pair(MemoryStore::failing(AppError::Other(
            "something else".into(),
        )));
        assert_eq!(
            store.write("k", Some("v")),
            Err(AppError::Other("something else".into()))
        );
        assert!(fallback.map.lock().is_empty());
        assert!(!store.primary_dead());
    }

    #[test]
    fn fallback_delete_all_wipes_both_even_if_one_fails() {
        let (_primary, fallback, store) =
            fallback_pair(MemoryStore::failing(AppError::Storage("-34018".into())));
        fallback.map.lock().insert("leftover".into(), "x".into());
        assert_eq!(store.delete_all(), Err(AppError::Storage("-34018".into())));
        assert!(fallback.map.lock().is_empty());
    }

    #[test]
    fn fallback_delete_all_clears_both() {
        let (primary, fallback, store) = fallback_pair(MemoryStore::default());
        store.write("a", Some("1")).unwrap();
        store.write("b", Some("2")).unwrap();
        fallback.map.lock().insert("c".into(), "3".into());
        store.delete_all().unwrap();
        assert!(primary.map.lock().is_empty());
        assert!(fallback.map.lock().is_empty());
    }

    struct MapBackend(Mutex<HashMap<String, String>>);

    impl SecretBackend for MapBackend {
        fn get(&self, key: &str) -> Result<Option<String>> {
            Ok(self.0.lock().get(key).cloned())
        }
        fn set(&self, key: &str, value: &str) -> Result<()> {
            self.0.lock().insert(key.into(), value.into());
            Ok(())
        }
        fn delete(&self, key: &str) -> Result<()> {
            self.0.lock().remove(key);
            Ok(())
        }
    }

    #[test]
    fn native_delete_all_removes_known_and_per_id_keys() {
        let store =
            NativeCredentialStore::with_backend(Box::new(MapBackend(Mutex::new(HashMap::new()))));
        store
            .write(
                crate::keys::SERVERS,
                Some(r#"[{"id":"a","name":"n","url":"u","username":"x"}]"#),
            )
            .unwrap();
        store.write("server_password_a", Some("pw")).unwrap();
        store
            .write(
                crate::keys::LIDARR_INSTANCES,
                Some(r#"[{"id":"b","name":"n","url":"u"}]"#),
            )
            .unwrap();
        store.write("lidarr_api_key_b", Some("key")).unwrap();
        store.write("selected_server_id", Some("a")).unwrap();
        store.write("password", Some("legacy")).unwrap();
        store.delete_all().unwrap();
        for k in [
            crate::keys::SERVERS,
            "server_password_a",
            crate::keys::LIDARR_INSTANCES,
            "lidarr_api_key_b",
            "selected_server_id",
            "password",
        ] {
            assert_eq!(store.read(k).unwrap(), None, "{k}");
        }
    }

    #[test]
    fn file_entries_move_into_a_working_keychain_only() {
        let (_tmp, path, file) = file_store();
        file.write("navidrome_servers", Some("[]")).unwrap();
        file.write("server_password_1", Some("new")).unwrap();

        let down = Arc::new(MemoryStore::failing(AppError::Storage("locked".into())));
        assert!(move_file_entries(&file, &down).is_err());
        assert_eq!(load_map(&path).len(), 2);

        let keychain = Arc::new(MemoryStore::default());
        keychain.write("server_password_1", Some("old")).unwrap();
        assert_eq!(move_file_entries(&file, &keychain).unwrap(), 2);
        assert_eq!(
            keychain.read("server_password_1").unwrap().as_deref(),
            Some("new")
        );
        assert_eq!(
            keychain.read("navidrome_servers").unwrap().as_deref(),
            Some("[]")
        );
        assert!(load_map(&path).is_empty());
        assert_eq!(move_file_entries(&file, &keychain).unwrap(), 0);
    }
}
