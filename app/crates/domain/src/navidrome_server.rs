use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, PartialEq, Eq, Hash, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct NavidromeServer {
    pub id: String,
    pub name: String,
    pub url: String,
    pub username: String,
}
