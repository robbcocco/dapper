use std::path::{Path, PathBuf};

use dapper_domain::{
    AppError, AppSettings, DeviceSettings, FilenameFormat, FolderStructure, Result,
    TranscodeFormat, TransferTask,
};
use parking_lot::Mutex;
use rusqlite::{Connection, OptionalExtension, Row, params};
use serde::Serialize;
use serde::de::DeserializeOwned;

use crate::{fsutil, queue, settings};

pub const DB_FILE: &str = "app.db";
pub const SETTINGS_FILE: &str = "settings.json";
pub const QUEUE_FILE: &str = "queue.json";

/// Ordered schema migrations; `PRAGMA user_version` = number applied.
const MIGRATIONS: &[&str] = &[
    // v1. Columns/defaults mirror Flutter's Drift `device_settings_table` at schema v8.
    r#"
    CREATE TABLE device_settings (
        device_path TEXT NOT NULL PRIMARY KEY,
        music_root_folder TEXT NOT NULL DEFAULT '',
        playlist_folder TEXT NOT NULL DEFAULT 'Playlists',
        folder_structure TEXT NOT NULL DEFAULT 'artistAlbum',
        filename_format TEXT NOT NULL DEFAULT 'discTrack',
        include_year INTEGER NOT NULL DEFAULT 0 CHECK (include_year IN (0, 1)),
        overwrite_existing INTEGER NOT NULL DEFAULT 0 CHECK (overwrite_existing IN (0, 1)),
        transcode_format TEXT NOT NULL DEFAULT 'original',
        transcode_max_bit_rate INTEGER NULL,
        use_zip_download INTEGER NOT NULL DEFAULT 1 CHECK (use_zip_download IN (0, 1)),
        custom_filename_template TEXT NOT NULL DEFAULT '',
        custom_folder_template TEXT NOT NULL DEFAULT '',
        auto_clean_metadata INTEGER NOT NULL DEFAULT 1 CHECK (auto_clean_metadata IN (0, 1)),
        auto_shrink_cover_art INTEGER NOT NULL DEFAULT 1 CHECK (auto_shrink_cover_art IN (0, 1))
    );
    CREATE TABLE meta (
        key TEXT NOT NULL PRIMARY KEY,
        value TEXT NOT NULL
    );
    "#,
];

pub(crate) const DEVICE_SETTINGS_COLUMNS: &str = "device_path, music_root_folder, playlist_folder, \
    folder_structure, filename_format, include_year, overwrite_existing, transcode_format, \
    transcode_max_bit_rate, use_zip_download, custom_filename_template, custom_folder_template, \
    auto_clean_metadata, auto_shrink_cover_art";

pub(crate) fn sql_err(e: rusqlite::Error) -> AppError {
    AppError::Storage(format!("database: {e}"))
}

/// Dart enum `.name`.
pub(crate) fn enum_name<T: Serialize>(v: T) -> String {
    match serde_json::to_value(v) {
        Ok(serde_json::Value::String(s)) => s,
        _ => unreachable!("unit enum variants serialise as strings"),
    }
}

/// Dart `values.firstWhere((e) => e.name == s, orElse: () => fallback)`.
pub(crate) fn parse_enum<T: DeserializeOwned>(s: &str, fallback: T) -> T {
    serde_json::from_value(serde_json::Value::String(s.to_owned())).unwrap_or(fallback)
}

/// Raw column values, before enum fallbacks are applied.
pub(crate) struct DeviceSettingsRow {
    pub device_path: String,
    pub music_root_folder: String,
    pub playlist_folder: String,
    pub folder_structure: String,
    pub filename_format: String,
    pub include_year: bool,
    pub overwrite_existing: bool,
    pub transcode_format: String,
    pub transcode_max_bit_rate: Option<i64>,
    pub use_zip_download: bool,
    pub custom_filename_template: String,
    pub custom_folder_template: String,
    pub auto_clean_metadata: bool,
    pub auto_shrink_cover_art: bool,
}

impl DeviceSettingsRow {
    /// Reads columns in [`DEVICE_SETTINGS_COLUMNS`] order.
    pub(crate) fn read(r: &Row<'_>) -> rusqlite::Result<Self> {
        Ok(Self {
            device_path: r.get(0)?,
            music_root_folder: r.get(1)?,
            playlist_folder: r.get(2)?,
            folder_structure: r.get(3)?,
            filename_format: r.get(4)?,
            include_year: r.get(5)?,
            overwrite_existing: r.get(6)?,
            transcode_format: r.get(7)?,
            transcode_max_bit_rate: r.get(8)?,
            use_zip_download: r.get(9)?,
            custom_filename_template: r.get(10)?,
            custom_folder_template: r.get(11)?,
            auto_clean_metadata: r.get(12)?,
            auto_shrink_cover_art: r.get(13)?,
        })
    }

