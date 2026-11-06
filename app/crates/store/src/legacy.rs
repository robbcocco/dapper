//! One-time import of the Flutter app's persisted state. Legacy files are
//! only ever read; nothing in the legacy directory is modified.

use std::collections::{BTreeMap, HashMap};
use std::path::Path;

use dapper_domain::{AppSettings, LidarrInstance, NavidromeServer, Result};
use rusqlite::{Connection, OpenFlags};
use serde::Serialize;

use crate::credentials::{self, CredentialStore};
use crate::db::{DeviceSettingsRow, Store};
use crate::{keys, queue, settings};

/// `meta` key recording that the file/database import ran (value: unix seconds).
pub const LEGACY_IMPORT_MARKER: &str = "legacy_flutter_import";
/// `meta` key recording that Flutter's secure storage was read successfully.
/// Kept separate so an unreadable keychain (e.g. a build lacking the keychain
/// entitlement) is retried on later launches without redoing the rest.
pub const LEGACY_SECRETS_IMPORT_MARKER: &str = "legacy_flutter_secrets_import";

pub const LEGACY_DB_FILE: &str = "dapper.db";
pub const LEGACY_DEVICE_SETTINGS_TABLE: &str = "device_settings_table";
pub const LEGACY_SETTINGS_FILE: &str = "app_settings.json";
pub const LEGACY_QUEUE_FILE: &str = "transfer_queue.json";
pub const LEGACY_CREDENTIALS_FILE: &str = "credentials.json";
/// Windows `flutter_secure_storage` file (DPAPI-encrypted JSON map).
pub const LEGACY_WINDOWS_SECRETS_FILE: &str = "flutter_secure_storage.dat";

/// Outcome of [`import_legacy`]. Contains key names and paths only, never
/// secret values.
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ImportReport {
    /// Both markers were already set; nothing was read.
    pub already_imported: bool,
    pub device_settings: usize,
    pub app_settings: bool,
    pub queue_tasks: usize,
    /// Credential-store keys copied (server/instance lists, ids, secrets).
    pub secrets: usize,
    /// Legacy sources that do not exist (normal on a fresh install).
    pub missing: Vec<String>,
    /// Sources that exist but could not be (fully) imported.
    pub issues: Vec<String>,
}

/// Imports Flutter data from `legacy_dir` once; subsequent calls return
/// `already_imported`. Legacy problems are reported, not returned as errors.
/// A failed secure-storage read leaves its marker unset so the secrets part
/// is retried next launch (`credentials.json` gaps are filled each attempt;
/// existing keys are never overwritten).
pub fn import_legacy(
    legacy_dir: &Path,
    store: &Store,
    creds: &dyn CredentialStore,
) -> Result<ImportReport> {
    import_legacy_with(
        legacy_dir,
        store,
        creds,
        dapper_platform::secrets::read_legacy_flutter_secrets,
    )
}

/// [`import_legacy`] with an injectable reader for Flutter's secure storage.
pub fn import_legacy_with(
    legacy_dir: &Path,
    store: &Store,
    creds: &dyn CredentialStore,
    read_legacy_secrets: impl FnOnce(&Path) -> Result<HashMap<String, String>>,
) -> Result<ImportReport> {
    let mut report = ImportReport::default();
    let files_done = store.meta_get(LEGACY_IMPORT_MARKER)?.is_some();
    let secrets_done = store.meta_get(LEGACY_SECRETS_IMPORT_MARKER)?.is_some();
    if files_done && secrets_done {
        report.already_imported = true;
        return Ok(report);
    }
    let now = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map_or(0, |d| d.as_secs())
        .to_string();
    if !files_done {
        import_device_settings(legacy_dir, store, &mut report)?;
        import_app_settings(legacy_dir, store, &mut report);
        import_queue(legacy_dir, store, &mut report);
        store.meta_set(LEGACY_IMPORT_MARKER, &now)?;
    }
    if !secrets_done && import_secrets(legacy_dir, creds, read_legacy_secrets, &mut report) {
        store.meta_set(LEGACY_SECRETS_IMPORT_MARKER, &now)?;
    }
    if !report.issues.is_empty() {
        tracing::warn!(issues = ?report.issues, "legacy import finished with issues");
    }
    Ok(report)
}

