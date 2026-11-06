use std::collections::{HashMap, HashSet};
use std::path::Path;
use std::time::Duration;

use dapper_domain::{Album, AppError, Artist, Genre, Playlist, Result, SearchResults, Song};
use parking_lot::Mutex;
use rusqlite::{Connection, OptionalExtension, Row, Transaction, TransactionBehavior, params};

use crate::fts::match_expr;
use crate::schema::migrate;
use crate::types::{AlbumSort, LibraryStatus, SearchLimits, SongSort, SortDir};

const K_GEN: &str = "gen";
const K_COMPLETED_AT: &str = "completed_at";
const K_LAST_SCAN: &str = "last_scan";
const K_SCAN_COUNT: &str = "scan_count";

const ARTIST_COLS: &str = "id, name, cover_art_id, album_count, music_brainz_id";
const ALBUM_COLS: &str = "id, name, artist_id, artist, cover_art_id, year, genre, song_count, \
     duration, user_rating, starred, created";
const SONG_COLS: &str = "id, title, album_id, artist_id, album, artist, duration, bit_rate, \
     content_type, suffix, size, cover_art_id, track, disc_number, year, genre, album_artist, \
     user_rating, starred";

/// Blocking SQLite cache for one server. Every method is synchronous; async
/// callers wrap them in `spawn_blocking`. Reads and writes use separate WAL
/// connections so window queries never wait behind a sync transaction.
pub struct LibraryDb {
    writer: Mutex<Connection>,
    reader: Mutex<Connection>,
}

/// Values recorded when a full sync completes; compared against
/// `getScanStatus` to decide whether the next sync can be skipped.
#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct ScanMark {
    pub last_scan: Option<String>,
    pub count: i64,
}

fn storage(e: rusqlite::Error) -> AppError {
    AppError::Storage(e.to_string())
}

fn sort_key(s: Option<&str>) -> String {
    s.unwrap_or_default().trim().to_lowercase()
}

fn json_ids<'a>(ids: impl IntoIterator<Item = &'a String>) -> String {
    serde_json::to_string(&ids.into_iter().collect::<Vec<_>>()).expect("string list serialises")
}

fn artist_row(r: &Row) -> rusqlite::Result<Artist> {
    Ok(Artist {
        id: r.get(0)?,
        name: r.get(1)?,
        cover_art_id: r.get(2)?,
        album_count: r.get(3)?,
        music_brainz_id: r.get(4)?,
    })
}

fn album_row(r: &Row) -> rusqlite::Result<Album> {
    Ok(Album {
        id: r.get(0)?,
        name: r.get(1)?,
        artist_id: r.get(2)?,
        artist: r.get(3)?,
        cover_art_id: r.get(4)?,
        year: r.get(5)?,
        genre: r.get(6)?,
        song_count: r.get(7)?,
        duration: r.get(8)?,
        songs: Vec::new(),
        user_rating: r.get(9)?,
        starred: r.get(10)?,
        created: r.get(11)?,
    })
}

fn song_row(r: &Row) -> rusqlite::Result<Song> {
    Ok(Song {
        id: r.get(0)?,
        title: r.get(1)?,
        album_id: r.get(2)?,
        artist_id: r.get(3)?,
        album: r.get(4)?,
        artist: r.get(5)?,
        duration: r.get(6)?,
        bit_rate: r.get(7)?,
        content_type: r.get(8)?,
        suffix: r.get(9)?,
        size: r.get(10)?,
        cover_art_id: r.get(11)?,
        track: r.get(12)?,
        disc_number: r.get(13)?,
        year: r.get(14)?,
        genre: r.get(15)?,
        album_artist: r.get(16)?,
        user_rating: r.get(17)?,
        starred: r.get(18)?,
    })
}

fn collect<T>(
    c: &Connection,
    sql: &str,
    p: impl rusqlite::Params,
    f: fn(&Row) -> rusqlite::Result<T>,
) -> rusqlite::Result<Vec<T>> {
    c.prepare_cached(sql)?.query_map(p, f)?.collect()
}