    /// `DeviceSettingsNotifier.fromRow`: unknown enum names fall back to defaults.
    pub(crate) fn into_settings(self) -> DeviceSettings {
        DeviceSettings {
            device_path: self.device_path,
            music_root_folder: self.music_root_folder,
            playlist_folder: self.playlist_folder,
            folder_structure: parse_enum(&self.folder_structure, FolderStructure::ArtistAlbum),
            filename_format: parse_enum(&self.filename_format, FilenameFormat::DiscTrack),
            include_year: self.include_year,
            overwrite_existing: self.overwrite_existing,
            transcode_format: parse_enum(&self.transcode_format, TranscodeFormat::Original),
            transcode_max_bit_rate: self.transcode_max_bit_rate,
            use_zip_download: self.use_zip_download,
            custom_filename_template: self.custom_filename_template,
            custom_folder_template: self.custom_folder_template,
            auto_clean_metadata: self.auto_clean_metadata,
            auto_shrink_cover_art: self.auto_shrink_cover_art,
        }
    }
}

/// App-level persistent state rooted at the app support directory. All
/// methods block; async callers wrap them in `spawn_blocking`.
pub struct Store {
    dir: PathBuf,
    db: Mutex<Connection>,
}

impl Store {
    pub fn open(support_dir: impl AsRef<Path>) -> Result<Self> {
        let dir = support_dir.as_ref().to_path_buf();
        std::fs::create_dir_all(&dir)?;
        let mut conn = Connection::open(dir.join(DB_FILE)).map_err(sql_err)?;
        conn.pragma_update(None, "journal_mode", "WAL")
            .map_err(sql_err)?;
        conn.pragma_update(None, "synchronous", "NORMAL")
            .map_err(sql_err)?;
        conn.busy_timeout(std::time::Duration::from_secs(5))
            .map_err(sql_err)?;
        migrate(&mut conn)?;
        Ok(Self {
            dir,
            db: Mutex::new(conn),
        })
    }

    pub fn support_dir(&self) -> &Path {
        &self.dir
    }

    pub fn schema_version(&self) -> Result<i64> {
        self.db
            .lock()
            .pragma_query_value(None, "user_version", |r| r.get(0))
            .map_err(sql_err)
    }

    // ── meta ────────────────────────────────────────────────────────────────

    pub fn meta_get(&self, key: &str) -> Result<Option<String>> {
        self.db
            .lock()
            .query_row("SELECT value FROM meta WHERE key = ?1", [key], |r| r.get(0))
            .optional()
            .map_err(sql_err)
    }

    pub fn meta_set(&self, key: &str, value: &str) -> Result<()> {
        self.db
            .lock()
            .execute(
                "INSERT INTO meta (key, value) VALUES (?1, ?2) \
                 ON CONFLICT(key) DO UPDATE SET value = excluded.value",
                [key, value],
            )
            .map(drop)
            .map_err(sql_err)
    }

    // ── device settings ─────────────────────────────────────────────────────

    /// Stored settings for `device_path`, or `None` when the device was never
    /// saved (callers then use `DeviceSettings::new(device_path)`).
    pub fn device_settings(&self, device_path: &str) -> Result<Option<DeviceSettings>> {
        self.db
            .lock()
            .query_row(
                &format!(
                    "SELECT {DEVICE_SETTINGS_COLUMNS} FROM device_settings WHERE device_path = ?1"
                ),
                [device_path],
                DeviceSettingsRow::read,
            )
            .optional()
            .map(|r| r.map(DeviceSettingsRow::into_settings))
            .map_err(sql_err)
    }

    pub fn all_device_settings(&self) -> Result<Vec<DeviceSettings>> {
        let conn = self.db.lock();
        let mut stmt = conn
            .prepare(&format!(
                "SELECT {DEVICE_SETTINGS_COLUMNS} FROM device_settings"
            ))
            .map_err(sql_err)?;
        let rows = stmt
            .query_map([], DeviceSettingsRow::read)
            .map_err(sql_err)?
            .map(|r| r.map(DeviceSettingsRow::into_settings))
            .collect::<rusqlite::Result<Vec<_>>>()
            .map_err(sql_err)?;
        Ok(rows)
    }

    pub fn upsert_device_settings(&self, s: &DeviceSettings) -> Result<()> {
        upsert_device_settings(&self.db.lock(), s, true).map(drop)
    }

