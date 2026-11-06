//! The selected server's clients and library cache, swapped atomically when
//! the selection changes, plus the ports other services use to reach it.

use std::path::Path;
use std::sync::Arc;

use async_trait::async_trait;
use dapper_api::{NavidromeClient, PlaylistScraper, SubsonicApi, SubsonicClient};
use dapper_audio::StreamResolver;
use dapper_domain::{AppError, NavidromeServer, Result, ScrobbleSink, Song, SpotifyPlaylistData};
use dapper_import::{PlaylistSink, PlaylistSource, SongSearch};
use dapper_library::Library;
use dapper_store::ServerCredentials;
use parking_lot::RwLock;
use tauri::AppHandle;
use url::Url;

use crate::events;

pub struct Session {
    pub server: NavidromeServer,
    pub api: Arc<SubsonicApi>,
    pub navidrome: Arc<NavidromeClient>,
    pub library: Library,
}

impl Session {
    /// Blocking (opens and migrates `library/<serverId>.db`).
    pub fn open(support_dir: &Path, server: NavidromeServer, creds: &ServerCredentials) -> Result<Self> {
        let api = Arc::new(SubsonicApi::new(SubsonicClient::new(
            &creds.url,
            &creds.username,
            &creds.password,
        )?));
        let navidrome = Arc::new(NavidromeClient::new(&creds.url, &creds.username, &creds.password)?);
        let library = Library::open(&Library::db_path(support_dir, &server.id), server.id.clone(), api.clone())?;
        Ok(Self { server, api, navidrome, library })
    }
}

#[derive(Default)]
pub struct SessionSlot {
    current: RwLock<Option<Arc<Session>>>,
}

impl SessionSlot {
    pub fn get(&self) -> Option<Arc<Session>> {
        self.current.read().clone()
    }

    pub fn require(&self) -> Result<Arc<Session>> {
        self.get().ok_or_else(|| AppError::Other("No server selected".into()))
    }

    pub fn replace(&self, next: Option<Arc<Session>>) {
        *self.current.write() = next;
    }

    pub fn selected_id(&self) -> Option<String> {
        self.current.read().as_ref().map(|s| s.server.id.clone())
    }
}

/// Player / import ports backed by whichever server is selected at call time.
pub struct CurrentServer(pub Arc<SessionSlot>);

impl StreamResolver for CurrentServer {
    fn stream_url(&self, song: &Song, transcode: bool) -> Url {
        match self.0.get() {
            Some(s) if transcode => s.api.stream_uri(&song.id, Some("mp3"), Some(320)),
            Some(s) => s.api.stream_uri(&song.id, None, None),
            // Unfetchable on purpose: the loader reports it as a playback error.
            None => Url::parse("dapper:no-server").expect("static url"),
        }
    }
}

#[async_trait]
impl ScrobbleSink for CurrentServer {
    async fn scrobble(&self, song_id: &str, submission: bool, time_ms: Option<i64>) -> Result<()> {
        self.0.require()?.api.scrobble(song_id, submission, time_ms).await
    }
}

#[async_trait]
impl SongSearch for CurrentServer {
    fn is_available(&self) -> bool {
        self.0.get().is_some()
    }

    async fn search_songs(&self, query: &str, count: usize) -> Result<Vec<Song>> {
        let count = i64::try_from(count).unwrap_or(i64::MAX);
        self.0.require()?.api.search3_songs(query, count, 0).await
    }
}

pub struct Scrapers;

#[async_trait]
impl PlaylistSource for Scrapers {
    async fn fetch(&self, url: &str) -> Result<SpotifyPlaylistData> {
        let scraper = PlaylistScraper::detect(url).ok_or_else(|| {
            AppError::Other(
                "That link is not from a supported provider. Paste a Spotify or Tidal playlist URL.".into(),
            )
        })?;
        scraper.fetch_playlist(url).await
    }
}

/// Creates imported playlists through the library so the cache stays current.
pub struct LibraryPlaylistSink {
    pub slot: Arc<SessionSlot>,
    pub app: AppHandle,
}

#[async_trait]
impl PlaylistSink for LibraryPlaylistSink {
    async fn create_playlist(&self, name: &str, song_ids: &[String]) -> Result<()> {
        self.slot.require()?.library.create_playlist(name, song_ids).await?;
        events::library_changed(&self.app);
        Ok(())
    }
}
