//! Persistent app state: app.db, settings, credentials, transfer queue file, legacy Flutter import.

mod credentials;
mod db;
mod fsutil;
pub mod keys;
mod legacy;
mod queue;
mod repos;
mod settings;

pub use credentials::{
    CREDENTIALS_FILE, CredentialStore, FallbackCredentialStore, FileCredentialStore,
    KEYCHAIN_SERVICE, NativeCredentialStore, build_default_credential_store,
};
pub use db::{DB_FILE, QUEUE_FILE, SETTINGS_FILE, Store};
pub use legacy::{
    ImportReport, LEGACY_CREDENTIALS_FILE, LEGACY_DB_FILE, LEGACY_IMPORT_MARKER, LEGACY_QUEUE_FILE,
    LEGACY_SECRETS_IMPORT_MARKER, LEGACY_SETTINGS_FILE, import_legacy, import_legacy_with,
};
pub use queue::{encode_queue, load_queue_file, parse_queue, save_queue_file};
pub use repos::{LidarrCredentials, LidarrRepository, ServerCredentials, ServerRepository, new_id};
pub use settings::with_transfer_concurrency;
