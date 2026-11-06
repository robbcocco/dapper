use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, PartialEq, Eq, Hash, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Artist {
    pub id: String,
    pub name: String,
    pub cover_art_id: Option<String>,
    #[serde(default)]
    pub album_count: i64,
    pub music_brainz_id: Option<String>,
}
