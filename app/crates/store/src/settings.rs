use std::path::Path;

use dapper_domain::{AppSettings, Result};

use crate::fsutil;

/// Missing or unreadable file → defaults (Dart `AppSettingsNotifier._load`).
pub fn load(path: &Path) -> AppSettings {
    let Ok(raw) = std::fs::read_to_string(path) else {
        return AppSettings::default();
    };
    match serde_json::from_str::<serde_json::Value>(&raw) {
        Ok(v @ serde_json::Value::Object(_)) => AppSettings::from_json(&v),
        _ => AppSettings::default(),
    }
}

pub fn save(path: &Path, s: &AppSettings) -> Result<()> {
    fsutil::write_atomic(path, s.to_json().to_string().as_bytes(), false)
}

/// `setTransferConcurrency`: the only user-settable value, clamped to 1..=4.
pub fn with_transfer_concurrency(mut s: AppSettings, value: i64) -> AppSettings {
    s.transfer_concurrency = value.clamp(1, 4);
    s
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn missing_or_malformed_is_default() {
        let tmp = tempfile::tempdir().unwrap();
        let p = tmp.path().join("settings.json");
        assert_eq!(load(&p), AppSettings::default());
        std::fs::write(&p, "{nope").unwrap();
        assert_eq!(load(&p), AppSettings::default());
        std::fs::write(&p, "[1]").unwrap();
        assert_eq!(load(&p), AppSettings::default());
    }

    #[test]
    fn round_trip_and_shape() {
        let tmp = tempfile::tempdir().unwrap();
        let p = tmp.path().join("settings.json");
        save(
            &p,
            &AppSettings {
                transfer_concurrency: 2,
            },
        )
        .unwrap();
        assert_eq!(
            std::fs::read_to_string(&p).unwrap(),
            r#"{"transferConcurrency":2}"#
        );
        assert_eq!(load(&p).transfer_concurrency, 2);
    }

    #[test]
    fn clamps() {
        let d = AppSettings::default();
        assert_eq!(with_transfer_concurrency(d, 0).transfer_concurrency, 1);
        assert_eq!(with_transfer_concurrency(d, 3).transfer_concurrency, 3);
        assert_eq!(with_transfer_concurrency(d, 9).transfer_concurrency, 4);
    }
}
