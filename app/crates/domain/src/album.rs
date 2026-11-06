use serde::{Deserialize, Serialize};

use crate::Song;

#[derive(Debug, Clone, PartialEq, Eq, Hash, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Album {
    pub id: String,
    pub name: String,
    pub artist_id: Option<String>,
    pub artist: Option<String>,
    pub cover_art_id: Option<String>,
    pub year: Option<i32>,
    pub genre: Option<String>,
    #[serde(default)]
    pub song_count: i64,
    #[serde(default)]
    pub duration: i64,
    #[serde(default)]
    pub songs: Vec<Song>,
    pub user_rating: Option<i32>,
    /// ISO timestamp as sent by Subsonic.
    #[serde(default)]
    pub starred: Option<String>,
    #[serde(default)]
    pub created: Option<String>,
}