    /// Inserts only when no row exists; returns whether it inserted.
    pub(crate) fn insert_device_settings_if_absent(&self, s: &DeviceSettings) -> Result<bool> {
        upsert_device_settings(&self.db.lock(), s, false)
    }

    // ── app settings (settings.json) ────────────────────────────────────────

    pub fn settings_path(&self) -> PathBuf {
        self.dir.join(SETTINGS_FILE)
    }

    pub fn load_app_settings(&self) -> AppSettings {
        settings::load(&self.settings_path())
    }

    pub fn save_app_settings(&self, s: &AppSettings) -> Result<()> {
        settings::save(&self.settings_path(), s)
    }

    // ── transfer queue (queue.json) ─────────────────────────────────────────

    pub fn queue_path(&self) -> PathBuf {
        self.dir.join(QUEUE_FILE)
    }

    pub fn load_queue(&self) -> Vec<TransferTask> {
        queue::load_queue_file(&self.queue_path())
    }

    pub fn save_queue(&self, tasks: &[TransferTask]) -> Result<()> {
        queue::save_queue_file(&self.queue_path(), tasks)
    }

    /// Settings-page "reset": drops every device-settings row and the settings
    /// and queue files. Credentials are wiped separately via
    /// [`crate::CredentialStore::delete_all`]; the legacy-import marker stays
    /// so Flutter data is not re-imported.
    pub fn wipe_user_data(&self) -> Result<()> {
        self.db
            .lock()
            .execute("DELETE FROM device_settings", [])
            .map_err(sql_err)?;
        fsutil::remove_if_exists(&self.settings_path())?;
        fsutil::remove_if_exists(&self.queue_path())
    }
}

fn upsert_device_settings(conn: &Connection, s: &DeviceSettings, replace: bool) -> Result<bool> {
    let conflict = if replace {
        "ON CONFLICT(device_path) DO UPDATE SET music_root_folder = excluded.music_root_folder, \
         playlist_folder = excluded.playlist_folder, folder_structure = excluded.folder_structure, \
         filename_format = excluded.filename_format, include_year = excluded.include_year, \
         overwrite_existing = excluded.overwrite_existing, transcode_format = excluded.transcode_format, \
         transcode_max_bit_rate = excluded.transcode_max_bit_rate, use_zip_download = excluded.use_zip_download, \
         custom_filename_template = excluded.custom_filename_template, \
         custom_folder_template = excluded.custom_folder_template, \
         auto_clean_metadata = excluded.auto_clean_metadata, auto_shrink_cover_art = excluded.auto_shrink_cover_art"
    } else {
        "ON CONFLICT(device_path) DO NOTHING"
    };
    let n = conn
        .execute(
            &format!(
                "INSERT INTO device_settings ({DEVICE_SETTINGS_COLUMNS}) \
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14) {conflict}"
            ),
            params![
                s.device_path,
                s.music_root_folder,
                s.playlist_folder,
                enum_name(s.folder_structure),
                enum_name(s.filename_format),
                s.include_year,
                s.overwrite_existing,
                enum_name(s.transcode_format),
                s.transcode_max_bit_rate,
                s.use_zip_download,
                s.custom_filename_template,
                s.custom_folder_template,
                s.auto_clean_metadata,
                s.auto_shrink_cover_art,
            ],
        )
        .map_err(sql_err)?;
    Ok(n > 0)
}

