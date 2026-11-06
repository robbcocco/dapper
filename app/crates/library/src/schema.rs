use rusqlite::Connection;

/// Ordered migrations; index + 1 is the `user_version` a database reaches
/// after applying the entry.
const MIGRATIONS: &[&str] = &[r#"
CREATE TABLE artists(
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  sort_name TEXT NOT NULL,
  cover_art_id TEXT,
  album_count INTEGER NOT NULL DEFAULT 0,
  music_brainz_id TEXT,
  starred TEXT,
  user_rating INTEGER,
  pos INTEGER NOT NULL DEFAULT 0,
  gen INTEGER NOT NULL
);
CREATE INDEX artists_pos ON artists(pos, sort_name);

CREATE TABLE albums(
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  sort_name TEXT NOT NULL,
  artist_id TEXT,
  artist TEXT,
  sort_artist TEXT NOT NULL,
  cover_art_id TEXT,
  year INTEGER,
  genre TEXT,
  song_count INTEGER NOT NULL DEFAULT 0,
  duration INTEGER NOT NULL DEFAULT 0,
  created TEXT,
  starred TEXT,
  user_rating INTEGER,
  gen INTEGER NOT NULL
);
CREATE INDEX albums_sort_name ON albums(sort_name, sort_artist, id);
CREATE INDEX albums_sort_artist ON albums(sort_artist, year, sort_name, id);
CREATE INDEX albums_year ON albums(year, sort_artist, sort_name, id);
CREATE INDEX albums_created ON albums(created, id);
CREATE INDEX albums_artist_id ON albums(artist_id);
CREATE INDEX albums_genre ON albums(genre);

CREATE TABLE songs(
  id TEXT PRIMARY KEY,
  title TEXT NOT NULL,
  sort_title TEXT NOT NULL,
  album_id TEXT,
  artist_id TEXT,
  album TEXT,
  sort_album TEXT NOT NULL,
  artist TEXT,
  sort_artist TEXT NOT NULL,
  album_artist TEXT,
  track INTEGER,
  disc_number INTEGER,
  year INTEGER,
  genre TEXT,
  duration INTEGER,
  bit_rate INTEGER,
  content_type TEXT,
  suffix TEXT,
  size INTEGER,
  cover_art_id TEXT,
  user_rating INTEGER,
  starred TEXT,
  gen INTEGER NOT NULL
);
CREATE INDEX songs_album ON songs(album_id, disc_number, track);
CREATE INDEX songs_sort_title ON songs(sort_title, id);
CREATE INDEX songs_sort_artist ON songs(sort_artist, sort_album, disc_number, track, id);
CREATE INDEX songs_sort_album ON songs(sort_album, disc_number, track, id);
CREATE INDEX songs_year ON songs(year, sort_artist, sort_album, disc_number, track, id);
CREATE INDEX songs_duration ON songs(duration, id);
CREATE INDEX songs_genre ON songs(genre);
CREATE INDEX songs_starred ON songs(starred) WHERE starred IS NOT NULL;

CREATE TABLE genres(
  name TEXT PRIMARY KEY,
  song_count INTEGER NOT NULL,
  album_count INTEGER NOT NULL
);

CREATE TABLE playlists(
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  comment TEXT,
  cover_art_id TEXT,
  song_count INTEGER NOT NULL DEFAULT 0,
  duration INTEGER NOT NULL DEFAULT 0,
  pos INTEGER NOT NULL,
  -- 1 once the entries below mirror a getPlaylist response.
  songs_cached INTEGER NOT NULL DEFAULT 0
);

-- Songs are denormalised so a playlist stays viewable offline even when an
-- entry has been swept from (or never reached) the songs table.
CREATE TABLE playlist_songs(
  playlist_id TEXT NOT NULL,
  pos INTEGER NOT NULL,
  song_id TEXT NOT NULL,
  song TEXT NOT NULL,
  PRIMARY KEY(playlist_id, pos)
) WITHOUT ROWID;

CREATE TABLE sync_state(k TEXT PRIMARY KEY, v TEXT NOT NULL) WITHOUT ROWID;

CREATE VIRTUAL TABLE songs_fts USING fts5(
  title, artist, album, album_artist,
  content='songs', content_rowid='rowid',
  tokenize='unicode61 remove_diacritics 2', prefix='2 3'
);
CREATE VIRTUAL TABLE albums_fts USING fts5(
  name, artist,
  content='albums', content_rowid='rowid',
  tokenize='unicode61 remove_diacritics 2', prefix='2 3'
);
CREATE VIRTUAL TABLE artists_fts USING fts5(
  name,
  content='artists', content_rowid='rowid',
  tokenize='unicode61 remove_diacritics 2', prefix='2 3'
);

CREATE TRIGGER songs_fts_ai AFTER INSERT ON songs BEGIN
  INSERT INTO songs_fts(rowid, title, artist, album, album_artist)
  VALUES (new.rowid, new.title, new.artist, new.album, new.album_artist);
END;
CREATE TRIGGER songs_fts_ad AFTER DELETE ON songs BEGIN
  INSERT INTO songs_fts(songs_fts, rowid, title, artist, album, album_artist)
  VALUES ('delete', old.rowid, old.title, old.artist, old.album, old.album_artist);
END;
-- The WHEN guard keeps every-sync upserts (which rewrite gen) from churning
-- the index for rows whose text did not change.
CREATE TRIGGER songs_fts_au AFTER UPDATE ON songs
WHEN old.title IS NOT new.title OR old.artist IS NOT new.artist
  OR old.album IS NOT new.album OR old.album_artist IS NOT new.album_artist
BEGIN
  INSERT INTO songs_fts(songs_fts, rowid, title, artist, album, album_artist)
  VALUES ('delete', old.rowid, old.title, old.artist, old.album, old.album_artist);
  INSERT INTO songs_fts(rowid, title, artist, album, album_artist)
  VALUES (new.rowid, new.title, new.artist, new.album, new.album_artist);
END;

CREATE TRIGGER albums_fts_ai AFTER INSERT ON albums BEGIN
  INSERT INTO albums_fts(rowid, name, artist) VALUES (new.rowid, new.name, new.artist);
END;
CREATE TRIGGER albums_fts_ad AFTER DELETE ON albums BEGIN
  INSERT INTO albums_fts(albums_fts, rowid, name, artist)
  VALUES ('delete', old.rowid, old.name, old.artist);
END;
CREATE TRIGGER albums_fts_au AFTER UPDATE ON albums
WHEN old.name IS NOT new.name OR old.artist IS NOT new.artist
BEGIN
  INSERT INTO albums_fts(albums_fts, rowid, name, artist)
  VALUES ('delete', old.rowid, old.name, old.artist);
  INSERT INTO albums_fts(rowid, name, artist) VALUES (new.rowid, new.name, new.artist);
END;

CREATE TRIGGER artists_fts_ai AFTER INSERT ON artists BEGIN
  INSERT INTO artists_fts(rowid, name) VALUES (new.rowid, new.name);
END;
CREATE TRIGGER artists_fts_ad AFTER DELETE ON artists BEGIN
  INSERT INTO artists_fts(artists_fts, rowid, name) VALUES ('delete', old.rowid, old.name);
END;
CREATE TRIGGER artists_fts_au AFTER UPDATE ON artists
WHEN old.name IS NOT new.name
BEGIN
  INSERT INTO artists_fts(artists_fts, rowid, name) VALUES ('delete', old.rowid, old.name);
  INSERT INTO artists_fts(rowid, name) VALUES (new.rowid, new.name);
END;
"#];

pub(crate) fn migrate(conn: &mut Connection) -> rusqlite::Result<()> {
    let version: usize =
        conn.pragma_query_value(None, "user_version", |r| r.get::<_, i64>(0))? as usize;
    for (i, sql) in MIGRATIONS.iter().enumerate().skip(version) {
        let tx = conn.transaction()?;
        tx.execute_batch(sql)?;
        tx.pragma_update(None, "user_version", (i + 1) as i64)?;
        tx.commit()?;
    }
    Ok(())
}
