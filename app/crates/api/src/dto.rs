//! Subsonic JSON shapes and their mapping to domain models.

use dapper_domain::{Album, Artist, Playlist, Song};
use serde::{Deserialize, Deserializer};

/// Dart `(json[k] as num?)?.toInt()`: accepts ints and floats (truncated).
fn opt_i64<'de, D: Deserializer<'de>>(d: D) -> Result<Option<i64>, D::Error> {
    let n: Option<serde_json::Number> = Option::deserialize(d)?;
    Ok(n.and_then(|n| n.as_i64().or_else(|| n.as_f64().map(|f| f as i64))))
}

fn opt_i32<'de, D: Deserializer<'de>>(d: D) -> Result<Option<i32>, D::Error> {
    Ok(opt_i64(d)?.map(|n| n as i32))
}

/// Dart `(json[k] as num?)?.toInt() ?? 0`.
fn i64_or_zero<'de, D: Deserializer<'de>>(d: D) -> Result<i64, D::Error> {
    Ok(opt_i64(d)?.unwrap_or(0))
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct SongDto {
    id: String,
    title: String,
    album_id: Option<String>,
    artist_id: Option<String>,
    album: Option<String>,
    artist: Option<String>,
    #[serde(default, deserialize_with = "opt_i64")]
    duration: Option<i64>,
    #[serde(default, deserialize_with = "opt_i32")]
    bit_rate: Option<i32>,
    content_type: Option<String>,
    suffix: Option<String>,
    #[serde(default, deserialize_with = "opt_i64")]
    size: Option<i64>,
    #[serde(rename = "coverArt")]
    cover_art_id: Option<String>,
    #[serde(default, deserialize_with = "opt_i32")]
    track: Option<i32>,
    #[serde(default, deserialize_with = "opt_i32")]
    disc_number: Option<i32>,
    #[serde(default, deserialize_with = "opt_i32")]
    year: Option<i32>,
    genre: Option<String>,
    album_artist: Option<String>,
    #[serde(default, deserialize_with = "opt_i32")]
    user_rating: Option<i32>,
    starred: Option<String>,
}

impl SongDto {
    pub(crate) fn into_song(self, fallback_album_artist: Option<&str>) -> Song {
        Song {
            id: self.id,
            title: self.title,
            album_id: self.album_id,
            artist_id: self.artist_id,
            album: self.album,
            artist: self.artist,
            duration: self.duration,
            bit_rate: self.bit_rate,
            content_type: self.content_type,
            suffix: self.suffix,
            size: self.size,
            cover_art_id: self.cover_art_id,
            track: self.track,
            disc_number: self.disc_number,
            year: self.year,
            genre: self.genre,
            album_artist: self
                .album_artist
                .or_else(|| fallback_album_artist.map(str::to_string)),
            user_rating: self.user_rating,
            starred: self.starred,
        }
    }
}

impl From<SongDto> for Song {
    fn from(d: SongDto) -> Self {
        d.into_song(None)
    }
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct AlbumDto {
    id: String,
    name: String,
    artist_id: Option<String>,
    artist: Option<String>,
    #[serde(rename = "coverArt")]
    cover_art_id: Option<String>,
    #[serde(default, deserialize_with = "opt_i32")]
    year: Option<i32>,
    genre: Option<String>,
    #[serde(default, deserialize_with = "i64_or_zero")]
    song_count: i64,
    #[serde(default, deserialize_with = "i64_or_zero")]
    duration: i64,
    #[serde(default, rename = "song")]
    songs: Option<Vec<SongDto>>,
    #[serde(default, deserialize_with = "opt_i32")]
    user_rating: Option<i32>,
    starred: Option<String>,
    created: Option<String>,
}

impl From<AlbumDto> for Album {
    fn from(d: AlbumDto) -> Self {
        let songs = d
            .songs
            .unwrap_or_default()
            .into_iter()
            .map(|s| s.into_song(d.artist.as_deref()))
            .collect();
        Album {
            id: d.id,
            name: d.name,
            artist_id: d.artist_id,
            artist: d.artist,
            cover_art_id: d.cover_art_id,
            year: d.year,
            genre: d.genre,
            song_count: d.song_count,
            duration: d.duration,
            songs,
            user_rating: d.user_rating,
            starred: d.starred,
            created: d.created,
        }
    }
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct ArtistDto {
    id: String,
    name: String,
    #[serde(rename = "coverArt")]
    cover_art_id: Option<String>,
    #[serde(default, deserialize_with = "i64_or_zero")]
    album_count: i64,
    music_brainz_id: Option<String>,
}

impl From<ArtistDto> for Artist {
    fn from(d: ArtistDto) -> Self {
        Artist {
            id: d.id,
            name: d.name,
            cover_art_id: d.cover_art_id,
            album_count: d.album_count,
            music_brainz_id: d.music_brainz_id,
        }
    }
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct PlaylistDto {
    id: String,
    name: String,
    comment: Option<String>,
    #[serde(rename = "coverArt")]
    cover_art_id: Option<String>,
    #[serde(default, deserialize_with = "i64_or_zero")]
    song_count: i64,
    #[serde(default, deserialize_with = "i64_or_zero")]
    duration: i64,
    #[serde(default, rename = "entry")]
    songs: Option<Vec<SongDto>>,
}

impl From<PlaylistDto> for Playlist {
    fn from(d: PlaylistDto) -> Self {
        Playlist {
            id: d.id,
            name: d.name,
            comment: d.comment,
            cover_art_id: d.cover_art_id,
            song_count: d.song_count,
            duration: d.duration,
            songs: d
                .songs
                .unwrap_or_default()
                .into_iter()
                .map(Song::from)
                .collect(),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn album_maps_songs_with_fallback_album_artist() {
        let dto: AlbumDto = serde_json::from_value(json!({
            "id": "al1", "name": "A", "artist": "Band", "coverArt": "c1", "songCount": 2,
            "duration": 300.7, "created": "2024-01-01T00:00:00Z", "starred": "2024-02-02T00:00:00Z",
            "song": [
                {"id": "s1", "title": "One", "track": 1, "size": 1234},
                {"id": "s2", "title": "Two", "albumArtist": "Other", "userRating": 4, "starred": "x"}
            ]
        }))
        .unwrap();
        let album = Album::from(dto);
        assert_eq!(album.duration, 300);
        assert_eq!(album.cover_art_id.as_deref(), Some("c1"));
        assert_eq!(album.created.as_deref(), Some("2024-01-01T00:00:00Z"));
        assert_eq!(album.songs[0].album_artist.as_deref(), Some("Band"));
        assert_eq!(album.songs[0].size, Some(1234));
        assert_eq!(album.songs[1].album_artist.as_deref(), Some("Other"));
        assert_eq!(album.songs[1].user_rating, Some(4));
        assert_eq!(album.songs[1].starred.as_deref(), Some("x"));
    }

    #[test]
    fn defaults_and_nulls() {
        let p: PlaylistDto =
            serde_json::from_value(json!({"id": "p", "name": "P", "songCount": null})).unwrap();
        let p = Playlist::from(p);
        assert_eq!(p.song_count, 0);
        assert!(p.songs.is_empty());
        let a: ArtistDto =
            serde_json::from_value(json!({"id": "a", "name": "N", "albumCount": 3})).unwrap();
        assert_eq!(Artist::from(a).album_count, 3);
        assert!(serde_json::from_value::<SongDto>(json!({"id": "s"})).is_err());
    }
}