fn state_get(c: &Connection, k: &str) -> rusqlite::Result<Option<String>> {
    c.query_row("SELECT v FROM sync_state WHERE k = ?1", [k], |r| r.get(0))
        .optional()
}

fn state_set(c: &Connection, k: &str, v: &str) -> rusqlite::Result<()> {
    c.execute(
        "INSERT INTO sync_state(k, v) VALUES (?1, ?2) ON CONFLICT(k) DO UPDATE SET v = excluded.v",
        [k, v],
    )?;
    Ok(())
}

fn current_generation(c: &Connection) -> rusqlite::Result<i64> {
    Ok(state_get(c, K_GEN)?
        .and_then(|v| v.parse().ok())
        .unwrap_or(0))
}

fn count(c: &Connection, table: &str) -> rusqlite::Result<i64> {
    c.query_row(&format!("SELECT COUNT(*) FROM {table}"), [], |r| r.get(0))
}

/// Upserts preserve the row's rowid, which is what the external-content FTS
/// tables key on.
fn upsert_songs_tx(tx: &Transaction, songs: &[Song], gen_: i64) -> rusqlite::Result<()> {
    let mut st = tx.prepare_cached(
        "INSERT INTO songs(id, title, sort_title, album_id, artist_id, album, sort_album, artist, \
           sort_artist, album_artist, track, disc_number, year, genre, duration, bit_rate, \
           content_type, suffix, size, cover_art_id, user_rating, starred, gen)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14, ?15, ?16, ?17, ?18, \
           ?19, ?20, ?21, ?22, ?23)
         ON CONFLICT(id) DO UPDATE SET title = excluded.title, sort_title = excluded.sort_title, \
           album_id = excluded.album_id, artist_id = excluded.artist_id, album = excluded.album, \
           sort_album = excluded.sort_album, artist = excluded.artist, \
           sort_artist = excluded.sort_artist, album_artist = excluded.album_artist, \
           track = excluded.track, disc_number = excluded.disc_number, year = excluded.year, \
           genre = excluded.genre, duration = excluded.duration, bit_rate = excluded.bit_rate, \
           content_type = excluded.content_type, suffix = excluded.suffix, size = excluded.size, \
           cover_art_id = excluded.cover_art_id, user_rating = excluded.user_rating, \
           starred = excluded.starred, gen = excluded.gen",
    )?;
    for s in songs {
        st.execute(params![
            s.id,
            s.title,
            sort_key(Some(&s.title)),
            s.album_id,
            s.artist_id,
            s.album,
            sort_key(s.album.as_deref()),
            s.artist,
            sort_key(s.artist.as_deref()),
            s.album_artist,
            s.track,
            s.disc_number,
            s.year,
            s.genre,
            s.duration,
            s.bit_rate,
            s.content_type,
            s.suffix,
            s.size,
            s.cover_art_id,
            s.user_rating,
            s.starred,
            gen_,
        ])?;
    }
    Ok(())
}

impl LibraryDb {
    /// Opens (creating if needed) the cache at `path` and applies migrations.
    pub fn open(path: &Path) -> Result<Self> {
        if let Some(dir) = path.parent() {
            std::fs::create_dir_all(dir)?;
        }
        let mut writer = Connection::open(path).map_err(storage)?;
        Self::configure(&writer).map_err(storage)?;
        writer
            .pragma_update(None, "journal_mode", "WAL")
            .map_err(storage)?;
        migrate(&mut writer).map_err(storage)?;
        let reader = Connection::open(path).map_err(storage)?;
        Self::configure(&reader).map_err(storage)?;
        reader
            .pragma_update(None, "query_only", true)
            .map_err(storage)?;
        Ok(Self {
            writer: Mutex::new(writer),
            reader: Mutex::new(reader),
        })
    }

