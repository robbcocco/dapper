use serde::{Deserialize, Serialize};

use crate::Song;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum TransferStatus {
    #[default]
    Queued,
    InProgress,
    Completed,
    Failed,
    Cancelled,
}

#[derive(Debug, Clone, PartialEq, Eq, Hash, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct TransferTask {
    pub id: String,
    pub song: Song,
    pub device_path: String,
    #[serde(default)]
    pub status: TransferStatus,
    #[serde(default)]
    pub bytes_received: i64,
    #[serde(default)]
    pub total_bytes: i64,
    pub error_message: Option<String>,
    /// Shared by every task of one bulk-zip group.
    pub zip_group_id: Option<String>,
    /// Album/artist id for /rest/download; set only on the group's leader.
    pub zip_source_id: Option<String>,
}

impl TransferTask {
    pub fn new(id: impl Into<String>, song: Song, device_path: impl Into<String>) -> Self {
        Self { id: id.into(), song, device_path: device_path.into(), ..Default::default() }
    }

    pub fn progress(&self) -> f64 {
        if self.total_bytes > 0 {
            self.bytes_received as f64 / self.total_bytes as f64
        } else {
            0.0
        }
    }

    pub fn is_zip_member(&self) -> bool {
        self.zip_group_id.is_some()
    }

    pub fn is_zip_leader(&self) -> bool {
        self.zip_source_id.is_some()
    }
}
