use std::collections::{HashMap, HashSet};
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, LazyLock, Weak};

use async_trait::async_trait;
use dapper_api::SubsonicApi;
use dapper_domain::{
    Album, AppError, Artist, Genre, LibraryReader, Playlist, Result, SearchResults, Song,
};

use crate::db::LibraryDb;
use crate::types::{AlbumSort, LibraryStatus, Page, SearchLimits, SongSort, SortDir};

/// Page size for server listings (Navidrome's `getAlbumList2`/`search3` cap).
pub(crate) const SERVER_PAGE: i64 = 500;

type SyncLock = Arc<tokio::sync::Mutex<()>>;

/// One sync lock per database file for the whole process, so a second
/// `Library` opened on the same cache (e.g. on server re-select) waits for an
/// in-flight pass instead of interleaving with it.
static SYNC_LOCKS: LazyLock<parking_lot::Mutex<HashMap<PathBuf, Weak<tokio::sync::Mutex<()>>>>> =
    LazyLock::new(Default::default);

fn sync_lock_for(path: &Path) -> SyncLock {
    let key = std::fs::canonicalize(path).unwrap_or_else(|_| path.to_path_buf());
    let mut locks = SYNC_LOCKS.lock();
    locks.retain(|_, l| l.strong_count() > 0);
    if let Some(lock) = locks.get(&key).and_then(Weak::upgrade) {
        return lock;
    }
    let lock = SyncLock::default();
    locks.insert(key, Arc::downgrade(&lock));
    lock
}

/// Library of one server: reads come from the local cache once a full sync
/// has completed and from the server before that; edits go to the server
/// first and are then written through to the cache. Cheap to clone.
#[derive(Clone)]
pub struct Library {
    pub(crate) inner: Arc<Inner>,
}

pub(crate) struct Inner {
    pub(crate) server_id: String,
    pub(crate) db: Arc<LibraryDb>,
    pub(crate) api: Arc<SubsonicApi>,
    pub(crate) ready: AtomicBool,
    pub(crate) sync_lock: SyncLock,
}

impl Library {
    /// `<support_dir>/library/<server_id>.db`.
    pub fn db_path(support_dir: &Path, server_id: &str) -> PathBuf {
        support_dir.join("library").join(format!("{server_id}.db"))
    }

    /// Opens the cache at `db_path`. Blocking (SQLite open + migrations).
    pub fn open(
        db_path: &Path,
        server_id: impl Into<String>,
        api: Arc<SubsonicApi>,
    ) -> Result<Self> {
        let db = LibraryDb::open(db_path)?;
        let ready = db.is_ready()?;
        Ok(Self {
            inner: Arc::new(Inner {
                server_id: server_id.into(),
                db: Arc::new(db),
                api,
                ready: AtomicBool::new(ready),
                sync_lock: sync_lock_for(db_path),
            }),
        })
    }

    pub fn server_id(&self) -> &str {
        &self.inner.server_id
    }

    pub fn api(&self) -> &Arc<SubsonicApi> {
        &self.inner.api
    }

    /// The blocking cache, for callers that batch several reads in one
    /// `spawn_blocking`.
    pub fn db(&self) -> &Arc<LibraryDb> {
        &self.inner.db
    }

    /// True once a full sync has completed and reads are served from cache.
    pub fn is_ready(&self) -> bool {
        self.inner.ready.load(Ordering::Acquire)
    }

