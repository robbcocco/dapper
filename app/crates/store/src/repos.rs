//! Navidrome server and Lidarr instance persistence, ported from
//! `ServerRepository`/`LidarrRepository` plus the list/selection notifiers in
//! `lib/application/providers/providers.dart`.

use std::sync::Arc;

use dapper_domain::{AppError, LidarrInstance, NavidromeServer, Result};
use serde::Serialize;
use serde::de::DeserializeOwned;

use crate::credentials::CredentialStore;
use crate::keys;

fn load_list<T: DeserializeOwned>(creds: &dyn CredentialStore, key: &str) -> Result<Vec<T>> {
    match creds.read(key)? {
        None => Ok(Vec::new()),
        Some(raw) => {
            serde_json::from_str(&raw).map_err(|e| AppError::Storage(format!("{key}: {e}")))
        }
    }
}

fn save_list<T: Serialize>(creds: &dyn CredentialStore, key: &str, items: &[T]) -> Result<()> {
    let raw = serde_json::to_string(items).expect("model serialisation cannot fail");
    creds.write(key, Some(&raw))
}

fn save_selected(creds: &dyn CredentialStore, key: &str, id: Option<&str>) -> Result<()> {
    match id {
        None => creds.delete(key),
        Some(id) => creds.write(key, Some(id)),
    }
}

/// Dart `int.tryParse` (no radix): surrounding whitespace ignored, optional
/// sign, `0x` hex prefix accepted.
fn dart_int_try_parse(s: &str) -> Option<i64> {
    let t = s.trim();
    let (neg, body) = match t.as_bytes().first() {
        Some(b'-') => (true, &t[1..]),
        Some(b'+') => (false, &t[1..]),
        _ => (false, t),
    };
    let (digits, radix) = match body.strip_prefix("0x").or_else(|| body.strip_prefix("0X")) {
        Some(hex) => (hex, 16),
        None => (body, 10),
    };
    if digits.is_empty() || !digits.chars().all(|c| c.is_digit(radix)) {
        return None;
    }
    let v = i64::from_str_radix(digits, radix).ok()?;
    Some(if neg { -v } else { v })
}

pub fn new_id() -> String {
    uuid::Uuid::new_v4().to_string()
}

/// URL + login for the selected server. `Debug` redacts the password.
#[derive(Clone, PartialEq, Eq)]
pub struct ServerCredentials {
    pub url: String,
    pub username: String,
    pub password: String,
}

impl std::fmt::Debug for ServerCredentials {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("ServerCredentials")
            .field("url", &self.url)
            .field("username", &self.username)
            .field("password", &"<redacted>")
            .finish()
    }
}

/// URL + API key for the selected Lidarr instance. `Debug` redacts the key.
#[derive(Clone, PartialEq, Eq)]
pub struct LidarrCredentials {
    pub url: String,
    pub api_key: String,
}

impl std::fmt::Debug for LidarrCredentials {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("LidarrCredentials")
            .field("url", &self.url)
            .field("api_key", &"<redacted>")
            .finish()
    }
}

/// Blocking; async callers use `spawn_blocking`.
#[derive(Clone)]
pub struct ServerRepository {
    creds: Arc<dyn CredentialStore>,
}

impl ServerRepository {
    pub fn new(creds: Arc<dyn CredentialStore>) -> Self {
        Self { creds }
    }

    pub fn load_all(&self) -> Result<Vec<NavidromeServer>> {
        load_list(self.creds.as_ref(), keys::SERVERS)
    }

    pub fn upsert(&self, server: &NavidromeServer) -> Result<()> {
        let mut servers = self.load_all()?;
        match servers.iter_mut().find(|s| s.id == server.id) {
            Some(slot) => *slot = server.clone(),
            None => servers.push(server.clone()),
        }
        save_list(self.creds.as_ref(), keys::SERVERS, &servers)
    }

    pub fn delete(&self, id: &str) -> Result<()> {
        let servers: Vec<_> = self
            .load_all()?
            .into_iter()
            .filter(|s| s.id != id)
            .collect();
        save_list(self.creds.as_ref(), keys::SERVERS, &servers)?;
        self.creds
            .delete(&format!("{}{id}", keys::SERVER_PASSWORD_PREFIX))
    }

