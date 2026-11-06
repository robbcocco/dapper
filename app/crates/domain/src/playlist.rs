use serde::{Deserialize, Serialize};

use crate::Song;

#[derive(Debug, Clone, PartialEq, Eq, Hash, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Playlist {
    pub id: String,
    pub name: String,
    pub comment: Option<String>,
    pub cover_art_id: Option<String>,
    #[serde(default)]
    pub song_count: i64,
    #[serde(default)]
    pub duration: i64,
    #[serde(default)]
    pub songs: Vec<Song>,
}
