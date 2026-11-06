use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct AppSettings {
    pub transfer_concurrency: i64,
}

impl Default for AppSettings {
    fn default() -> Self {
        Self { transfer_concurrency: 4 }
    }
}

impl AppSettings {
    /// Dart `fromJson`: missing or non-int `transferConcurrency` → 4.
    pub fn from_json(j: &serde_json::Value) -> Self {
        Self {
            transfer_concurrency: j.get("transferConcurrency").and_then(|v| v.as_i64()).unwrap_or(4),
        }
    }

    pub fn to_json(&self) -> serde_json::Value {
        serde_json::json!({ "transferConcurrency": self.transfer_concurrency })
    }
}