    pub fn save_password(&self, id: &str, password: &str) -> Result<()> {
        self.creds.write(
            &format!("{}{id}", keys::SERVER_PASSWORD_PREFIX),
            Some(password),
        )
    }

    pub fn load_password(&self, id: &str) -> Result<Option<String>> {
        self.creds
            .read(&format!("{}{id}", keys::SERVER_PASSWORD_PREFIX))
    }

    pub fn load_selected_id(&self) -> Result<Option<String>> {
        self.creds.read(keys::SELECTED_SERVER)
    }

    pub fn save_selected_id(&self, id: Option<&str>) -> Result<()> {
        save_selected(self.creds.as_ref(), keys::SELECTED_SERVER, id)
    }

    /// `ServersNotifier._load`: the server list, first migrating the legacy
    /// single-server keys into a "My Server" entry when the list is empty.
    pub fn load_migrating(&self) -> Result<Vec<NavidromeServer>> {
        let servers = self.load_all()?;
        if !servers.is_empty() {
            return Ok(servers);
        }
        let c = self.creds.as_ref();
        let (Some(url), Some(username), Some(password)) = (
            c.read(keys::LEGACY_SERVER_URL)?,
            c.read(keys::LEGACY_USERNAME)?,
            c.read(keys::LEGACY_PASSWORD)?,
        ) else {
            return Ok(servers);
        };
        let migrated = NavidromeServer {
            id: new_id(),
            name: "My Server".into(),
            url,
            username,
        };
        self.upsert(&migrated)?;
        self.save_password(&migrated.id, &password)?;
        self.save_selected_id(Some(&migrated.id))?;
        for k in [
            keys::LEGACY_SERVER_URL,
            keys::LEGACY_USERNAME,
            keys::LEGACY_PASSWORD,
        ] {
            c.delete(k)?;
        }
        Ok(vec![migrated])
    }

    /// `ServersNotifier.add`: auto-selects the first server ever added.
    pub fn add(&self, server: &NavidromeServer, password: &str) -> Result<()> {
        self.upsert(server)?;
        self.save_password(&server.id, password)?;
        if self.load_all()?.len() == 1 {
            self.save_selected_id(Some(&server.id))?;
        }
        Ok(())
    }

    /// `ServersNotifier.update`: an empty or absent password keeps the old one.
    pub fn update(&self, server: &NavidromeServer, new_password: Option<&str>) -> Result<()> {
        self.upsert(server)?;
        match new_password {
            Some(pw) if !pw.is_empty() => self.save_password(&server.id, pw),
            _ => Ok(()),
        }
    }

    /// `ServersNotifier.remove`: removing the selected server selects the
    /// first remaining one (or none). Returns the resulting selection.
    pub fn remove(&self, id: &str) -> Result<Option<String>> {
        self.delete(id)?;
        let selected = self.load_selected_id()?;
        if selected.as_deref() != Some(id) {
            return Ok(selected);
        }
        let next = self.load_all()?.into_iter().next().map(|s| s.id);
        self.save_selected_id(next.as_deref())?;
        Ok(next)
    }

    /// `selectedServerProvider`: the selected server if it still exists.
    pub fn selected(&self) -> Result<Option<NavidromeServer>> {
        let Some(id) = self.load_selected_id()? else {
            return Ok(None);
        };
        Ok(self.load_all()?.into_iter().find(|s| s.id == id))
    }

    /// `serverCredentialsProvider`: `None` without a selection or password.
    pub fn credentials(&self) -> Result<Option<ServerCredentials>> {
        let Some(server) = self.selected()? else {
            return Ok(None);
        };
        Ok(self
            .load_password(&server.id)?
            .map(|password| ServerCredentials {
                url: server.url,
                username: server.username,
                password,
            }))
    }
}

/// Blocking; async callers use `spawn_blocking`.
#[derive(Clone)]
pub struct LidarrRepository {
    creds: Arc<dyn CredentialStore>,
}

impl LidarrRepository {
    pub fn new(creds: Arc<dyn CredentialStore>) -> Self {
        Self { creds }
    }

