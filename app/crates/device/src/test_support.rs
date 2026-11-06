//! Fakes shared by this crate's unit tests.

use std::collections::{HashMap, HashSet};

use async_trait::async_trait;
use dapper_domain::{Album, AppError, Artist, LibraryReader, Result, ScrobbleSink, Song};
use parking_lot::Mutex;

#[derive(Default)]
pub struct FakeReader {
    pub albums: Vec<Album>,
    pub album_songs: HashMap<String, Vec<Song>>,
    pub song_ids: HashSet<String>,
    pub artists: Vec<Artist>,
}

#[async_trait]
impl LibraryReader for FakeReader {
    async fn all_albums(&self) -> Result<Vec<Album>> {
        Ok(self.albums.clone())
    }
    async fn album_songs(&self, album_id: &str) -> Result<Vec<Song>> {
        self.album_songs.get(album_id).cloned().ok_or_else(|| AppError::Network(format!("no album {album_id}")))
    }
    async fn all_song_ids(&self) -> Result<HashSet<String>> {
        Ok(self.song_ids.clone())
    }
    async fn artists(&self) -> Result<Vec<Artist>> {
        Ok(self.artists.clone())
    }
}

#[derive(Default)]
pub struct FakeSink {
    pub fail_ids: HashSet<String>,
    pub calls: Mutex<Vec<(String, bool, Option<i64>)>>,
}

#[async_trait]
impl ScrobbleSink for FakeSink {
    async fn scrobble(&self, song_id: &str, submission: bool, time_ms: Option<i64>) -> Result<()> {
        self.calls.lock().push((song_id.to_owned(), submission, time_ms));
        if self.fail_ids.contains(song_id) { Err(AppError::Network("boom".into())) } else { Ok(()) }
    }
}

pub fn album(id: &str, artist: &str, name: &str) -> Album {
    Album { id: id.into(), name: name.into(), artist: Some(artist.into()), ..Default::default() }
}

pub fn song(id: &str, title: &str, artist: &str, album: &str) -> Song {
    Song { id: id.into(), title: title.into(), artist: Some(artist.into()), album: Some(album.into()), ..Default::default() }
}
