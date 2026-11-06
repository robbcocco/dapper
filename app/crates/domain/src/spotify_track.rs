use std::fmt;

use serde::{Deserialize, Serialize};

/// One track lifted from an external playlist (Spotify, Tidal, …).
#[derive(Debug, Clone, PartialEq, Eq, Hash, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SpotifyTrack {
    pub title: String,
    pub artist: String,
    pub album: Option<String>,
    pub duration_ms: Option<i64>,
}

impl fmt::Display for SpotifyTrack {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{} — {}", self.artist, self.title)
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum PlaylistProvider {
    Spotify,
    Tidal,
}

#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SpotifyPlaylistData {
    pub name: String,
    pub tracks: Vec<SpotifyTrack>,
    /// Source returned only a partial track list (e.g. Spotify embed cap).
    pub truncated: bool,
    pub provider: PlaylistProvider,
}