    pub fn load_all(&self) -> Result<Vec<LidarrInstance>> {
        load_list(self.creds.as_ref(), keys::LIDARR_INSTANCES)
    }

    pub fn upsert(&self, instance: &LidarrInstance) -> Result<()> {
        let mut all = self.load_all()?;
        match all.iter_mut().find(|i| i.id == instance.id) {
            Some(slot) => *slot = instance.clone(),
            None => all.push(instance.clone()),
        }
        save_list(self.creds.as_ref(), keys::LIDARR_INSTANCES, &all)
    }

    pub fn delete(&self, id: &str) -> Result<()> {
        let all: Vec<_> = self
            .load_all()?
            .into_iter()
            .filter(|i| i.id != id)
            .collect();
        save_list(self.creds.as_ref(), keys::LIDARR_INSTANCES, &all)?;
        self.creds
            .delete(&format!("{}{id}", keys::LIDARR_API_KEY_PREFIX))
    }

    pub fn save_api_key(&self, id: &str, api_key: &str) -> Result<()> {
        self.creds.write(
            &format!("{}{id}", keys::LIDARR_API_KEY_PREFIX),
            Some(api_key),
        )
    }

    pub fn load_api_key(&self, id: &str) -> Result<Option<String>> {
        self.creds
            .read(&format!("{}{id}", keys::LIDARR_API_KEY_PREFIX))
    }

    pub fn load_selected_id(&self) -> Result<Option<String>> {
        self.creds.read(keys::LIDARR_SELECTED)
    }

    pub fn save_selected_id(&self, id: Option<&str>) -> Result<()> {
        save_selected(self.creds.as_ref(), keys::LIDARR_SELECTED, id)
    }

    /// `LidarrInstancesNotifier._load`: migrates the legacy single-instance
    /// keys into a "Lidarr" entry when the list is empty.
    pub fn load_migrating(&self) -> Result<Vec<LidarrInstance>> {
        let instances = self.load_all()?;
        if !instances.is_empty() {
            return Ok(instances);
        }
        let c = self.creds.as_ref();
        let (Some(url), Some(api_key)) = (
            c.read(keys::LEGACY_LIDARR_URL)?,
            c.read(keys::LEGACY_LIDARR_API_KEY)?,
        ) else {
            return Ok(instances);
        };
        let migrated = LidarrInstance {
            id: new_id(),
            name: "Lidarr".into(),
            url,
            default_root_folder_id: c
                .read(keys::LEGACY_LIDARR_ROOT_FOLDER_ID)?
                .as_deref()
                .and_then(dart_int_try_parse),
            default_root_folder_path: c.read(keys::LEGACY_LIDARR_ROOT_FOLDER_PATH)?,
            default_quality_profile_id: c
                .read(keys::LEGACY_LIDARR_QUALITY_PROFILE_ID)?
                .as_deref()
                .and_then(dart_int_try_parse),
            default_quality_profile_name: c.read(keys::LEGACY_LIDARR_QUALITY_PROFILE_NAME)?,
        };
        self.upsert(&migrated)?;
        self.save_api_key(&migrated.id, &api_key)?;
        self.save_selected_id(Some(&migrated.id))?;
        for k in keys::LEGACY_LIDARR_KEYS {
            c.delete(k)?;
        }
        Ok(vec![migrated])
    }

    /// `LidarrInstancesNotifier.add`: auto-selects the first instance.
    pub fn add(&self, instance: &LidarrInstance, api_key: &str) -> Result<()> {
        self.upsert(instance)?;
        self.save_api_key(&instance.id, api_key)?;
        if self.load_all()?.len() == 1 {
            self.save_selected_id(Some(&instance.id))?;
        }
        Ok(())
    }

    /// `LidarrInstancesNotifier.update`: empty or absent key keeps the old one.
    pub fn update(&self, instance: &LidarrInstance, new_api_key: Option<&str>) -> Result<()> {
        self.upsert(instance)?;
        match new_api_key {
            Some(k) if !k.is_empty() => self.save_api_key(&instance.id, k),
            _ => Ok(()),
        }
    }