    fn configure(c: &Connection) -> rusqlite::Result<()> {
        c.busy_timeout(Duration::from_secs(5))?;
        c.pragma_update(None, "synchronous", "NORMAL")?;
        c.set_prepared_statement_cache_capacity(64);
        Ok(())
    }

    fn read<T>(&self, f: impl FnOnce(&Connection) -> rusqlite::Result<T>) -> Result<T> {
        f(&self.reader.lock()).map_err(storage)
    }

    /// IMMEDIATE so the write lock is taken up front: a deferred transaction
    /// that reads first and then writes fails with SQLITE_BUSY_SNAPSHOT
    /// (bypassing the busy timeout) when another connection to the same file
    /// committed in between.
    fn write<T>(&self, f: impl FnOnce(&Transaction) -> rusqlite::Result<T>) -> Result<T> {
        self.write_checked(|_| Ok(true), f)
    }

    /// Like `write`, for a sync pass's generation-stamped writes: rejected
    /// with `Cancelled` once a newer pass has reserved a generation, so a
    /// superseded or abandoned pass can never stamp rows the newer pass's
    /// sweep would then delete.
    fn write_for_pass<T>(
        &self,
        gen_: i64,
        f: impl FnOnce(&Transaction) -> rusqlite::Result<T>,
    ) -> Result<T> {
        self.write_checked(|tx| Ok(current_generation(tx)? == gen_), f)
    }

    fn write_checked<T>(
        &self,
        valid: impl FnOnce(&Transaction) -> rusqlite::Result<bool>,
        f: impl FnOnce(&Transaction) -> rusqlite::Result<T>,
    ) -> Result<T> {
        let mut c = self.writer.lock();
        let tx = c
            .transaction_with_behavior(TransactionBehavior::Immediate)
            .map_err(storage)?;
        if !valid(&tx).map_err(storage)? {
            return Err(AppError::Cancelled);
        }
        let out = f(&tx).map_err(storage)?;
        tx.commit().map_err(storage)?;
        Ok(out)
    }

    // ── State ────────────────────────────────────────────────────────────────

    /// True once a full sync has completed; until then reads should go to the
    /// server.
    pub fn is_ready(&self) -> Result<bool> {
        self.read(|c| Ok(state_get(c, K_COMPLETED_AT)?.is_some()))
    }

    pub fn status(&self) -> Result<LibraryStatus> {
        self.read(|c| {
            let completed_at = state_get(c, K_COMPLETED_AT)?;
            Ok(LibraryStatus {
                ready: completed_at.is_some(),
                completed_at,
                last_scan: state_get(c, K_LAST_SCAN)?,
                artists: count(c, "artists")?,
                albums: count(c, "albums")?,
                songs: count(c, "songs")?,
                playlists: count(c, "playlists")?,
            })
        })
    }

    /// Scan mark of the last completed sync, if any.
    pub(crate) fn scan_mark(&self) -> Result<Option<ScanMark>> {
        self.read(|c| {
            if state_get(c, K_COMPLETED_AT)?.is_none() {
                return Ok(None);
            }
            Ok(Some(ScanMark {
                last_scan: state_get(c, K_LAST_SCAN)?,
                count: state_get(c, K_SCAN_COUNT)?
                    .and_then(|v| v.parse().ok())
                    .unwrap_or(-1),
            }))
        })
    }

    /// Reserves the generation number for a new sync pass. Persisted up front
    /// so an interrupted pass never reuses a generation already stamped on
    /// rows.
    pub(crate) fn begin_generation(&self) -> Result<i64> {
        self.write(|tx| {
            let next = current_generation(tx)? + 1;
            state_set(tx, K_GEN, &next.to_string())?;
            Ok(next)
        })
    }

    // ── Sync writes ──────────────────────────────────────────────────────────

