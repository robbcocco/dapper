use std::collections::HashSet;
use std::num::NonZeroUsize;
use std::path::Path;

use async_trait::async_trait;
use dapper_domain::{
    Album, AppError, Artist, Genre, Lyrics, LyricsLine, Playlist, Result, ScrobbleSink,
    SearchResults, Song,
};
use lru::LruCache;
use parking_lot::Mutex;
use serde::de::DeserializeOwned;
use serde_json::Value;
use tokio_util::sync::CancellationToken;
use url::Url;

use crate::dto::{AlbumDto, ArtistDto, PlaylistDto, SongDto};
use crate::subsonic_client::{Params, SubsonicClient, endpoints as ep, malformed};

// Cover-art URIs are requested on every grid rebuild. Subsonic tokens never
// expire server-side, so a cached URI stays valid for this client's lifetime.
const COVER_ART_URI_CACHE_CAP: usize = 1024;
// Session LRU for getAlbum: direct callers (play artist iterating albums)
// would otherwise refetch on every invocation.
const ALBUM_CACHE_CAP: usize = 50;

/// `getScanStatus` result.
#[derive(Debug, Clone, PartialEq, Eq, Default, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ScanStatus {
    pub scanning: bool,
    pub count: Option<i64>,
    pub folder_count: Option<i64>,
    /// ISO-8601 timestamp of the last completed scan, when the server reports it.
    pub last_scan: Option<String>,
}

/// Ids from `getStarred2`.
#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct StarredIds {
    pub song_ids: HashSet<String>,
    pub album_ids: HashSet<String>,
    pub artist_ids: HashSet<String>,
}

fn at<'a>(v: &'a Value, path: &[&str]) -> Option<&'a Value> {
    path.iter()
        .try_fold(v, |cur, k| cur.get(*k))
        .filter(|v| !v.is_null())
}

/// Decodes every object in the array at `v` (non-objects are skipped).
fn list<T: DeserializeOwned>(v: Option<&Value>) -> Result<Vec<T>> {
    let Some(Value::Array(items)) = v else {
        return Ok(Vec::new());
    };
    items
        .iter()
        .filter(|i| i.is_object())
        .map(|i| T::deserialize(i).map_err(|_| malformed()))
        .collect()
}

fn object<T: DeserializeOwned>(v: Option<&Value>, what: &str) -> Result<T> {
    match v {
        Some(o @ Value::Object(_)) => T::deserialize(o).map_err(|_| malformed()),
        _ => Err(AppError::Subsonic {
            message: what.into(),
            code: 0,
        }),
    }
}

fn ids(v: Option<&Value>) -> HashSet<String> {
    let Some(Value::Array(items)) = v else {
        return HashSet::new();
    };
    items
        .iter()
        .filter_map(|e| e.get("id").and_then(Value::as_str).map(str::to_string))
        .collect()
}

fn songs(v: Option<&Value>) -> Result<Vec<Song>> {
    Ok(list::<SongDto>(v)?.into_iter().map(Song::from).collect())
}

fn albums(v: Option<&Value>) -> Result<Vec<Album>> {
    Ok(list::<AlbumDto>(v)?.into_iter().map(Album::from).collect())
}

fn artists(v: Option<&Value>) -> Result<Vec<Artist>> {
    Ok(list::<ArtistDto>(v)?
        .into_iter()
        .map(Artist::from)
        .collect())
}

/// Typed Subsonic API returning domain models (the Dart `SubsonicApi` +
/// `LibraryRepositoryImpl` pair).
pub struct SubsonicApi {
    client: SubsonicClient,
    cover_art_uris: Mutex<LruCache<(String, i32), Url>>,
    albums: Mutex<LruCache<String, Album>>,
}

impl SubsonicApi {
    pub fn new(client: SubsonicClient) -> Self {
        Self {
            client,
            cover_art_uris: Mutex::new(LruCache::new(
                NonZeroUsize::new(COVER_ART_URI_CACHE_CAP).expect("non-zero"),
            )),
            albums: Mutex::new(LruCache::new(
                NonZeroUsize::new(ALBUM_CACHE_CAP).expect("non-zero"),
            )),
        }
    }

