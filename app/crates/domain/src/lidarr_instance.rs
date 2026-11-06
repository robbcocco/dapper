use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, PartialEq, Eq, Hash, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct LidarrInstance {
    pub id: String,
    pub name: String,
    pub url: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub default_root_folder_id: Option<i64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub default_root_folder_path: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub default_quality_profile_id: Option<i64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub default_quality_profile_name: Option<String>,
}
