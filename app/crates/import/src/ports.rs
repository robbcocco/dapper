//! Ports the import workflow needs; the app backs them with `dapper-api`.

use async_trait::async_trait;
use dapper_domain::{Result, Song, SpotifyPlaylistData};

#[async_trait]
pub trait SongSearch: Send + Sync {
    /// False when no library server is connected (Dart: repository is null).
    fn is_available(&self) -> bool {
        true
    }
    async fn search_songs(&self, query: &str, count: usize) -> Result<Vec<Song>>;
}

/// Fetches an external playlist (Spotify/Tidal scraper chosen by URL).
#[async_trait]
pub trait PlaylistSource: Send + Sync {
    async fn fetch(&self, url: &str) -> Result<SpotifyPlaylistData>;
}

#[async_trait]
pub trait PlaylistSink: Send + Sync {
    async fn create_playlist(&self, name: &str, song_ids: &[String]) -> Result<()>;
}