    pub fn client(&self) -> &SubsonicClient {
        &self.client
    }

    pub async fn ping(&self) -> Result<bool> {
        let r = self.client.get(ep::PING, &[]).await?;
        Ok(r.get("status").and_then(Value::as_str) == Some("ok"))
    }

    pub async fn get_artists(&self) -> Result<Vec<Artist>> {
        let r = self.client.get(ep::GET_ARTISTS, &[]).await?;
        let Some(Value::Array(indices)) = at(&r, &["artists", "index"]) else {
            return Ok(Vec::new());
        };
        let mut out = Vec::new();
        for index in indices.iter().filter(|i| i.is_object()) {
            out.extend(artists(index.get("artist"))?);
        }
        Ok(out)
    }

    pub async fn get_albums_by_artist(&self, artist_id: &str) -> Result<Vec<Album>> {
        let r = self
            .client
            .get(ep::GET_ARTIST, &[("id", artist_id.into())])
            .await?;
        albums(at(&r, &["artist", "album"]))
    }

    /// Album with its songs; served from a 50-entry session LRU when cached.
    pub async fn get_album(&self, album_id: &str) -> Result<Album> {
        if let Some(a) = self.albums.lock().get(album_id) {
            return Ok(a.clone());
        }
        self.refresh_album(album_id).await
    }

    /// Fetches the album from the server, bypassing (and then updating) the LRU.
    pub async fn refresh_album(&self, album_id: &str) -> Result<Album> {
        let r = self
            .client
            .get(ep::GET_ALBUM, &[("id", album_id.into())])
            .await?;
        let album = Album::from(object::<AlbumDto>(
            r.get("album"),
            "Unexpected album payload",
        )?);
        self.albums.lock().put(album_id.to_string(), album.clone());
        Ok(album)
    }

    /// Paged `getAlbumList2` (`type` e.g. `newest`, `alphabeticalByName`,
    /// `byGenre` — the latter requires `genre`).
    pub async fn get_album_list2(
        &self,
        list_type: &str,
        size: i64,
        offset: i64,
        genre: Option<&str>,
    ) -> Result<Vec<Album>> {
        let mut params: Params = vec![("type", list_type.into())];
        if let Some(g) = genre {
            params.push(("genre", g.into()));
        }
        params.push(("size", size.to_string()));
        params.push(("offset", offset.to_string()));
        let r = self.client.get(ep::GET_ALBUM_LIST2, &params).await?;
        albums(at(&r, &["albumList2", "album"]))
    }

    pub async fn get_recent_albums(&self, size: i64, offset: i64) -> Result<Vec<Album>> {
        self.get_album_list2("newest", size, offset, None).await
    }

    pub async fn get_all_albums(&self, size: i64, offset: i64) -> Result<Vec<Album>> {
        self.get_album_list2("alphabeticalByName", size, offset, None)
            .await
    }

    pub async fn get_albums_by_genre(
        &self,
        genre: &str,
        size: i64,
        offset: i64,
    ) -> Result<Vec<Album>> {
        self.get_album_list2("byGenre", size, offset, Some(genre))
            .await
    }

    pub async fn get_playlists(&self) -> Result<Vec<Playlist>> {
        let r = self.client.get(ep::GET_PLAYLISTS, &[]).await?;
        Ok(list::<PlaylistDto>(at(&r, &["playlists", "playlist"]))?
            .into_iter()
            .map(Playlist::from)
            .collect())
    }

    pub async fn get_playlist(&self, playlist_id: &str) -> Result<Playlist> {
        let r = self
            .client
            .get(ep::GET_PLAYLIST, &[("id", playlist_id.into())])
            .await?;
        Ok(object::<PlaylistDto>(r.get("playlist"), "Unexpected playlist payload")?.into())
    }