    /// `first_pos` is the index of `artists[0]` in the server's listing order.
    pub(crate) fn upsert_artists(
        &self,
        artists: &[Artist],
        first_pos: i64,
        gen_: i64,
    ) -> Result<()> {
        self.write_for_pass(gen_, |tx| {
            let mut st = tx.prepare_cached(
                "INSERT INTO artists(id, name, sort_name, cover_art_id, album_count, \
                   music_brainz_id, pos, gen)
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)
                 ON CONFLICT(id) DO UPDATE SET name = excluded.name, \
                   sort_name = excluded.sort_name, cover_art_id = excluded.cover_art_id, \
                   album_count = excluded.album_count, music_brainz_id = excluded.music_brainz_id, \
                   pos = excluded.pos, gen = excluded.gen",
            )?;
            for (i, a) in artists.iter().enumerate() {
                st.execute(params![
                    a.id,
                    a.name,
                    sort_key(Some(&a.name)),
                    a.cover_art_id,
                    a.album_count,
                    a.music_brainz_id,
                    first_pos + i as i64,
                    gen_,
                ])?;
            }
            Ok(())
        })
    }

    pub(crate) fn upsert_albums(&self, albums: &[Album], gen_: i64) -> Result<()> {
        self.write_for_pass(gen_, |tx| {
            let mut st = tx.prepare_cached(
                "INSERT INTO albums(id, name, sort_name, artist_id, artist, sort_artist, \
                   cover_art_id, year, genre, song_count, duration, created, starred, \
                   user_rating, gen)
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14, ?15)
                 ON CONFLICT(id) DO UPDATE SET name = excluded.name, \
                   sort_name = excluded.sort_name, artist_id = excluded.artist_id, \
                   artist = excluded.artist, sort_artist = excluded.sort_artist, \
                   cover_art_id = excluded.cover_art_id, year = excluded.year, \
                   genre = excluded.genre, song_count = excluded.song_count, \
                   duration = excluded.duration, created = excluded.created, \
                   starred = excluded.starred, user_rating = excluded.user_rating, \
                   gen = excluded.gen",
            )?;
            for a in albums {
                st.execute(params![
                    a.id,
                    a.name,
                    sort_key(Some(&a.name)),
                    a.artist_id,
                    a.artist,
                    sort_key(a.artist.as_deref()),
                    a.cover_art_id,
                    a.year,
                    a.genre,
                    a.song_count,
                    a.duration,
                    a.created,
                    a.starred,
                    a.user_rating,
                    gen_,
                ])?;
            }
            Ok(())
        })
    }

    pub(crate) fn upsert_songs(&self, songs: &[Song], gen_: i64) -> Result<()> {
        self.write_for_pass(gen_, |tx| upsert_songs_tx(tx, songs, gen_))
    }

    /// Reconciles starred flags with the server's authoritative id sets.
    /// Rows that were already starred keep their original timestamp; newly
    /// starred rows get `now`.
    pub(crate) fn apply_starred(
        &self,
        songs: &HashSet<String>,
        albums: &HashSet<String>,
        artists: &HashSet<String>,
        now: &str,
    ) -> Result<()> {
        self.write(|tx| {
            for (table, ids) in [("songs", songs), ("albums", albums), ("artists", artists)] {
                let ids = json_ids(ids);
                tx.execute(
                    &format!(
                        "UPDATE {table} SET starred = NULL WHERE starred IS NOT NULL \
                         AND id NOT IN (SELECT value FROM json_each(?1))"
                    ),
                    [&ids],
                )?;
                tx.execute(
                    &format!(
                        "UPDATE {table} SET starred = ?2 WHERE starred IS NULL \
                         AND id IN (SELECT value FROM json_each(?1))"
                    ),
                    [&ids, now],
                )?;
            }
            Ok(())
        })
    }

    pub(crate) fn replace_genres(&self, genres: &[Genre]) -> Result<()> {
        self.write(|tx| {
            tx.execute("DELETE FROM genres", [])?;
            let mut st = tx.prepare_cached(
                "INSERT INTO genres(name, song_count, album_count) VALUES (?1, ?2, ?3)
                 ON CONFLICT(name) DO UPDATE SET song_count = excluded.song_count, \
                   album_count = excluded.album_count",
            )?;
            for g in genres {
                st.execute(params![g.name, g.song_count, g.album_count])?;
            }
            Ok(())
        })
    }

    /// Replaces playlist metadata with a `getPlaylists` listing, keeping its
    /// order. Cached entries survive unless the playlist disappeared or its
    /// metadata changed (the next `playlist()` call refetches them).
    pub fn replace_playlists(&self, playlists: &[Playlist]) -> Result<()> {
        self.write(|tx| {
            let ids = json_ids(playlists.iter().map(|p| &p.id));
            tx.execute(
                "DELETE FROM playlist_songs WHERE playlist_id NOT IN (SELECT value FROM json_each(?1))",
                [&ids],
            )?;
            tx.execute("DELETE FROM playlists WHERE id NOT IN (SELECT value FROM json_each(?1))", [&ids])?;
            let mut st = tx.prepare_cached(
                "INSERT INTO playlists(id, name, comment, cover_art_id, song_count, duration, pos)
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)
                 ON CONFLICT(id) DO UPDATE SET name = excluded.name, comment = excluded.comment, \
                   cover_art_id = excluded.cover_art_id, song_count = excluded.song_count, \
                   duration = excluded.duration, pos = excluded.pos, \
                   songs_cached = songs_cached AND song_count = excluded.song_count \
                     AND duration = excluded.duration",
            )?;
            for (i, p) in playlists.iter().enumerate() {
                st.execute(params![
                    p.id,
                    p.name,
                    p.comment,
                    p.cover_art_id,
                    p.song_count,
                    p.duration,
                    i as i64
                ])?;
            }
            Ok(())
        })
    }

    /// Stores one playlist with its entries, as returned by `getPlaylist` or
    /// `createPlaylist`. New playlists are appended after existing ones.
    pub fn store_playlist(&self, p: &Playlist) -> Result<()> {
        self.write(|tx| {
            tx.execute(
                "INSERT INTO playlists(id, name, comment, cover_art_id, song_count, duration, pos, \
                   songs_cached)
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6, \
                   (SELECT COALESCE(MAX(pos) + 1, 0) FROM playlists), 1)
                 ON CONFLICT(id) DO UPDATE SET name = excluded.name, comment = excluded.comment, \
                   cover_art_id = excluded.cover_art_id, song_count = excluded.song_count, \
                   duration = excluded.duration, songs_cached = 1",
                params![p.id, p.name, p.comment, p.cover_art_id, p.song_count, p.duration],
            )?;
            tx.execute("DELETE FROM playlist_songs WHERE playlist_id = ?1", [&p.id])?;
            let mut st = tx.prepare_cached(
                "INSERT INTO playlist_songs(playlist_id, pos, song_id, song) VALUES (?1, ?2, ?3, ?4)",
            )?;
            for (i, s) in p.songs.iter().enumerate() {
                let json = serde_json::to_string(s).expect("Song serialises");
                st.execute(params![p.id, i as i64, s.id, json])?;
            }
            Ok(())
        })
    }

    pub fn remove_playlist(&self, id: &str) -> Result<()> {
        self.write(|tx| {
            tx.execute("DELETE FROM playlist_songs WHERE playlist_id = ?1", [id])?;
            tx.execute("DELETE FROM playlists WHERE id = ?1", [id])?;
            Ok(())
        })
    }

    /// Deletes every row a sync pass did not touch and records the scan mark.
    /// Returns removed (artists, albums, songs).
    pub(crate) fn finish_sync(
        &self,
        gen_: i64,
        mark: &ScanMark,
        completed_at: &str,
    ) -> Result<(i64, i64, i64)> {
        self.write_for_pass(gen_, |tx| {
            let mut removed = [0i64; 3];
            for (i, table) in ["artists", "albums", "songs"].into_iter().enumerate() {
                removed[i] =
                    tx.execute(&format!("DELETE FROM {table} WHERE gen < ?1"), [gen_])? as i64;
            }
            match &mark.last_scan {
                Some(v) => state_set(tx, K_LAST_SCAN, v)?,
                None => {
                    tx.execute("DELETE FROM sync_state WHERE k = ?1", [K_LAST_SCAN])?;
                }
            }
            state_set(tx, K_SCAN_COUNT, &mark.count.to_string())?;
            state_set(tx, K_COMPLETED_AT, completed_at)?;
            Ok((removed[0], removed[1], removed[2]))
        })
    }

    // ── Write-through (call after the server accepted the change) ───────────

    /// Sets or clears (`None`) the starred timestamp on whichever of song,
    /// album or artist carries `id`.
    pub fn set_starred(&self, id: &str, starred: Option<&str>) -> Result<()> {
        self.write(|tx| {
            for table in ["songs", "albums", "artists"] {
                tx.execute(
                    &format!("UPDATE {table} SET starred = ?2 WHERE id = ?1"),
                    params![id, starred],
                )?;
            }
            Ok(())
        })
    }

    /// Rating 0 clears it, matching Subsonic `setRating`.
    pub fn set_rating(&self, id: &str, rating: i32) -> Result<()> {
        let value = (rating > 0).then_some(rating);
        self.write(|tx| {
            for table in ["songs", "albums", "artists"] {
                tx.execute(
                    &format!("UPDATE {table} SET user_rating = ?2 WHERE id = ?1"),
                    params![id, value],
                )?;
            }
            Ok(())
        })
    }

    // ── Reads ────────────────────────────────────────────────────────────────

    /// Artists in the server's `getArtists` order.
    pub fn artists(&self) -> Result<Vec<Artist>> {
        self.read(|c| {
            collect(
                c,
                &format!("SELECT {ARTIST_COLS} FROM artists ORDER BY pos, sort_name"),
                [],
                artist_row,
            )
        })
    }

    pub fn artist(&self, id: &str) -> Result<Option<Artist>> {
        self.read(|c| {
            c.query_row(
                &format!("SELECT {ARTIST_COLS} FROM artists WHERE id = ?1"),
                [id],
                artist_row,
            )
            .optional()
        })
    }

    /// Albums whose album artist is `artist_id`, oldest first (Navidrome's
    /// `getArtist` order).
    pub fn albums_by_artist(&self, artist_id: &str) -> Result<Vec<Album>> {
        self.read(|c| {
            collect(
                c,
                &format!(
                    "SELECT {ALBUM_COLS} FROM albums WHERE artist_id = ?1 ORDER BY year, sort_name, id"
                ),
                [artist_id],
                album_row,
            )
        })
    }

    pub fn recent_albums(&self, limit: i64) -> Result<Vec<Album>> {
        self.albums_window(0, limit, AlbumSort::Recent, SortDir::Desc)
    }

    pub fn albums_window(
        &self,
        offset: i64,
        limit: i64,
        sort: AlbumSort,
        dir: SortDir,
    ) -> Result<Vec<Album>> {
        self.read(|c| {
            collect(
                c,
                &format!(
                    "SELECT {ALBUM_COLS} FROM albums ORDER BY {} LIMIT ?1 OFFSET ?2",
                    sort.order_by(dir)
                ),
                [limit, offset],
                album_row,
            )
        })
    }

    pub fn albums_count(&self) -> Result<i64> {
        self.read(|c| count(c, "albums"))
    }

    pub fn all_albums(&self) -> Result<Vec<Album>> {
        self.albums_window(0, -1, AlbumSort::Name, SortDir::Asc)
    }

    /// The album with its songs in disc/track order, or `None` when uncached.
    /// Songs without an album artist inherit the album's artist, as the
    /// server-backed mapping does.
    pub fn album(&self, id: &str) -> Result<Option<Album>> {
        self.read(|c| {
            let Some(mut album) = c
                .query_row(
                    &format!("SELECT {ALBUM_COLS} FROM albums WHERE id = ?1"),
                    [id],
                    album_row,
                )
                .optional()?
            else {
                return Ok(None);
            };
            album.songs = album_songs(c, id)?;
            for s in &mut album.songs {
                if s.album_artist.is_none() {
                    s.album_artist.clone_from(&album.artist);
                }
            }
            Ok(Some(album))
        })
    }

    pub fn album_songs(&self, album_id: &str) -> Result<Vec<Song>> {
        self.read(|c| album_songs(c, album_id))
    }

    pub fn songs_window(
        &self,
        offset: i64,
        limit: i64,
        sort: SongSort,
        dir: SortDir,
    ) -> Result<Vec<Song>> {
        self.read(|c| {
            collect(
                c,
                &format!(
                    "SELECT {SONG_COLS} FROM songs ORDER BY {} LIMIT ?1 OFFSET ?2",
                    sort.order_by(dir)
                ),
                [limit, offset],
                song_row,
            )
        })
    }

    pub fn songs_count(&self) -> Result<i64> {
        self.read(|c| count(c, "songs"))
    }

    /// Song ids of a window in the given order, for range selection across
    /// rows the UI has not materialised.
    pub fn song_ids(
        &self,
        offset: i64,
        limit: i64,
        sort: SongSort,
        dir: SortDir,
    ) -> Result<Vec<String>> {
        self.read(|c| {
            c.prepare_cached(&format!(
                "SELECT id FROM songs ORDER BY {} LIMIT ?1 OFFSET ?2",
                sort.order_by(dir)
            ))?
            .query_map([limit, offset], |r| r.get(0))?
            .collect()
        })
    }

    pub fn all_song_ids(&self) -> Result<HashSet<String>> {
        self.read(|c| {
            c.prepare_cached("SELECT id FROM songs")?
                .query_map([], |r| r.get(0))?
                .collect()
        })
    }

    pub fn song(&self, id: &str) -> Result<Option<Song>> {
        self.read(|c| {
            c.query_row(
                &format!("SELECT {SONG_COLS} FROM songs WHERE id = ?1"),
                [id],
                song_row,
            )
            .optional()
        })
    }

    /// Genres, heaviest-used first.
    pub fn genres(&self) -> Result<Vec<Genre>> {
        self.read(|c| {
            collect(
                c,
                "SELECT name, song_count, album_count FROM genres ORDER BY song_count DESC, name",
                [],
                |r| {
                    Ok(Genre {
                        name: r.get(0)?,
                        song_count: r.get(1)?,
                        album_count: r.get(2)?,
                    })
                },
            )
        })
    }

    /// Albums tagged with `genre` either on the album or on any of its songs
    /// (albums only carry their first genre).
    pub fn albums_by_genre(&self, genre: &str) -> Result<Vec<Album>> {
        self.read(|c| {
            collect(
                c,
                &format!(
                    "SELECT {ALBUM_COLS} FROM albums WHERE genre = ?1 \
                     OR id IN (SELECT album_id FROM songs WHERE genre = ?1) \
                     ORDER BY sort_name, sort_artist, id"
                ),
                [genre],
                album_row,
            )
        })
    }

    /// Prefix full-text search over artists, albums and songs, best match
    /// first. Diacritics and case are ignored.
    pub fn search(&self, query: &str, limits: SearchLimits) -> Result<SearchResults> {
        let Some(expr) = match_expr(query) else {
            return Ok(SearchResults::default());
        };
        self.read(|c| {
            let sql = |table: &str, cols: &str| {
                format!(
                    "SELECT {cols} FROM {table} JOIN (SELECT rowid AS fts_rowid, rank AS fts_rank \
                       FROM {table}_fts WHERE {table}_fts MATCH ?1 ORDER BY rank LIMIT ?2) \
                     ON {table}.rowid = fts_rowid ORDER BY fts_rank"
                )
            };
            Ok(SearchResults {
                artists: collect(
                    c,
                    &sql("artists", ARTIST_COLS),
                    params![expr, limits.artists],
                    artist_row,
                )?,
                albums: collect(
                    c,
                    &sql("albums", ALBUM_COLS),
                    params![expr, limits.albums],
                    album_row,
                )?,
                songs: collect(
                    c,
                    &sql("songs", SONG_COLS),
                    params![expr, limits.songs],
                    song_row,
                )?,
            })
        })
    }

    pub fn starred_song_ids(&self) -> Result<HashSet<String>> {
        self.read(|c| {
            c.prepare_cached("SELECT id FROM songs WHERE starred IS NOT NULL")?
                .query_map([], |r| r.get(0))?
                .collect()
        })
    }

    /// Cached user ratings for whichever of `ids` are rated songs, albums or
    /// artists.
    pub fn ratings(&self, ids: &[String]) -> Result<HashMap<String, i32>> {
        let ids = json_ids(ids);
        self.read(|c| {
            c.prepare_cached(
                "SELECT id, user_rating FROM songs WHERE user_rating IS NOT NULL \
                   AND id IN (SELECT value FROM json_each(?1))
                 UNION ALL SELECT id, user_rating FROM albums WHERE user_rating IS NOT NULL \
                   AND id IN (SELECT value FROM json_each(?1))
                 UNION ALL SELECT id, user_rating FROM artists WHERE user_rating IS NOT NULL \
                   AND id IN (SELECT value FROM json_each(?1))",
            )?
            .query_map([&ids], |r| Ok((r.get(0)?, r.get(1)?)))?
            .collect()
        })
    }

    /// Playlist metadata (without entries) in server order.
    pub fn playlists(&self) -> Result<Vec<Playlist>> {
        self.read(|c| {
            collect(
                c,
                "SELECT id, name, comment, cover_art_id, song_count, duration FROM playlists ORDER BY pos",
                [],
                playlist_row,
            )
        })
    }

    /// A playlist with its cached entries, or `None` when its entries were
    /// never fetched (or went stale after a metadata change).
    pub fn playlist(&self, id: &str) -> Result<Option<Playlist>> {
        self.read(|c| {
            let Some(mut p) = c
                .query_row(
                    "SELECT id, name, comment, cover_art_id, song_count, duration FROM playlists \
                     WHERE id = ?1 AND songs_cached",
                    [id],
                    playlist_row,
                )
                .optional()?
            else {
                return Ok(None);
            };
            let jsons: Vec<String> = c
                .prepare_cached(
                    "SELECT song FROM playlist_songs WHERE playlist_id = ?1 ORDER BY pos",
                )?
                .query_map([id], |r| r.get(0))?
                .collect::<rusqlite::Result<_>>()?;
            p.songs = jsons
                .iter()
                .map(|j| serde_json::from_str(j))
                .collect::<serde_json::Result<_>>()
                .map_err(|e| rusqlite::Error::ToSqlConversionFailure(Box::new(e)))?;
            Ok(Some(p))
        })
    }
}

fn playlist_row(r: &Row) -> rusqlite::Result<Playlist> {
    Ok(Playlist {
        id: r.get(0)?,
        name: r.get(1)?,
        comment: r.get(2)?,
        cover_art_id: r.get(3)?,
        song_count: r.get(4)?,
        duration: r.get(5)?,
        songs: Vec::new(),
    })
}

fn album_songs(c: &Connection, album_id: &str) -> rusqlite::Result<Vec<Song>> {
    collect(
        c,
        &format!(
            "SELECT {SONG_COLS} FROM songs WHERE album_id = ?1 \
             ORDER BY disc_number, track, sort_title, id"
        ),
        [album_id],
        song_row,
    )
}
