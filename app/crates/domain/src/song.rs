use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, PartialEq, Eq, Hash, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Song {
    pub id: String,
    pub title: String,
    pub album_id: Option<String>,
    pub artist_id: Option<String>,
    pub album: Option<String>,
    pub artist: Option<String>,
    pub duration: Option<i64>,
    pub bit_rate: Option<i32>,
    pub content_type: Option<String>,
    pub suffix: Option<String>,
    pub size: Option<i64>,
    pub cover_art_id: Option<String>,
    pub track: Option<i32>,
    pub disc_number: Option<i32>,
    pub year: Option<i32>,
    pub genre: Option<String>,
    pub album_artist: Option<String>,
    pub user_rating: Option<i32>,
    /// ISO timestamp as sent by Subsonic.
    #[serde(default)]
    pub starred: Option<String>,
}