    pub async fn search_all(&self, query: &str) -> Result<SearchResults> {
        let params: Params = vec![
            ("query", query.into()),
            ("artistCount", "10".into()),
            ("albumCount", "10".into()),
            ("songCount", "30".into()),
        ];
        let r = self.client.get(ep::SEARCH3, &params).await?;
        Ok(SearchResults {
            artists: artists(at(&r, &["searchResult3", "artist"]))?,
            albums: albums(at(&r, &["searchResult3", "album"]))?,
            songs: songs(at(&r, &["searchResult3", "song"]))?,
        })
    }

    pub async fn search(&self, query: &str) -> Result<Vec<Song>> {
        let params: Params = vec![
            ("query", query.into()),
            ("artistCount", "0".into()),
            ("albumCount", "0".into()),
            ("songCount", "50".into()),
        ];
        let r = self.client.get(ep::SEARCH3, &params).await?;
        songs(at(&r, &["searchResult3", "song"]))
    }

    /// Paged song-only `search3`; an empty query pages the whole library.
    pub async fn search3_songs(&self, query: &str, count: i64, offset: i64) -> Result<Vec<Song>> {
        let params: Params = vec![
            ("query", query.into()),
            ("artistCount", "0".into()),
            ("albumCount", "0".into()),
            ("songCount", count.to_string()),
            ("songOffset", offset.to_string()),
        ];
        let r = self.client.get(ep::SEARCH3, &params).await?;
        songs(at(&r, &["searchResult3", "song"]))
    }

    pub async fn get_all_songs(&self, count: i64, offset: i64) -> Result<Vec<Song>> {
        self.search3_songs("", count, offset).await
    }

    pub async fn create_playlist(&self, name: &str, song_ids: &[String]) -> Result<Playlist> {
        let mut params: Params = vec![("name", name.into())];
        params.extend(song_ids.iter().map(|id| ("songId", id.clone())));
        let r = self.client.get(ep::CREATE_PLAYLIST, &params).await?;
        Ok(object::<PlaylistDto>(r.get("playlist"), "createPlaylist returned no playlist")?.into())
    }

    pub async fn update_playlist(
        &self,
        id: &str,
        name: Option<&str>,
        song_ids_to_add: &[String],
        song_indexes_to_remove: &[i64],
    ) -> Result<()> {
        let mut params: Params = vec![("playlistId", id.into())];
        if let Some(n) = name {
            params.push(("name", n.into()));
        }
        params.extend(song_ids_to_add.iter().map(|s| ("songIdToAdd", s.clone())));
        params.extend(
            song_indexes_to_remove
                .iter()
                .map(|i| ("songIndexToRemove", i.to_string())),
        );
        self.client
            .get(ep::UPDATE_PLAYLIST, &params)
            .await
            .map(drop)
    }

    pub async fn delete_playlist(&self, id: &str) -> Result<()> {
        self.client
            .get(ep::DELETE_PLAYLIST, &[("id", id.into())])
            .await
            .map(drop)
    }

    pub async fn get_genres(&self) -> Result<Vec<Genre>> {
        let r = self.client.get(ep::GET_GENRES, &[]).await?;
        let Some(Value::Array(items)) = at(&r, &["genres", "genre"]) else {
            return Ok(Vec::new());
        };
        Ok(items
            .iter()
            .filter(|g| g.is_object())
            .filter_map(|g| {
                // Subsonic uses `value`; some older forks send `name`.
                let name = at(g, &["value"]).or_else(|| at(g, &["name"]))?.as_str()?;
                if name.is_empty() {
                    return None;
                }
                Some(Genre {
                    name: name.into(),
                    song_count: g.get("songCount").and_then(Value::as_i64).unwrap_or(0),
                    album_count: g.get("albumCount").and_then(Value::as_i64).unwrap_or(0),
                })
            })
            .collect())
    }

