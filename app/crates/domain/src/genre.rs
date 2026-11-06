use serde::{Deserialize, Serialize};

/// One genre as returned by Subsonic's `getGenres`.
#[derive(Debug, Clone, PartialEq, Eq, Hash, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Genre {
    pub name: String,
    pub song_count: i64,
    pub album_count: i64,
}