/// (column, SQL default) in `DEVICE_SETTINGS_COLUMNS` order. Older Drift
/// schemas lack later columns; missing or NULL values take the v8 default.
const LEGACY_COLUMNS: [(&str, &str); 14] = [
    ("device_path", ""),
    ("music_root_folder", "''"),
    ("playlist_folder", "'Playlists'"),
    ("folder_structure", "'artistAlbum'"),
    ("filename_format", "'discTrack'"),
    ("include_year", "0"),
    ("overwrite_existing", "0"),
    ("transcode_format", "'original'"),
    ("transcode_max_bit_rate", "NULL"),
    ("use_zip_download", "1"),
    ("custom_filename_template", "''"),
    ("custom_folder_template", "''"),
    ("auto_clean_metadata", "1"),
    ("auto_shrink_cover_art", "1"),
];

fn import_device_settings(
    legacy_dir: &Path,
    store: &Store,
    report: &mut ImportReport,
) -> Result<()> {
    let path = legacy_dir.join(LEGACY_DB_FILE);
    if !path.exists() {
        report.missing.push(LEGACY_DB_FILE.into());
        return Ok(());
    }
    let rows = match read_legacy_device_rows(&path) {
        Ok(rows) => rows,
        Err(e) => {
            report.issues.push(format!("{LEGACY_DB_FILE}: {e}"));
            return Ok(());
        }
    };
    for row in rows {
        match row {
            Ok(row) => {
                if store.insert_device_settings_if_absent(&row.into_settings())? {
                    report.device_settings += 1;
                }
            }
            Err(e) => report
                .issues
                .push(format!("{LEGACY_DB_FILE}: skipped a device row: {e}")),
        }
    }
    Ok(())
}

fn read_legacy_device_rows(
    path: &Path,
) -> rusqlite::Result<Vec<rusqlite::Result<DeviceSettingsRow>>> {
    let conn = Connection::open_with_flags(
        path,
        OpenFlags::SQLITE_OPEN_READ_ONLY | OpenFlags::SQLITE_OPEN_NO_MUTEX,
    )?;
    let present: Vec<String> = conn
        .prepare(&format!(
            "PRAGMA table_info({LEGACY_DEVICE_SETTINGS_TABLE})"
        ))?
        .query_map([], |r| r.get::<_, String>(1))?
        .collect::<rusqlite::Result<_>>()?;
    if !present.iter().any(|c| c == "device_path") {
        return Err(rusqlite::Error::InvalidParameterName(format!(
            "no {LEGACY_DEVICE_SETTINGS_TABLE} table with a device_path column"
        )));
    }
    let select: Vec<String> = LEGACY_COLUMNS
        .iter()
        .map(
            |(col, default)| match (present.iter().any(|c| c == col), *col) {
                (_, "device_path") | (true, "transcode_max_bit_rate") => (*col).to_owned(),
                (true, _) => format!("COALESCE({col}, {default})"),
                (false, _) => (*default).to_owned(),
            },
        )
        .collect();
    let sql = format!(
        "SELECT {} FROM {LEGACY_DEVICE_SETTINGS_TABLE}",
        select.join(", ")
    );
    let mut stmt = conn.prepare(&sql)?;
    let rows = stmt.query_map([], DeviceSettingsRow::read)?.collect();
    Ok(rows)
}