    /// Lyrics for `song_id`, or `None` when the server has none. Handles the
    /// structured (OpenSubsonic, possibly synced) and legacy flat shapes.
    pub async fn get_lyrics(&self, song_id: &str) -> Result<Option<Lyrics>> {
        let r = self
            .client
            .get(ep::GET_LYRICS_BY_SONG_ID, &[("id", song_id.into())])
            .await?;
        Ok(parse_lyrics(&r))
    }

    /// Rating 1-5; 0 clears an existing rating.
    pub async fn set_rating(&self, id: &str, rating: i32) -> Result<()> {
        debug_assert!((0..=5).contains(&rating), "rating must be 0-5");
        self.client
            .get(
                ep::SET_RATING,
                &[("id", id.into()), ("rating", rating.to_string())],
            )
            .await
            .map(drop)
    }

    /// `submission=false` is the "now playing" ping; `time_ms` backdates an
    /// imported listen (ms since epoch).
    pub async fn scrobble(
        &self,
        song_id: &str,
        submission: bool,
        time_ms: Option<i64>,
    ) -> Result<()> {
        let mut params: Params = vec![
            ("id", song_id.into()),
            ("submission", submission.to_string()),
        ];
        if let Some(t) = time_ms {
            params.push(("time", t.to_string()));
        }
        self.client.get(ep::SCROBBLE, &params).await.map(drop)
    }

    pub async fn star(&self, id: &str) -> Result<()> {
        self.client
            .get(ep::STAR, &[("id", id.into())])
            .await
            .map(drop)
    }

    pub async fn unstar(&self, id: &str) -> Result<()> {
        self.client
            .get(ep::UNSTAR, &[("id", id.into())])
            .await
            .map(drop)
    }

    pub async fn get_starred2(&self) -> Result<StarredIds> {
        let r = self.client.get(ep::GET_STARRED2, &[]).await?;
        Ok(StarredIds {
            song_ids: ids(at(&r, &["starred2", "song"])),
            album_ids: ids(at(&r, &["starred2", "album"])),
            artist_ids: ids(at(&r, &["starred2", "artist"])),
        })
    }

    pub async fn get_starred_song_ids(&self) -> Result<HashSet<String>> {
        Ok(self.get_starred2().await?.song_ids)
    }

    pub async fn get_scan_status(&self) -> Result<ScanStatus> {
        let r = self.client.get(ep::GET_SCAN_STATUS, &[]).await?;
        let s = at(&r, &["scanStatus"]);
        let get = |k: &str| s.and_then(|s| s.get(k));
        Ok(ScanStatus {
            scanning: get("scanning").and_then(Value::as_bool).unwrap_or(false),
            count: get("count").and_then(Value::as_i64),
            folder_count: get("folderCount").and_then(Value::as_i64),
            last_scan: get("lastScan").and_then(Value::as_str).map(str::to_string),
        })
    }

    /// Memoised per `(id, size)` with LRU promote-on-read.
    pub fn cover_art_uri(&self, cover_art_id: &str, size: i32) -> Url {
        let key = (cover_art_id.to_string(), size);
        let mut cache = self.cover_art_uris.lock();
        if let Some(u) = cache.get(&key) {
            return u.clone();
        }
        let uri = self.client.build_uri(
            ep::GET_COVER_ART,
            &[("id", cover_art_id.into()), ("size", size.to_string())],
        );
        cache.put(key, uri.clone());
        uri
    }

    /// Playback URL; `format`/`maxBitRate` request server-side transcoding.
    pub fn stream_uri(
        &self,
        song_id: &str,
        format: Option<&str>,
        max_bit_rate: Option<i32>,
    ) -> Url {
        let mut params: Params = vec![("id", song_id.into())];
        if let Some(f) = format {
            params.push(("format", f.into()));
        }
        if let Some(b) = max_bit_rate.filter(|b| *b > 0) {
            params.push(("maxBitRate", b.to_string()));
        }
        self.client.build_uri(ep::STREAM, &params)
    }

