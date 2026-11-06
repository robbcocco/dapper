use std::sync::atomic::Ordering;

use dapper_domain::{AppError, Result};
use tracing::{debug, info};

use crate::db::{LibraryDb, ScanMark};
use crate::library::{Library, SERVER_PAGE};
use crate::types::{SyncPhase, SyncProgress, SyncReport};

impl Library {
    /// Brings the cache up to date with the server.
    ///
    /// When `getScanStatus` reports the same `lastScan`/`count` as the last
    /// completed sync (and `force` is false), only starred flags and
    /// playlists — which change without a scan — are refreshed. Otherwise
    /// every artist, album page and song page is upserted under a new
    /// generation, one transaction per page, and rows the pass did not touch
    /// are swept at the end. An interrupted pass leaves the previous data in
    /// place.
    ///
    /// Passes over the same database file run one after another, across all
    /// `Library` instances in the process. To abort a pass, drop its future
    /// (or abort its task): every page write is checked against the latest
    /// reserved generation, so a write still in flight from an abandoned pass
    /// is rejected once a newer pass has started, and can never be swept by
    /// it.
    pub async fn sync(
        &self,
        force: bool,
        mut progress: impl FnMut(SyncProgress) + Send,
    ) -> Result<SyncReport> {
        let _guard = self.inner.sync_lock.lock().await;
        let api = &self.inner.api;
        let mut emit = |phase, done, total| progress(SyncProgress { phase, done, total });

        emit(SyncPhase::ScanStatus, 0, None);
        let status = api.get_scan_status().await?;
        let mark = ScanMark {
            last_scan: status.last_scan.clone(),
            count: status.count.unwrap_or(-1),
        };
        let comparable = mark.last_scan.is_some() || status.count.is_some();
        let previous = self.blocking(LibraryDb::scan_mark).await?;
        if !force && comparable && previous.as_ref() == Some(&mark) {
            debug!(server = %self.inner.server_id, "library unchanged since last sync");
            // Another instance on this file may have completed the sync.
            self.inner.ready.store(true, Ordering::Release);
            self.sync_starred(&mut emit).await?;
            self.sync_playlists(&mut emit).await?;
            emit(SyncPhase::Done, 0, None);
            let s = self.status().await?;
            return Ok(SyncReport {
                skipped: true,
                artists: s.artists,
                albums: s.albums,
                songs: s.songs,
                removed_artists: 0,
                removed_albums: 0,
                removed_songs: 0,
            });
        }

        let generation = self.blocking(LibraryDb::begin_generation).await?;

        emit(SyncPhase::Artists, 0, None);
        let artists = api.get_artists().await?;
        let artist_count = artists.len() as i64;
        self.blocking(move |db| db.upsert_artists(&artists, 0, generation))
            .await?;
        emit(SyncPhase::Artists, artist_count, Some(artist_count));

        emit(SyncPhase::Albums, 0, None);
        let mut album_count = 0;
        loop {
            let page = api
                .get_album_list2("alphabeticalByName", SERVER_PAGE, album_count, None)
                .await?;
            let n = page.len() as i64;
            if n > 0 {
                self.blocking(move |db| db.upsert_albums(&page, generation))
                    .await?;
            }
            album_count += n;
            emit(SyncPhase::Albums, album_count, None);
            if n < SERVER_PAGE {
                break;
            }
        }

        emit(SyncPhase::Songs, 0, status.count);
        let mut song_count = 0;
        loop {
            let page = api.search3_songs("", SERVER_PAGE, song_count).await?;
            let n = page.len() as i64;
            if n > 0 {
                self.blocking(move |db| db.upsert_songs(&page, generation))
                    .await?;
            }
            song_count += n;
            emit(SyncPhase::Songs, song_count, status.count);
            if n < SERVER_PAGE {
                break;
            }
        }
        // Sweeping after an empty listing of a non-empty library would wipe
        // the cache (servers that reject an empty search3 query answer with
        // no songs rather than an error).
        if song_count == 0 && status.count.is_some_and(|c| c > 0) {
            return Err(AppError::Other(
                "Server listed no songs although its scan status reports some".into(),
            ));
        }

        self.sync_starred(&mut emit).await?;

        emit(SyncPhase::Genres, 0, None);
        let genres = api.get_genres().await?;
        let genre_count = genres.len() as i64;
        self.blocking(move |db| db.replace_genres(&genres)).await?;
        emit(SyncPhase::Genres, genre_count, Some(genre_count));

        self.sync_playlists(&mut emit).await?;

        emit(SyncPhase::Sweep, 0, None);
        let completed_at = crate::now_iso();
        let (removed_artists, removed_albums, removed_songs) = self
            .blocking(move |db| db.finish_sync(generation, &mark, &completed_at))
            .await?;
        self.inner.ready.store(true, Ordering::Release);
        emit(SyncPhase::Done, song_count, status.count);

        info!(
            server = %self.inner.server_id,
            artists = artist_count,
            albums = album_count,
            songs = song_count,
            removed_artists,
            removed_albums,
            removed_songs,
            "library sync complete"
        );
        Ok(SyncReport {
            skipped: false,
            artists: artist_count,
            albums: album_count,
            songs: song_count,
            removed_artists,
            removed_albums,
            removed_songs,
        })
    }

    async fn sync_starred(&self, emit: &mut impl FnMut(SyncPhase, i64, Option<i64>)) -> Result<()> {
        emit(SyncPhase::Starred, 0, None);
        let starred = self.inner.api.get_starred2().await?;
        let n =
            (starred.song_ids.len() + starred.album_ids.len() + starred.artist_ids.len()) as i64;
        let now = crate::now_iso();
        self.blocking(move |db| {
            db.apply_starred(
                &starred.song_ids,
                &starred.album_ids,
                &starred.artist_ids,
                &now,
            )
        })
        .await?;
        emit(SyncPhase::Starred, n, Some(n));
        Ok(())
    }

    async fn sync_playlists(
        &self,
        emit: &mut impl FnMut(SyncPhase, i64, Option<i64>),
    ) -> Result<()> {
        emit(SyncPhase::Playlists, 0, None);
        let playlists = self.inner.api.get_playlists().await?;
        let n = playlists.len() as i64;
        self.blocking(move |db| db.replace_playlists(&playlists))
            .await?;
        emit(SyncPhase::Playlists, n, Some(n));
        Ok(())
    }
}