    /// `LidarrInstancesNotifier.remove`: returns the resulting selection.
    pub fn remove(&self, id: &str) -> Result<Option<String>> {
        self.delete(id)?;
        let selected = self.load_selected_id()?;
        if selected.as_deref() != Some(id) {
            return Ok(selected);
        }
        let next = self.load_all()?.into_iter().next().map(|i| i.id);
        self.save_selected_id(next.as_deref())?;
        Ok(next)
    }

    /// `selectedLidarrInstanceProvider`.
    pub fn selected(&self) -> Result<Option<LidarrInstance>> {
        let Some(id) = self.load_selected_id()? else {
            return Ok(None);
        };
        Ok(self.load_all()?.into_iter().find(|i| i.id == id))
    }

    /// `lidarrCredentialsProvider`.
    pub fn credentials(&self) -> Result<Option<LidarrCredentials>> {
        let Some(instance) = self.selected()? else {
            return Ok(None);
        };
        Ok(self
            .load_api_key(&instance.id)?
            .map(|api_key| LidarrCredentials {
                url: instance.url,
                api_key,
            }))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::credentials::FileCredentialStore;

    fn creds() -> (tempfile::TempDir, Arc<dyn CredentialStore>) {
        let tmp = tempfile::tempdir().unwrap();
        let store = FileCredentialStore::open(tmp.path().join("c.json")).unwrap();
        (tmp, Arc::new(store))
    }

    fn server(id: &str) -> NavidromeServer {
        NavidromeServer {
            id: id.into(),
            name: id.into(),
            url: format!("https://{id}"),
            username: "u".into(),
        }
    }

    fn instance(id: &str) -> LidarrInstance {
        LidarrInstance {
            id: id.into(),
            name: id.into(),
            url: format!("http://{id}"),
            ..Default::default()
        }
    }

    #[test]
    fn int_parse() {
        assert_eq!(dart_int_try_parse("12"), Some(12));
        assert_eq!(dart_int_try_parse(" -3 "), Some(-3));
        assert_eq!(dart_int_try_parse("0x1f"), Some(31));
        assert_eq!(dart_int_try_parse(""), None);
        assert_eq!(dart_int_try_parse("1.5"), None);
        assert_eq!(dart_int_try_parse("abc"), None);
    }

    #[test]
    fn server_crud_and_selection() {
        let (_t, c) = creds();
        let repo = ServerRepository::new(c.clone());
        assert!(repo.load_migrating().unwrap().is_empty());
        repo.add(&server("a"), "pa").unwrap();
        assert_eq!(repo.load_selected_id().unwrap().as_deref(), Some("a"));
        repo.add(&server("b"), "pb").unwrap();
        assert_eq!(
            repo.load_selected_id().unwrap().as_deref(),
            Some("a"),
            "only the first add auto-selects"
        );
        assert_eq!(
            repo.credentials().unwrap(),
            Some(ServerCredentials {
                url: "https://a".into(),
                username: "u".into(),
                password: "pa".into()
            })
        );

        let renamed = NavidromeServer {
            name: "A2".into(),
            ..server("a")
        };
        repo.update(&renamed, Some("")).unwrap();
        assert_eq!(repo.load_password("a").unwrap().as_deref(), Some("pa"));
        repo.update(&renamed, Some("new")).unwrap();
        assert_eq!(repo.load_password("a").unwrap().as_deref(), Some("new"));
        assert_eq!(repo.load_all().unwrap(), vec![renamed, server("b")]);

        assert_eq!(repo.remove("b").unwrap().as_deref(), Some("a"));
        assert_eq!(repo.remove("a").unwrap(), None);
        assert_eq!(repo.load_password("a").unwrap(), None);
        assert_eq!(repo.load_selected_id().unwrap(), None);
        assert_eq!(repo.credentials().unwrap(), None);
    }

    #[test]
    fn removing_selected_selects_first_remaining() {
        let (_t, c) = creds();
        let repo = ServerRepository::new(c);
        repo.add(&server("a"), "p").unwrap();
        repo.add(&server("b"), "p").unwrap();
        repo.add(&server("c"), "p").unwrap();
        assert_eq!(repo.remove("a").unwrap().as_deref(), Some("b"));
        assert_eq!(repo.selected().unwrap(), Some(server("b")));
    }

    #[test]
    fn dart_written_server_json_parses() {
        let (_t, c) = creds();
        c.write(
            keys::SERVERS,
            Some(r#"[{"id":"x","name":"N","url":"https://h","username":"me"}]"#),
        )
        .unwrap();
        assert_eq!(
            ServerRepository::new(c).load_all().unwrap(),
            vec![NavidromeServer {
                id: "x".into(),
                name: "N".into(),
                url: "https://h".into(),
                username: "me".into()
            }]
        );
    }

    #[test]
    fn legacy_server_keys_migrate_once() {
        let (_t, c) = creds();
        c.write("server_url", Some("https://old")).unwrap();
        c.write("username", Some("me")).unwrap();
        c.write("password", Some("pw")).unwrap();
        let repo = ServerRepository::new(c.clone());
        let servers = repo.load_migrating().unwrap();
        assert_eq!(servers.len(), 1);
        let s = &servers[0];
        assert_eq!(
            (s.name.as_str(), s.url.as_str(), s.username.as_str()),
            ("My Server", "https://old", "me")
        );
        assert_eq!(repo.load_password(&s.id).unwrap().as_deref(), Some("pw"));
        assert_eq!(
            repo.load_selected_id().unwrap().as_deref(),
            Some(s.id.as_str())
        );
        for k in ["server_url", "username", "password"] {
            assert_eq!(c.read(k).unwrap(), None);
        }
        assert_eq!(repo.load_migrating().unwrap(), servers);
    }

    #[test]
    fn partial_legacy_server_keys_do_not_migrate() {
        let (_t, c) = creds();
        c.write("server_url", Some("https://old")).unwrap();
        c.write("username", Some("me")).unwrap();
        let repo = ServerRepository::new(c.clone());
        assert!(repo.load_migrating().unwrap().is_empty());
        assert_eq!(
            c.read("server_url").unwrap().as_deref(),
            Some("https://old")
        );
    }

    #[test]
    fn lidarr_crud_and_selection() {
        let (_t, c) = creds();
        let repo = LidarrRepository::new(c);
        repo.add(&instance("a"), "ka").unwrap();
        repo.add(&instance("b"), "kb").unwrap();
        assert_eq!(repo.load_selected_id().unwrap().as_deref(), Some("a"));
        assert_eq!(
            repo.credentials().unwrap(),
            Some(LidarrCredentials {
                url: "http://a".into(),
                api_key: "ka".into()
            })
        );
        repo.update(&instance("b"), None).unwrap();
        assert_eq!(repo.load_api_key("b").unwrap().as_deref(), Some("kb"));
        assert_eq!(repo.remove("a").unwrap().as_deref(), Some("b"));
        assert_eq!(repo.load_api_key("a").unwrap(), None);
        assert_eq!(repo.selected().unwrap(), Some(instance("b")));
    }

    #[test]
    fn legacy_lidarr_keys_migrate() {
        let (_t, c) = creds();
        for (k, v) in [
            ("lidarr_url", "http://l"),
            ("lidarr_api_key", "key"),
            ("lidarr_root_folder_id", "3"),
            ("lidarr_root_folder_path", "/music"),
            ("lidarr_quality_profile_id", "x"),
            ("lidarr_quality_profile_name", "Lossless"),
        ] {
            c.write(k, Some(v)).unwrap();
        }
        let repo = LidarrRepository::new(c.clone());
        let all = repo.load_migrating().unwrap();
        assert_eq!(all.len(), 1);
        let i = &all[0];
        assert_eq!(i.name, "Lidarr");
        assert_eq!(i.url, "http://l");
        assert_eq!(i.default_root_folder_id, Some(3));
        assert_eq!(i.default_root_folder_path.as_deref(), Some("/music"));
        assert_eq!(i.default_quality_profile_id, None);
        assert_eq!(i.default_quality_profile_name.as_deref(), Some("Lossless"));
        assert_eq!(repo.load_api_key(&i.id).unwrap().as_deref(), Some("key"));
        assert_eq!(
            repo.load_selected_id().unwrap().as_deref(),
            Some(i.id.as_str())
        );
        for k in keys::LEGACY_LIDARR_KEYS {
            assert_eq!(c.read(k).unwrap(), None);
        }
    }
}