fn migrate(conn: &mut Connection) -> Result<()> {
    let current: i64 = conn
        .pragma_query_value(None, "user_version", |r| r.get(0))
        .map_err(sql_err)?;
    let target = MIGRATIONS.len() as i64;
    if current > target {
        return Err(AppError::Storage(format!(
            "{DB_FILE} schema v{current} is newer than this build supports (v{target})"
        )));
    }
    for (i, sql) in MIGRATIONS.iter().enumerate().skip(current as usize) {
        let tx = conn.transaction().map_err(sql_err)?;
        tx.execute_batch(sql).map_err(sql_err)?;
        tx.pragma_update(None, "user_version", i as i64 + 1)
            .map_err(sql_err)?;
        tx.commit().map_err(sql_err)?;
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn open_creates_schema_and_is_idempotent() {
        let tmp = tempfile::tempdir().unwrap();
        let store = Store::open(tmp.path()).unwrap();
        assert_eq!(store.schema_version().unwrap(), MIGRATIONS.len() as i64);
        let mode: String = store
            .db
            .lock()
            .pragma_query_value(None, "journal_mode", |r| r.get(0))
            .unwrap();
        assert_eq!(mode, "wal");
        store.meta_set("k", "v").unwrap();
        drop(store);
        let store = Store::open(tmp.path()).unwrap();
        assert_eq!(store.schema_version().unwrap(), MIGRATIONS.len() as i64);
        assert_eq!(store.meta_get("k").unwrap().as_deref(), Some("v"));
        assert_eq!(store.meta_get("missing").unwrap(), None);
    }

    #[test]
    fn refuses_newer_schema() {
        let tmp = tempfile::tempdir().unwrap();
        let conn = Connection::open(tmp.path().join(DB_FILE)).unwrap();
        conn.pragma_update(None, "user_version", 99).unwrap();
        drop(conn);
        assert!(matches!(Store::open(tmp.path()), Err(AppError::Storage(_))));
    }

    #[test]
    fn raw_insert_gets_drift_defaults() {
        let tmp = tempfile::tempdir().unwrap();
        let store = Store::open(tmp.path()).unwrap();
        store
            .db
            .lock()
            .execute(
                "INSERT INTO device_settings (device_path) VALUES ('/v')",
                [],
            )
            .unwrap();
        assert_eq!(
            store.device_settings("/v").unwrap(),
            Some(DeviceSettings::new("/v"))
        );
    }

    #[test]
    fn device_settings_crud() {
        let tmp = tempfile::tempdir().unwrap();
        let store = Store::open(tmp.path()).unwrap();
        assert_eq!(store.device_settings("/v").unwrap(), None);
        let mut s = DeviceSettings {
            music_root_folder: "Music".into(),
            folder_structure: FolderStructure::Custom,
            filename_format: FilenameFormat::Track,
            include_year: true,
            overwrite_existing: true,
            transcode_format: TranscodeFormat::Opus,
            transcode_max_bit_rate: Some(192),
            use_zip_download: false,
            custom_filename_template: "{track} {title}".into(),
            custom_folder_template: "{artist}/{album}".into(),
            auto_clean_metadata: false,
            auto_shrink_cover_art: false,
            ..DeviceSettings::new("/v")
        };
        store.upsert_device_settings(&s).unwrap();
        assert_eq!(store.device_settings("/v").unwrap().as_ref(), Some(&s));
        s.transcode_max_bit_rate = None;
        s.playlist_folder = "P".into();
        store.upsert_device_settings(&s).unwrap();
        store
            .upsert_device_settings(&DeviceSettings::new("/w"))
            .unwrap();
        assert_eq!(store.device_settings("/v").unwrap().as_ref(), Some(&s));
        let mut all = store.all_device_settings().unwrap();
        all.sort_by(|a, b| a.device_path.cmp(&b.device_path));
        assert_eq!(all, vec![s.clone(), DeviceSettings::new("/w")]);
        assert!(
            !store
                .insert_device_settings_if_absent(&DeviceSettings::new("/v"))
                .unwrap()
        );
        assert_eq!(store.device_settings("/v").unwrap().as_ref(), Some(&s));
    }

    #[test]
    fn unknown_enum_names_fall_back() {
        let tmp = tempfile::tempdir().unwrap();
        let store = Store::open(tmp.path()).unwrap();
        store
            .db
            .lock()
            .execute(
                "INSERT INTO device_settings (device_path, folder_structure, filename_format, transcode_format) \
                 VALUES ('/v', 'bogus', 'nope', 'flac')",
                [],
            )
            .unwrap();
        let s = store.device_settings("/v").unwrap().unwrap();
        assert_eq!(s.folder_structure, FolderStructure::ArtistAlbum);
        assert_eq!(s.filename_format, FilenameFormat::DiscTrack);
        assert_eq!(s.transcode_format, TranscodeFormat::Original);
    }

    #[test]
    fn enum_names_match_dart() {
        assert_eq!(
            enum_name(FolderStructure::ArtistAlbumYear),
            "artistAlbumYear"
        );
        assert_eq!(enum_name(FilenameFormat::DiscTrack), "discTrack");
        assert_eq!(enum_name(TranscodeFormat::Mp3), "mp3");
    }

    #[test]
    fn wipe_user_data_keeps_meta() {
        let tmp = tempfile::tempdir().unwrap();
        let store = Store::open(tmp.path()).unwrap();
        store
            .upsert_device_settings(&DeviceSettings::new("/v"))
            .unwrap();
        store
            .save_app_settings(&AppSettings {
                transfer_concurrency: 2,
            })
            .unwrap();
        store.save_queue(&[]).unwrap();
        store.meta_set("k", "v").unwrap();
        store.wipe_user_data().unwrap();
        assert!(store.all_device_settings().unwrap().is_empty());
        assert!(!store.settings_path().exists());
        assert!(!store.queue_path().exists());
        assert_eq!(store.meta_get("k").unwrap().as_deref(), Some("v"));
        store.wipe_user_data().unwrap();
    }
}