fn import_app_settings(legacy_dir: &Path, store: &Store, report: &mut ImportReport) {
    let path = legacy_dir.join(LEGACY_SETTINGS_FILE);
    let raw = match std::fs::read_to_string(&path) {
        Ok(raw) => raw,
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => {
            report.missing.push(LEGACY_SETTINGS_FILE.into());
            return;
        }
        Err(e) => {
            report.issues.push(format!("{LEGACY_SETTINGS_FILE}: {e}"));
            return;
        }
    };
    if store.settings_path().exists() {
        report.issues.push(format!(
            "{LEGACY_SETTINGS_FILE}: skipped, {} already exists",
            crate::SETTINGS_FILE
        ));
        return;
    }
    let value = match serde_json::from_str::<serde_json::Value>(&raw) {
        Ok(v @ serde_json::Value::Object(_)) => v,
        _ => {
            report.issues.push(format!(
                "{LEGACY_SETTINGS_FILE}: not a JSON object, skipped"
            ));
            return;
        }
    };
    match settings::save(&store.settings_path(), &AppSettings::from_json(&value)) {
        Ok(()) => report.app_settings = true,
        Err(e) => report.issues.push(format!("{LEGACY_SETTINGS_FILE}: {e}")),
    }
}

fn import_queue(legacy_dir: &Path, store: &Store, report: &mut ImportReport) {
    let path = legacy_dir.join(LEGACY_QUEUE_FILE);
    let raw = match std::fs::read_to_string(&path) {
        Ok(raw) => raw,
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => {
            report.missing.push(LEGACY_QUEUE_FILE.into());
            return;
        }
        Err(e) => {
            report.issues.push(format!("{LEGACY_QUEUE_FILE}: {e}"));
            return;
        }
    };
    if store.queue_path().exists() {
        report.issues.push(format!(
            "{LEGACY_QUEUE_FILE}: skipped, {} already exists",
            crate::QUEUE_FILE
        ));
        return;
    }
    let tasks = match queue::try_parse_queue(&raw) {
        Ok(tasks) => tasks,
        Err(e) => {
            report
                .issues
                .push(format!("{LEGACY_QUEUE_FILE}: unreadable, skipped: {e}"));
            return;
        }
    };
    match store.save_queue(&tasks) {
        Ok(()) => report.queue_tasks = tasks.len(),
        Err(e) => report.issues.push(format!("{LEGACY_QUEUE_FILE}: {e}")),
    }
}

/// Returns whether Flutter's secure storage was read (the retry condition).
fn import_secrets(
    legacy_dir: &Path,
    creds: &dyn CredentialStore,
    read_legacy_secrets: impl FnOnce(&Path) -> Result<HashMap<String, String>>,
    report: &mut ImportReport,
) -> bool {
    // Flutter used the keychain whenever it worked and the file only after a
    // keychain failure, so keychain values win and the file fills gaps.
    let mut merged: BTreeMap<String, String> = BTreeMap::new();
    let file_path = legacy_dir.join(LEGACY_CREDENTIALS_FILE);
    if file_path.exists() {
        merged.extend(credentials::load_map(&file_path));
    } else {
        report.missing.push(LEGACY_CREDENTIALS_FILE.into());
    }
    let read_ok = match read_legacy_secrets(legacy_dir) {
        Ok(secrets) => {
            merged.extend(secrets);
            true
        }
        Err(e) if flutter_data_present(legacy_dir) => {
            report
                .issues
                .push(format!("secure storage: {e} (will retry next launch)"));
            false
        }
        // No sign the Flutter app ever ran here: nothing worth warning about,
        // but leave the marker unset so a build that can read it still tries.
        Err(e) => {
            tracing::debug!("legacy secure storage not readable, no Flutter data present: {e}");
            false
        }
    };

    for (key, value) in merged {
        if !keys::is_app_key(&key) {
            continue;
        }
        let valid = match key.as_str() {
            keys::SERVERS => serde_json::from_str::<Vec<NavidromeServer>>(&value).is_ok(),
            keys::LIDARR_INSTANCES => serde_json::from_str::<Vec<LidarrInstance>>(&value).is_ok(),
            _ => true,
        };
        if !valid {
            report
                .issues
                .push(format!("secure storage: {key} is malformed, skipped"));
            continue;
        }
        match creds.read(&key) {
            Ok(Some(_)) => continue,
            Ok(None) => {}
            Err(e) => {
                report
                    .issues
                    .push(format!("credential store: reading {key}: {e}"));
                continue;
            }
        }
        match creds.write(&key, Some(&value)) {
            Ok(()) => report.secrets += 1,
            Err(e) => report
                .issues
                .push(format!("credential store: writing {key}: {e}")),
        }
    }
    read_ok
}

