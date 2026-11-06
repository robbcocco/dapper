use serde::{Deserialize, Serialize};

use crate::to_string_as_fixed;

#[derive(Debug, Clone, PartialEq, Eq, Hash, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ConnectedDevice {
    pub path: String,
    pub label: String,
    pub total_bytes: i64,
    pub available_bytes: i64,
}

impl ConnectedDevice {
    pub fn used_fraction(&self) -> f64 {
        if self.total_bytes > 0 {
            (self.total_bytes - self.available_bytes) as f64 / self.total_bytes as f64
        } else {
            0.0
        }
    }

    pub fn available_formatted(&self) -> String {
        format_bytes(self.available_bytes)
    }

    pub fn total_formatted(&self) -> String {
        format_bytes(self.total_bytes)
    }
}

fn format_bytes(bytes: i64) -> String {
    let b = bytes as f64;
    if b >= 1e9 {
        format!("{} GB", to_string_as_fixed(b / 1e9, 1))
    } else if b >= 1e6 {
        format!("{} MB", to_string_as_fixed(b / 1e6, 0))
    } else {
        format!("{} KB", to_string_as_fixed(b / 1e3, 0))
    }
}

/// Outcome of a safe-unmount request; `error` carries the platform message.
#[derive(Debug, Clone, PartialEq, Eq, Hash, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct EjectResult {
    pub success: bool,
    pub error: Option<String>,
}

impl EjectResult {
    pub fn ok() -> Self {
        Self { success: true, error: None }
    }

    pub fn failed(error: impl Into<String>) -> Self {
        Self { success: false, error: Some(error.into()) }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn formats_and_fraction() {
        let d = ConnectedDevice {
            path: "/V".into(),
            label: "V".into(),
            total_bytes: 64_000_000_000,
            available_bytes: 16_000_000_000,
        };
        assert_eq!(d.used_fraction(), 0.75);
        assert_eq!(d.total_formatted(), "64.0 GB");
        assert_eq!(format_bytes(2_500_000), "3 MB");
        assert_eq!(format_bytes(999), "1 KB");
    }
}