    pub(crate) async fn blocking<T: Send + 'static>(
        &self,
        f: impl FnOnce(&LibraryDb) -> Result<T> + Send + 'static,
    ) -> Result<T> {
        let db = self.inner.db.clone();
        tokio::task::spawn_blocking(move || f(&db))
            .await
            .map_err(|e| AppError::Other(format!("library task failed: {e}")))?
    }

    pub async fn status(&self) -> Result<LibraryStatus> {
        self.blocking(LibraryDb::status).await
    }

    // ── Reads ────────────────────────────────────────────────────────────────

    pub async fn artists(&self) -> Result<Vec<Artist>> {
        if self.is_ready() {
            return self.blocking(LibraryDb::artists).await;
        }
        self.inner.api.get_artists().await
    }

    pub async fn artist_albums(&self, artist_id: &str) -> Result<Vec<Album>> {
        if self.is_ready() {
            let id = artist_id.to_string();
            return self.blocking(move |db| db.albums_by_artist(&id)).await;
        }
        self.inner.api.get_albums_by_artist(artist_id).await
    }

    /// Album with songs. Albums added since the last sync are fetched from
    /// the server.
    pub async fn album(&self, id: &str) -> Result<Album> {
        if self.is_ready() {
            let key = id.to_string();
            if let Some(a) = self.blocking(move |db| db.album(&key)).await? {
                return Ok(a);
            }
        }
        self.inner.api.get_album(id).await
    }

    pub async fn recent_albums(&self, limit: i64) -> Result<Vec<Album>> {
        if self.is_ready() {
            return self.blocking(move |db| db.recent_albums(limit)).await;
        }
        self.inner.api.get_recent_albums(limit, 0).await
    }

    pub async fn albums_page(
        &self,
        offset: i64,
        limit: i64,
        sort: AlbumSort,
        dir: SortDir,
    ) -> Result<Page<Album>> {
        if self.is_ready() {
            return self
                .blocking(move |db| {
                    Ok(Page {
                        items: db.albums_window(offset, limit, sort, dir)?,
                        total: Some(db.albums_count()?),
                    })
                })
                .await;
        }
        let items = self
            .inner
            .api
            .get_album_list2(sort.list_type(), limit, offset, None)
            .await?;
        Ok(Page { items, total: None })
    }

    /// Before the first sync the server's `search3` order applies regardless
    /// of `sort`.
    pub async fn songs_page(
        &self,
        offset: i64,
        limit: i64,
        sort: SongSort,
        dir: SortDir,
    ) -> Result<Page<Song>> {
        if self.is_ready() {
            return self
                .blocking(move |db| {
                    Ok(Page {
                        items: db.songs_window(offset, limit, sort, dir)?,
                        total: Some(db.songs_count()?),
                    })
                })
                .await;
        }
        let items = self.inner.api.search3_songs("", limit, offset).await?;
        Ok(Page { items, total: None })
    }

    pub async fn song_ids(
        &self,
        offset: i64,
        limit: i64,
        sort: SongSort,
        dir: SortDir,
    ) -> Result<Vec<String>> {
        if self.is_ready() {
            return self
                .blocking(move |db| db.song_ids(offset, limit, sort, dir))
                .await;
        }
        let songs = self.inner.api.search3_songs("", limit, offset).await?;
        Ok(songs.into_iter().map(|s| s.id).collect())
    }

    /// Genres, heaviest-used first.
    pub async fn genres(&self) -> Result<Vec<Genre>> {
        if self.is_ready() {
            return self.blocking(LibraryDb::genres).await;
        }
        let mut genres = self.inner.api.get_genres().await?;
        genres.sort_by_key(|g| std::cmp::Reverse(g.song_count));
        Ok(genres)
    }

    pub async fn albums_by_genre(&self, genre: &str) -> Result<Vec<Album>> {
        if self.is_ready() {
            let g = genre.to_string();
            return self.blocking(move |db| db.albums_by_genre(&g)).await;
        }
        self.inner
            .api
            .get_albums_by_genre(genre, SERVER_PAGE, 0)
            .await
    }

    /// Before the first sync this is the server's `search3` with its fixed
    /// 10/10/30 caps.
    pub async fn search(&self, query: &str, limits: SearchLimits) -> Result<SearchResults> {
        let query = query.trim();
        if query.is_empty() {
            return Ok(SearchResults::default());
        }
        if self.is_ready() {
            let q = query.to_string();
            return self.blocking(move |db| db.search(&q, limits)).await;
        }
        self.inner.api.search_all(query).await
    }

    pub async fn starred_song_ids(&self) -> Result<HashSet<String>> {
        if self.is_ready() {
            return self.blocking(LibraryDb::starred_song_ids).await;
        }
        self.inner.api.get_starred_song_ids().await
    }

    /// Cached ratings for `ids` (songs, albums or artists). Empty before the
    /// first sync; listings fetched from the server carry `userRating`.
    pub async fn ratings(&self, ids: Vec<String>) -> Result<HashMap<String, i32>> {
        self.blocking(move |db| db.ratings(&ids)).await
    }

    pub async fn playlists(&self) -> Result<Vec<Playlist>> {
        if self.is_ready() {
            return self.blocking(LibraryDb::playlists).await;
        }
        self.refresh_playlists().await
    }

    /// Server first so edits from other clients show; the cached copy is
    /// served when the server is unreachable.
    pub async fn playlist(&self, id: &str) -> Result<Playlist> {
        match self.inner.api.get_playlist(id).await {
            Ok(p) => {
                let stored = p.clone();
                self.blocking(move |db| db.store_playlist(&stored)).await?;
                Ok(p)
            }
            Err(e @ AppError::Network(_)) => {
                let key = id.to_string();
                self.blocking(move |db| db.playlist(&key)).await?.ok_or(e)
            }
            Err(e) => Err(e),
        }
    }

    async fn refresh_playlists(&self) -> Result<Vec<Playlist>> {
        let list = self.inner.api.get_playlists().await?;
        let stored = list.clone();
        self.blocking(move |db| db.replace_playlists(&stored))
            .await?;
        Ok(list)
    }

    // ── Writes: server first, then cache ────────────────────────────────────

    pub async fn star(&self, id: &str) -> Result<()> {
        self.inner.api.star(id).await?;
        let (id, now) = (id.to_string(), crate::now_iso());
        self.blocking(move |db| db.set_starred(&id, Some(&now)))
            .await
    }

    pub async fn unstar(&self, id: &str) -> Result<()> {
        self.inner.api.unstar(id).await?;
        let id = id.to_string();
        self.blocking(move |db| db.set_starred(&id, None)).await
    }

    /// Rating 1-5 for a song, album or artist; 0 clears it.
    pub async fn set_rating(&self, id: &str, rating: i32) -> Result<()> {
        self.inner.api.set_rating(id, rating).await?;
        let id = id.to_string();
        self.blocking(move |db| db.set_rating(&id, rating)).await
    }

    pub async fn create_playlist(&self, name: &str, song_ids: &[String]) -> Result<Playlist> {
        let created = self.inner.api.create_playlist(name, song_ids).await?;
        self.refresh_playlists().await?;
        let stored = created.clone();
        self.blocking(move |db| db.store_playlist(&stored)).await?;
        Ok(created)
    }

    pub async fn rename_playlist(&self, id: &str, name: &str) -> Result<Playlist> {
        self.inner
            .api
            .update_playlist(id, Some(name), &[], &[])
            .await?;
        self.refresh_playlist(id).await
    }

    pub async fn add_to_playlist(&self, id: &str, song_ids: &[String]) -> Result<Playlist> {
        self.inner
            .api
            .update_playlist(id, None, song_ids, &[])
            .await?;
        self.refresh_playlist(id).await
    }

    /// Removes the entries at `indexes` (positions in the playlist as last
    /// fetched).
    pub async fn remove_from_playlist(&self, id: &str, indexes: &[i64]) -> Result<Playlist> {
        self.inner
            .api
            .update_playlist(id, None, &[], indexes)
            .await?;
        self.refresh_playlist(id).await
    }

    pub async fn delete_playlist(&self, id: &str) -> Result<()> {
        self.inner.api.delete_playlist(id).await?;
        let id = id.to_string();
        self.blocking(move |db| db.remove_playlist(&id)).await
    }

    /// Re-reads the listing (order, counts) and the edited playlist's entries.
    async fn refresh_playlist(&self, id: &str) -> Result<Playlist> {
        let (list, playlist) = tokio::try_join!(
            self.inner.api.get_playlists(),
            self.inner.api.get_playlist(id)
        )?;
        let stored = playlist.clone();
        self.blocking(move |db| {
            db.replace_playlists(&list)?;
            db.store_playlist(&stored)
        })
        .await?;
        Ok(playlist)
    }
}

