//! Credential-store key names, identical to the Flutter app's.

pub const SERVERS: &str = "navidrome_servers";
pub const SELECTED_SERVER: &str = "selected_server_id";
pub const SERVER_PASSWORD_PREFIX: &str = "server_password_";
pub const LIDARR_INSTANCES: &str = "lidarr_instances";
pub const LIDARR_SELECTED: &str = "lidarr_selected_instance_id";
pub const LIDARR_API_KEY_PREFIX: &str = "lidarr_api_key_";

/// Pre-multi-server keys, migrated on first load.
pub const LEGACY_SERVER_URL: &str = "server_url";
pub const LEGACY_USERNAME: &str = "username";
pub const LEGACY_PASSWORD: &str = "password";
pub const LEGACY_LIDARR_URL: &str = "lidarr_url";
pub const LEGACY_LIDARR_API_KEY: &str = "lidarr_api_key";
pub const LEGACY_LIDARR_ROOT_FOLDER_ID: &str = "lidarr_root_folder_id";
pub const LEGACY_LIDARR_ROOT_FOLDER_PATH: &str = "lidarr_root_folder_path";
pub const LEGACY_LIDARR_QUALITY_PROFILE_ID: &str = "lidarr_quality_profile_id";
pub const LEGACY_LIDARR_QUALITY_PROFILE_NAME: &str = "lidarr_quality_profile_name";

pub const LEGACY_LIDARR_KEYS: [&str; 6] = [
    LEGACY_LIDARR_URL,
    LEGACY_LIDARR_API_KEY,
    LEGACY_LIDARR_ROOT_FOLDER_ID,
    LEGACY_LIDARR_ROOT_FOLDER_PATH,
    LEGACY_LIDARR_QUALITY_PROFILE_ID,
    LEGACY_LIDARR_QUALITY_PROFILE_NAME,
];

/// Every fixed (non per-id) key the app reads or writes.
pub const STATIC_KEYS: [&str; 13] = [
    SERVERS,
    SELECTED_SERVER,
    LIDARR_INSTANCES,
    LIDARR_SELECTED,
    LEGACY_SERVER_URL,
    LEGACY_USERNAME,
    LEGACY_PASSWORD,
    LEGACY_LIDARR_URL,
    LEGACY_LIDARR_API_KEY,
    LEGACY_LIDARR_ROOT_FOLDER_ID,
    LEGACY_LIDARR_ROOT_FOLDER_PATH,
    LEGACY_LIDARR_QUALITY_PROFILE_ID,
    LEGACY_LIDARR_QUALITY_PROFILE_NAME,
];

/// Whether `key` belongs to the app (fixed or per-id key).
pub fn is_app_key(key: &str) -> bool {
    STATIC_KEYS.contains(&key)
        || key
            .strip_prefix(SERVER_PASSWORD_PREFIX)
            .is_some_and(|id| !id.is_empty())
        || key
            .strip_prefix(LIDARR_API_KEY_PREFIX)
            .is_some_and(|id| !id.is_empty())
}

/// `id` fields of a stored JSON list; malformed input yields none.
pub(crate) fn ids_in_list(raw: &str) -> Vec<String> {
    match serde_json::from_str::<serde_json::Value>(raw) {
        Ok(serde_json::Value::Array(items)) => items
            .iter()
            .filter_map(|v| v.get("id").and_then(|id| id.as_str()).map(String::from))
            .collect(),
        _ => Vec::new(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn app_keys() {
        assert!(is_app_key("navidrome_servers"));
        assert!(is_app_key("server_password_abc"));
        assert!(is_app_key("lidarr_api_key_abc"));
        assert!(is_app_key("lidarr_api_key"));
        assert!(!is_app_key("server_password_"));
        assert!(!is_app_key("something_else"));
    }
}
