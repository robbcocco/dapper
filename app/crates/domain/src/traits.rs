use std::collections::HashSet;

use async_trait::async_trait;

use crate::{Album, Artist, Result, Song};

#[async_trait]
pub trait LibraryReader: Send + Sync {
    async fn all_albums(&self) -> Result<Vec<Album>>;
    async fn album_songs(&self, album_id: &str) -> Result<Vec<Song>>;
    async fn all_song_ids(&self) -> Result<HashSet<String>>;
    async fn artists(&self) -> Result<Vec<Artist>>;
}

#[async_trait]
pub trait ScrobbleSink: Send + Sync {
    async fn scrobble(&self, song_id: &str, submission: bool, time_ms: Option<i64>) -> Result<()>;
}