#[async_trait]
impl LibraryReader for Library {
    async fn all_albums(&self) -> Result<Vec<Album>> {
        if self.is_ready() {
            return self.blocking(LibraryDb::all_albums).await;
        }
        let mut all = Vec::new();
        loop {
            let page = self
                .inner
                .api
                .get_all_albums(SERVER_PAGE, all.len() as i64)
                .await?;
            let short = (page.len() as i64) < SERVER_PAGE;
            all.extend(page);
            if short {
                return Ok(all);
            }
        }
    }

    async fn album_songs(&self, album_id: &str) -> Result<Vec<Song>> {
        Ok(self.album(album_id).await?.songs)
    }

    async fn all_song_ids(&self) -> Result<HashSet<String>> {
        if self.is_ready() {
            return self.blocking(LibraryDb::all_song_ids).await;
        }
        let mut ids = HashSet::new();
        let mut offset = 0;
        loop {
            let page = self
                .inner
                .api
                .search3_songs("", SERVER_PAGE, offset)
                .await?;
            offset += page.len() as i64;
            let short = (page.len() as i64) < SERVER_PAGE;
            ids.extend(page.into_iter().map(|s| s.id));
            if short {
                return Ok(ids);
            }
        }
    }

    async fn artists(&self) -> Result<Vec<Artist>> {
        Library::artists(self).await
    }
}