    /// Transfer-engine URL: `/rest/download` (original file) when `format` is
    /// `None`, otherwise a transcoded `/rest/stream`.
    pub fn transfer_uri(
        &self,
        song_id: &str,
        format: Option<&str>,
        max_bit_rate: Option<i32>,
    ) -> Url {
        match format {
            None => self.download_uri(song_id),
            Some(_) => self.stream_uri(song_id, format, max_bit_rate),
        }
    }

    /// Original-file download URL for a song.
    pub fn download_uri(&self, id: &str) -> Url {
        self.client.build_uri(ep::DOWNLOAD, &[("id", id.into())])
    }

    /// Zip of originals for an album/artist/playlist id. Navidrome ignores
    /// transcoding options on this endpoint.
    pub fn zip_uri(&self, id: &str) -> Url {
        self.download_uri(id)
    }

    /// Streams `url` into `dest` over this client's connection pool.
    pub async fn download_to_file(
        &self,
        url: &str,
        dest: &Path,
        on_progress: impl FnMut(u64, Option<u64>),
        cancel: CancellationToken,
    ) -> Result<u64> {
        crate::download_to_file(self.client.http(), url, dest, on_progress, cancel).await
    }
}

#[async_trait]
impl ScrobbleSink for SubsonicApi {
    async fn scrobble(&self, song_id: &str, submission: bool, time_ms: Option<i64>) -> Result<()> {
        SubsonicApi::scrobble(self, song_id, submission, time_ms).await
    }
}

fn parse_lyrics(r: &Value) -> Option<Lyrics> {
    if let Some(Value::Array(structured)) = at(r, &["lyricsList", "structuredLyrics"])
        && let Some(first) = structured.first()
    {
        let synced = first.get("synced") == Some(&Value::Bool(true));
        let lines: Vec<LyricsLine> = first
            .get("line")
            .and_then(Value::as_array)
            .into_iter()
            .flatten()
            .filter_map(|raw| {
                let text = raw.get("value")?.as_str()?;
                let start = raw
                    .get("start")
                    .and_then(Value::as_i64)
                    .filter(|s| synced && *s >= 0);
                Some(LyricsLine {
                    text: text.into(),
                    start_ms: start,
                })
            })
            .collect();
        if lines.is_empty() {
            return None;
        }
        let lang = first
            .get("lang")
            .and_then(Value::as_str)
            .map(str::to_string);
        return Some(Lyrics {
            lines,
            synced,
            lang,
        });
    }
    let flat = at(r, &["lyrics", "value"])?.as_str()?;
    if flat.trim().is_empty() {
        return None;
    }
    let lines = flat
        .split('\n')
        .map(|l| LyricsLine {
            text: l.into(),
            start_ms: None,
        })
        .collect();
    Some(Lyrics {
        lines,
        synced: false,
        lang: None,
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn lyrics_structured_and_legacy() {
        let l = parse_lyrics(&json!({"lyricsList": {"structuredLyrics": [{
            "synced": true, "lang": "en",
            "line": [{"value": "a", "start": 10}, {"value": "b", "start": -1}, {"start": 5}, "x"]
        }]}}))
        .unwrap();
        assert!(l.synced);
        assert_eq!(l.lang.as_deref(), Some("en"));
        assert_eq!(
            l.lines,
            vec![
                LyricsLine {
                    text: "a".into(),
                    start_ms: Some(10)
                },
                LyricsLine {
                    text: "b".into(),
                    start_ms: None
                }
            ]
        );
        let unsynced = parse_lyrics(
            &json!({"lyricsList": {"structuredLyrics": [{"line": [{"value": "a", "start": 10}]}]}}),
        )
        .unwrap();
        assert_eq!(unsynced.lines[0].start_ms, None);
        let legacy = parse_lyrics(&json!({"lyrics": {"value": "x\ny"}})).unwrap();
        assert_eq!(legacy.lines.len(), 2);
        assert!(!legacy.synced);
        assert_eq!(parse_lyrics(&json!({"lyrics": {"value": "  "}})), None);
        assert_eq!(
            parse_lyrics(&json!({"lyricsList": {"structuredLyrics": [{"line": []}]}})),
            None
        );
    }
}