/// Whether the Flutter app left any file behind in `legacy_dir`.
fn flutter_data_present(legacy_dir: &Path) -> bool {
    [
        LEGACY_DB_FILE,
        LEGACY_SETTINGS_FILE,
        LEGACY_QUEUE_FILE,
        LEGACY_CREDENTIALS_FILE,
        LEGACY_WINDOWS_SECRETS_FILE,
    ]
    .iter()
    .any(|f| legacy_dir.join(f).exists())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::credentials::FileCredentialStore;
    use crate::repos::{LidarrRepository, ServerRepository};
    use dapper_domain::{
        AppError, DeviceSettings, FilenameFormat, FolderStructure, TranscodeFormat, TransferStatus,
    };
    use std::sync::Arc;

    /// Drift's v8 `device_settings_table` DDL.
    const DRIFT_V8: &str = r#"CREATE TABLE IF NOT EXISTS "device_settings_table" ("device_path" TEXT NOT NULL, "music_root_folder" TEXT NOT NULL DEFAULT '', "playlist_folder" TEXT NOT NULL DEFAULT 'Playlists', "folder_structure" TEXT NOT NULL DEFAULT 'artistAlbum', "include_track_number" INTEGER NOT NULL DEFAULT 1 CHECK ("include_track_number" IN (0, 1)), "include_year" INTEGER NOT NULL DEFAULT 0 CHECK ("include_year" IN (0, 1)), "overwrite_existing" INTEGER NOT NULL DEFAULT 0 CHECK ("overwrite_existing" IN (0, 1)), "filename_format" TEXT NOT NULL DEFAULT 'discTrack', "transcode_format" TEXT NOT NULL DEFAULT 'original', "transcode_max_bit_rate" INTEGER NULL, "use_zip_download" INTEGER NOT NULL DEFAULT 1 CHECK ("use_zip_download" IN (0, 1)), "custom_filename_template" TEXT NOT NULL DEFAULT '', "custom_folder_template" TEXT NOT NULL DEFAULT '', "auto_clean_metadata" INTEGER NOT NULL DEFAULT 1 CHECK ("auto_clean_metadata" IN (0, 1)), "auto_shrink_cover_art" INTEGER NOT NULL DEFAULT 1 CHECK ("auto_shrink_cover_art" IN (0, 1)), PRIMARY KEY ("device_path"));"#;

    struct Env {
        _tmp: tempfile::TempDir,
        legacy: std::path::PathBuf,
        store: Store,
        creds: Arc<dyn CredentialStore>,
    }

    fn env() -> Env {
        let tmp = tempfile::tempdir().unwrap();
        let legacy = tmp.path().join("legacy");
        let new = tmp.path().join("new");
        std::fs::create_dir_all(&legacy).unwrap();
        let store = Store::open(&new).unwrap();
        let creds: Arc<dyn CredentialStore> =
            Arc::new(FileCredentialStore::open(new.join(credentials::CREDENTIALS_FILE)).unwrap());
        Env {
            _tmp: tmp,
            legacy,
            store,
            creds,
        }
    }

    fn no_secrets(_: &Path) -> Result<HashMap<String, String>> {
        Ok(HashMap::new())
    }

    fn snapshot(dir: &Path) -> BTreeMap<String, Vec<u8>> {
        std::fs::read_dir(dir)
            .unwrap()
            .map(|e| {
                let e = e.unwrap();
                (
                    e.file_name().to_string_lossy().into_owned(),
                    std::fs::read(e.path()).unwrap(),
                )
            })
            .collect()
    }

    #[test]
    fn empty_legacy_dir_reports_missing_and_marks_done() {
        let e = env();
        let r = import_legacy_with(&e.legacy, &e.store, e.creds.as_ref(), no_secrets).unwrap();
        assert!(!r.already_imported);
        assert_eq!(
            r.missing,
            [
                LEGACY_DB_FILE,
                LEGACY_SETTINGS_FILE,
                LEGACY_QUEUE_FILE,
                LEGACY_CREDENTIALS_FILE
            ]
        );
        assert!(r.issues.is_empty());
        assert!(e.store.meta_get(LEGACY_IMPORT_MARKER).unwrap().is_some());
        let again = import_legacy_with(&e.legacy, &e.store, e.creds.as_ref(), |_| {
            panic!("must not read")
        })
        .unwrap();
        assert!(again.already_imported);
    }

    #[test]
    fn imports_everything_without_touching_legacy_files() {
        let e = env();
        let conn = Connection::open(e.legacy.join(LEGACY_DB_FILE)).unwrap();
        conn.execute_batch(DRIFT_V8).unwrap();
        conn.execute_batch(
            r#"INSERT INTO device_settings_table (device_path, music_root_folder, folder_structure, filename_format,
                   include_year, transcode_format, transcode_max_bit_rate, use_zip_download, custom_folder_template,
                   auto_clean_metadata)
               VALUES ('/Volumes/A', 'Music', 'custom', 'track', 1, 'opus', 128, 0, '{artist}', 0);
               INSERT INTO device_settings_table (device_path, folder_structure) VALUES ('/Volumes/B', 'gone');"#,
        )
        .unwrap();
        drop(conn);
        std::fs::write(
            e.legacy.join(LEGACY_SETTINGS_FILE),
            r#"{"transferConcurrency":2}"#,
        )
        .unwrap();
        std::fs::write(
            e.legacy.join(LEGACY_QUEUE_FILE),
            r#"[{"id":"t1","song":{"id":"s1","title":"T"},"devicePath":"/Volumes/A","status":"inProgress"},
                {"id":"t2","song":{"id":"s2","title":"U"},"devicePath":"/Volumes/A","status":"failed","errorMessage":"x"}]"#,
        )
        .unwrap();
        std::fs::write(
            e.legacy.join(LEGACY_CREDENTIALS_FILE),
            r#"{"lidarr_instances":"[{\"id\":\"l1\",\"name\":\"L\",\"url\":\"http://l\",\"defaultRootFolderId\":null}]","lidarr_api_key_l1":"file-key","server_password_s1":"stale","junk":"x"}"#,
        )
        .unwrap();
        let before = snapshot(&e.legacy);

        let secrets = |_: &Path| {
            Ok(HashMap::from([
                (
                    "navidrome_servers".to_owned(),
                    r#"[{"id":"s1","name":"N","url":"https://n","username":"me"}]"#.to_owned(),
                ),
                ("selected_server_id".to_owned(), "s1".to_owned()),
                ("server_password_s1".to_owned(), "pw".to_owned()),
                ("lidarr_selected_instance_id".to_owned(), "l1".to_owned()),
                ("unrelated".to_owned(), "x".to_owned()),
            ]))
        };
        let r = import_legacy_with(&e.legacy, &e.store, e.creds.as_ref(), secrets).unwrap();
        assert!(r.issues.is_empty(), "{:?}", r.issues);
        assert!(r.missing.is_empty());
        assert_eq!(
            (r.device_settings, r.app_settings, r.queue_tasks, r.secrets),
            (2, true, 2, 6)
        );
        assert_eq!(
            snapshot(&e.legacy),
            before,
            "legacy files must be untouched"
        );

        let a = e.store.device_settings("/Volumes/A").unwrap().unwrap();
        assert_eq!(
            a,
            DeviceSettings {
                music_root_folder: "Music".into(),
                folder_structure: FolderStructure::Custom,
                filename_format: FilenameFormat::Track,
                include_year: true,
                transcode_format: TranscodeFormat::Opus,
                transcode_max_bit_rate: Some(128),
                use_zip_download: false,
                custom_folder_template: "{artist}".into(),
                auto_clean_metadata: false,
                ..DeviceSettings::new("/Volumes/A")
            }
        );
        assert_eq!(
            e.store.device_settings("/Volumes/B").unwrap(),
            Some(DeviceSettings::new("/Volumes/B"))
        );
        assert_eq!(e.store.load_app_settings().transfer_concurrency, 2);
        let q = e.store.load_queue();
        assert_eq!(q.len(), 2);
        assert_eq!(q[0].status, TransferStatus::Queued);
        assert_eq!(q[1].error_message.as_deref(), Some("x"));

        let servers = ServerRepository::new(e.creds.clone());
        assert_eq!(
            servers.credentials().unwrap().unwrap().password,
            "pw",
            "keychain wins over file"
        );
        let lidarr = LidarrRepository::new(e.creds.clone());
        assert_eq!(lidarr.credentials().unwrap().unwrap().api_key, "file-key");
        assert_eq!(e.creds.read("junk").unwrap(), None);
        assert_eq!(e.creds.read("unrelated").unwrap(), None);
    }

    #[test]
    fn old_drift_schema_and_partial_failures_are_reported() {
        let e = env();
        // Drift v2 shape: no filename_format or later columns.
        let conn = Connection::open(e.legacy.join(LEGACY_DB_FILE)).unwrap();
        conn.execute_batch(
            r#"CREATE TABLE device_settings_table (device_path TEXT NOT NULL PRIMARY KEY,
                 music_root_folder TEXT NOT NULL DEFAULT '', playlist_folder TEXT NOT NULL DEFAULT 'Playlists',
                 folder_structure TEXT NOT NULL DEFAULT 'artistAlbum', include_track_number INTEGER NOT NULL DEFAULT 1,
                 include_year INTEGER NOT NULL DEFAULT 0, overwrite_existing INTEGER NOT NULL DEFAULT 0);
               INSERT INTO device_settings_table (device_path, playlist_folder) VALUES ('/V', 'Lists');"#,
        )
        .unwrap();
        drop(conn);
        std::fs::write(e.legacy.join(LEGACY_SETTINGS_FILE), "{broken").unwrap();
        std::fs::write(e.legacy.join(LEGACY_QUEUE_FILE), "not json").unwrap();
        let secrets = |_: &Path| -> Result<HashMap<String, String>> {
            Err(AppError::Storage("keychain locked".into()))
        };
        let r = import_legacy_with(&e.legacy, &e.store, e.creds.as_ref(), secrets).unwrap();
        assert_eq!(r.device_settings, 1);
        assert!(!r.app_settings);
        assert_eq!(r.queue_tasks, 0);
        assert_eq!(r.issues.len(), 3, "{:?}", r.issues);
        assert_eq!(
            e.store.device_settings("/V").unwrap(),
            Some(DeviceSettings {
                playlist_folder: "Lists".into(),
                ..DeviceSettings::new("/V")
            })
        );
        assert!(!e.store.settings_path().exists());
        assert!(!e.store.queue_path().exists());
        assert!(e.store.meta_get(LEGACY_IMPORT_MARKER).unwrap().is_some());
        assert!(
            e.store
                .meta_get(LEGACY_SECRETS_IMPORT_MARKER)
                .unwrap()
                .is_none()
        );

        // Next launch: only the secure-storage part is retried.
        let secrets = |_: &Path| Ok(HashMap::from([("password".to_owned(), "pw".to_owned())]));
        let r = import_legacy_with(&e.legacy, &e.store, e.creds.as_ref(), secrets).unwrap();
        assert!(!r.already_imported);
        assert_eq!(
            (r.device_settings, r.app_settings, r.queue_tasks, r.secrets),
            (0, false, 0, 1)
        );
        assert!(r.issues.is_empty(), "{:?}", r.issues);
        assert_eq!(e.creds.read("password").unwrap().as_deref(), Some("pw"));
        assert!(
            e.store
                .meta_get(LEGACY_SECRETS_IMPORT_MARKER)
                .unwrap()
                .is_some()
        );
        let again = import_legacy_with(&e.legacy, &e.store, e.creds.as_ref(), |_| {
            panic!("must not read")
        })
        .unwrap();
        assert!(again.already_imported);
    }

    #[test]
    fn unusable_db_and_malformed_lists_do_not_fail() {
        let e = env();
        std::fs::write(
            e.legacy.join(LEGACY_DB_FILE),
            b"definitely not sqlite, just some bytes here....",
        )
        .unwrap();
        let secrets = |_: &Path| {
            Ok(HashMap::from([
                ("navidrome_servers".to_owned(), "{oops".to_owned()),
                ("password".to_owned(), "legacy-pw".to_owned()),
            ]))
        };
        let r = import_legacy_with(&e.legacy, &e.store, e.creds.as_ref(), secrets).unwrap();
        assert_eq!(r.device_settings, 0);
        assert_eq!(r.secrets, 1);
        assert_eq!(r.issues.len(), 2, "{:?}", r.issues);
        assert_eq!(e.creds.read("navidrome_servers").unwrap(), None);
        assert_eq!(
            e.creds.read("password").unwrap().as_deref(),
            Some("legacy-pw")
        );
    }

    #[test]
    fn existing_new_data_is_not_overwritten() {
        let e = env();
        e.store
            .save_app_settings(&AppSettings {
                transfer_concurrency: 3,
            })
            .unwrap();
        e.creds.write("selected_server_id", Some("new")).unwrap();
        std::fs::write(
            e.legacy.join(LEGACY_SETTINGS_FILE),
            r#"{"transferConcurrency":1}"#,
        )
        .unwrap();
        let secrets = |_: &Path| {
            Ok(HashMap::from([(
                "selected_server_id".to_owned(),
                "old".to_owned(),
            )]))
        };
        let r = import_legacy_with(&e.legacy, &e.store, e.creds.as_ref(), secrets).unwrap();
        assert!(!r.app_settings);
        assert_eq!(r.secrets, 0);
        assert_eq!(e.store.load_app_settings().transfer_concurrency, 3);
        assert_eq!(
            e.creds.read("selected_server_id").unwrap().as_deref(),
            Some("new")
        );
    }

    #[test]
    fn unreadable_secure_storage_is_quiet_without_flutter_data() {
        let e = env();
        let locked = |_: &Path| -> Result<HashMap<String, String>> {
            Err(AppError::Storage("missing keychain entitlement".into()))
        };
        let r = import_legacy_with(&e.legacy, &e.store, e.creds.as_ref(), locked).unwrap();
        assert!(r.issues.is_empty(), "{:?}", r.issues);
        assert!(
            e.store
                .meta_get(LEGACY_SECRETS_IMPORT_MARKER)
                .unwrap()
                .is_none()
        );

        std::fs::write(e.legacy.join(LEGACY_WINDOWS_SECRETS_FILE), b"x").unwrap();
        let r = import_legacy_with(&e.legacy, &e.store, e.creds.as_ref(), locked).unwrap();
        assert_eq!(r.issues.len(), 1, "{:?}", r.issues);
    }
}
