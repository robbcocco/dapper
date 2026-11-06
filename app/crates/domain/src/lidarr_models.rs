use std::collections::HashSet;
use std::fmt;

use serde::{Deserialize, Serialize};
use serde_json::{Map, Value};

use crate::{AppError, Result, to_string_as_fixed};

type JsonObject = Map<String, Value>;

fn int(j: &Value, k: &str) -> Option<i64> {
    j.get(k).and_then(Value::as_i64)
}

fn string(j: &Value, k: &str) -> Option<String> {
    j.get(k).and_then(Value::as_str).map(str::to_string)
}

fn boolean(j: &Value, k: &str) -> Option<bool> {
    j.get(k).and_then(Value::as_bool)
}

/// First image of `cover_type`, preferring `remoteUrl` over `url`.
fn image_url(j: &Value, cover_type: &str) -> Option<String> {
    j.get("images")?.as_array()?.iter().find_map(|img| {
        if img.get("coverType").and_then(Value::as_str) != Some(cover_type) {
            return None;
        }
        string(img, "remoteUrl").or_else(|| string(img, "url"))
    })
}

fn release_year(release_date: Option<&str>) -> Option<i32> {
    let d = release_date.filter(|d| !d.is_empty())?;
    d.split('-').next()?.parse().ok()
}

/// Dart `Object.toString()` for JSON scalars.
fn dart_to_string(v: &Value) -> String {
    match v {
        Value::String(s) => s.clone(),
        Value::Null => "null".into(),
        other => other.to_string(),
    }
}

fn required<T>(v: Option<T>, what: &str) -> Result<T> {
    v.ok_or_else(|| AppError::Other(format!("Lidarr JSON missing '{what}'")))
}

#[derive(Debug, Clone, PartialEq, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct LidarrArtist {
    /// 0 means a lookup result not yet added.
    pub id: i64,
    /// MusicBrainz artist ID (`foreignArtistId`).
    pub mbid: String,
    pub name: String,
    pub monitored: bool,
    pub status: Option<String>,
    pub root_folder_path: Option<String>,
    pub poster_url: Option<String>,
    pub overview: Option<String>,
    pub album_count: i64,
    pub track_file_count: i64,
    pub total_track_count: i64,
    pub quality_profile_id: i64,
    pub tag_ids: Vec<i64>,
    pub genres: Vec<String>,
}

impl LidarrArtist {
    pub fn is_in_lidarr(&self) -> bool {
        self.id > 0
    }

    /// Tracked but no track files downloaded.
    pub fn is_missing(&self) -> bool {
        self.is_in_lidarr() && self.total_track_count > 0 && self.track_file_count == 0
    }

    pub fn percent_of_tracks(&self) -> f64 {
        if self.total_track_count > 0 {
            self.track_file_count as f64 / self.total_track_count as f64 * 100.0
        } else {
            0.0
        }
    }

    pub fn from_json(j: &Value) -> Self {
        let stats = j.get("statistics");
        let stat = |k: &str| stats.and_then(|s| int(s, k)).unwrap_or(0);
        let list = |k: &str| j.get(k).and_then(Value::as_array).cloned().unwrap_or_default();
        Self {
            id: int(j, "id").unwrap_or(0),
            mbid: string(j, "foreignArtistId").unwrap_or_default(),
            name: string(j, "artistName").unwrap_or_default(),
            monitored: boolean(j, "monitored").unwrap_or(false),
            status: string(j, "status"),
            root_folder_path: string(j, "rootFolderPath"),
            poster_url: image_url(j, "poster"),
            overview: string(j, "overview"),
            quality_profile_id: int(j, "qualityProfileId").unwrap_or(0),
            tag_ids: list("tags").iter().filter_map(Value::as_i64).collect(),
            genres: list("genres").iter().filter_map(|g| g.as_str().map(str::to_string)).collect(),
            album_count: stat("albumCount"),
            track_file_count: stat("trackFileCount"),
            total_track_count: stat("totalTrackCount"),
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum LidarrAlbumType {
    Album,
    Ep,
    Single,
    Other,
}

impl LidarrAlbumType {
    pub fn from_str_opt(s: Option<&str>) -> Self {
        match s.map(str::to_lowercase).as_deref() {
            Some("album") => Self::Album,
            Some("ep") => Self::Ep,
            Some("single") => Self::Single,
            _ => Self::Other,
        }
    }

    pub fn label(self) -> &'static str {
        match self {
            Self::Album => "Albums",
            Self::Ep => "EPs",
            Self::Single => "Singles",
            Self::Other => "Other",
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct LidarrAlbum {
    pub id: i64,
    pub title: String,
    pub monitored: bool,
    /// At least one track file has been imported.
    pub has_file: bool,
    pub album_type: LidarrAlbumType,
    pub release_date: Option<String>,
    pub cover_url: Option<String>,
}

impl LidarrAlbum {
    pub fn year(&self) -> Option<i32> {
        release_year(self.release_date.as_deref())
    }

    pub fn from_json(j: &Value) -> Self {
        let track_file_count = j.get("statistics").and_then(|s| int(s, "trackFileCount")).unwrap_or(0);
        Self {
            id: int(j, "id").unwrap_or(0),
            title: string(j, "title").unwrap_or_default(),
            monitored: boolean(j, "monitored").unwrap_or(false),
            has_file: track_file_count > 0,
            album_type: LidarrAlbumType::from_str_opt(j.get("albumType").and_then(Value::as_str)),
            release_date: string(j, "releaseDate"),
            cover_url: image_url(j, "cover"),
        }
    }
}

/// One `GET /api/v1/album/lookup` result; `raw` is POSTed back to add it.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct LidarrAlbumLookup {
    /// 0 means lookup-only, not yet added.
    pub lidarr_album_id: i64,
    pub foreign_album_id: String,
    pub title: String,
    pub artist_name: String,
    pub artist_mbid: String,
    pub release_date: Option<String>,
    pub cover_url: Option<String>,
    pub album_type: Option<LidarrAlbumType>,
    pub raw: JsonObject,
}

impl LidarrAlbumLookup {
    pub fn is_in_lidarr(&self) -> bool {
        self.lidarr_album_id > 0
    }

    pub fn year(&self) -> Option<i32> {
        release_year(self.release_date.as_deref())
    }

    pub fn from_json(j: &Value) -> Self {
        let artist = j.get("artist");
        Self {
            lidarr_album_id: int(j, "id").unwrap_or(0),
            foreign_album_id: string(j, "foreignAlbumId").unwrap_or_default(),
            title: string(j, "title").unwrap_or_default(),
            artist_name: artist.and_then(|a| string(a, "artistName")).unwrap_or_default(),
            artist_mbid: artist.and_then(|a| string(a, "foreignArtistId")).unwrap_or_default(),
            release_date: string(j, "releaseDate"),
            cover_url: image_url(j, "cover"),
            album_type: Some(LidarrAlbumType::from_str_opt(j.get("albumType").and_then(Value::as_str))),
            raw: j.as_object().cloned().unwrap_or_default(),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct LidarrRelease {
    pub guid: String,
    pub title: String,
    pub indexer: String,
    pub size: i64,
    /// `torrent` | `usenet`
    pub protocol: String,
    pub quality: String,
    pub age_in_days: i64,
    pub rejected: bool,
    pub rejections: Vec<String>,
    pub seeders: Option<i64>,
    pub leechers: Option<i64>,
    /// Original JSON, sent back verbatim to POST /api/v1/release.
    pub raw: JsonObject,
}

impl LidarrRelease {
    pub fn formatted_size(&self) -> String {
        let size = self.size;
        let s = size as f64;
        if size <= 0 {
            "—".into()
        } else if size < 1024 * 1024 {
            format!("{} KB", to_string_as_fixed(s / 1024.0, 0))
        } else if size < 1024 * 1024 * 1024 {
            format!("{} MB", to_string_as_fixed(s / (1024.0 * 1024.0), 0))
        } else {
            format!("{} GB", to_string_as_fixed(s / (1024.0 * 1024.0 * 1024.0), 1))
        }
    }

    pub fn from_json(j: &Value) -> Self {
        let quality = j.get("quality").and_then(|q| q.get("quality")).and_then(|q| string(q, "name"));
        let rejections: Vec<String> = j
            .get("rejections")
            .and_then(Value::as_array)
            .map(|list| {
                list.iter()
                    .map(|r| match r {
                        Value::Object(_) => string(r, "reason").unwrap_or_else(|| r.to_string()),
                        other => dart_to_string(other),
                    })
                    .collect()
            })
            .unwrap_or_default();
        Self {
            guid: string(j, "guid").unwrap_or_default(),
            title: string(j, "title").unwrap_or_default(),
            indexer: string(j, "indexer").unwrap_or_default(),
            size: int(j, "size").unwrap_or(0),
            protocol: string(j, "protocol").unwrap_or_default(),
            quality: quality.unwrap_or_default(),
            age_in_days: int(j, "age").unwrap_or(0),
            rejected: !rejections.is_empty(),
            rejections,
            seeders: int(j, "seeders"),
            leechers: int(j, "leechers"),
            raw: j.as_object().cloned().unwrap_or_default(),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct LidarrRootFolder {
    pub id: i64,
    pub path: String,
}

impl LidarrRootFolder {
    pub fn from_json(j: &Value) -> Result<Self> {
        Ok(Self { id: required(int(j, "id"), "id")?, path: required(string(j, "path"), "path")? })
    }
}

impl fmt::Display for LidarrRootFolder {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(&self.path)
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct LidarrQualityProfile {
    pub id: i64,
    pub name: String,
}

impl LidarrQualityProfile {
    pub fn from_json(j: &Value) -> Result<Self> {
        Ok(Self { id: required(int(j, "id"), "id")?, name: required(string(j, "name"), "name")? })
    }
}

impl fmt::Display for LidarrQualityProfile {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(&self.name)
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct LidarrCustomFilter {
    pub id: i64,
    pub label: String,
    pub conditions: Vec<LidarrFilterCondition>,
}

impl LidarrCustomFilter {
    pub fn matches(&self, artist: &LidarrArtist) -> bool {
        self.conditions.iter().all(|c| c.matches(artist))
    }

    pub fn from_json(j: &Value) -> Result<Self> {
        let conditions = j
            .get("filters")
            .and_then(Value::as_array)
            .map(|l| l.iter().map(LidarrFilterCondition::from_json).collect())
            .unwrap_or_default();
        Ok(Self {
            id: required(int(j, "id"), "id")?,
            label: string(j, "label").unwrap_or_default(),
            conditions,
        })
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct LidarrFilterCondition {
    pub key: String,
    pub values: Vec<String>,
    pub operator: String,
}

impl LidarrFilterCondition {
    pub fn from_json(j: &Value) -> Self {
        let values = match j.get("value") {
            Some(Value::Array(list)) => list.iter().map(dart_to_string).collect(),
            None | Some(Value::Null) => Vec::new(),
            Some(v) => vec![dart_to_string(v)],
        };
        Self {
            key: string(j, "key").unwrap_or_default(),
            values,
            operator: string(j, "type").unwrap_or_default(),
        }
    }

    pub fn matches(&self, artist: &LidarrArtist) -> bool {
        let values = &self.values;
        match self.key.as_str() {
            "tags" => {
                let ids: HashSet<String> = artist.tag_ids.iter().map(i64::to_string).collect();
                return match self.operator.as_str() {
                    "contains" => values.iter().any(|v| ids.contains(v)),
                    "notContain" => values.iter().all(|v| !ids.contains(v)),
                    _ => true,
                };
            }
            "genres" => {
                let gs: HashSet<String> = artist.genres.iter().map(|g| g.to_lowercase()).collect();
                return match self.operator.as_str() {
                    "contains" => values.iter().any(|v| gs.contains(&v.to_lowercase())),
                    "notContain" => values.iter().all(|v| !gs.contains(&v.to_lowercase())),
                    _ => true,
                };
            }
            _ => {}
        }

        // Unknown field: pass through.
        let Some(field) = self.scalar_field(artist) else { return true };
        let eq = |b: &str| field.to_lowercase() == b.to_lowercase();
        let lower = field.to_lowercase();
        let num = |s: &str| s.trim().parse::<f64>().ok();
        match self.operator.as_str() {
            "equal" => values.iter().any(|v| eq(v)),
            "notEqual" => values.iter().all(|v| !eq(v)),
            "contains" => values.iter().any(|v| lower.contains(&v.to_lowercase())),
            "notContain" => values.iter().all(|v| !lower.contains(&v.to_lowercase())),
            "lessThan" => match (num(&field), values.first()) {
                (Some(f), Some(v)) => f < num(v).unwrap_or(0.0),
                _ => false,
            },
            "greaterThan" => match (num(&field), values.first()) {
                (Some(f), Some(v)) => f > num(v).unwrap_or(0.0),
                _ => false,
            },
            _ => true,
        }
    }

    fn scalar_field(&self, a: &LidarrArtist) -> Option<String> {
        match self.key.as_str() {
            "monitored" => Some(a.monitored.to_string()),
            "status" => a.status.clone(),
            "qualityProfileId" => Some(a.quality_profile_id.to_string()),
            "rootFolderPath" => a.root_folder_path.clone(),
            "albumCount" => Some(a.album_count.to_string()),
            "trackFileCount" => Some(a.track_file_count.to_string()),
            "totalTrackCount" => Some(a.total_track_count.to_string()),
            "percentOfTracks" => Some(to_string_as_fixed(a.percent_of_tracks(), 1)),
            _ => None,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    fn artist() -> LidarrArtist {
        LidarrArtist::from_json(&json!({
            "id": 3, "foreignArtistId": "mb", "artistName": "A", "monitored": true,
            "status": "continuing", "tags": [1, "x", 2], "genres": ["Rock", 5],
            "images": [{"coverType": "fanart", "url": "f"}, {"coverType": "poster", "url": "p"}],
            "statistics": {"albumCount": 2, "trackFileCount": 5, "totalTrackCount": 10}
        }))
    }

    fn cond(key: &str, value: Value, op: &str) -> LidarrFilterCondition {
        LidarrFilterCondition::from_json(&json!({"key": key, "value": value, "type": op}))
    }

    #[test]
    fn artist_parsing() {
        let a = artist();
        assert_eq!(a.tag_ids, vec![1, 2]);
        assert_eq!(a.genres, vec!["Rock"]);
        assert_eq!(a.poster_url.as_deref(), Some("p"));
        assert_eq!(a.percent_of_tracks(), 50.0);
        assert!(!a.is_missing());
    }

    #[test]
    fn filters() {
        let a = artist();
        assert!(cond("tags", json!([2]), "contains").matches(&a));
        assert!(!cond("tags", json!([2]), "notContain").matches(&a));
        assert!(cond("genres", json!("rock"), "contains").matches(&a));
        assert!(cond("monitored", json!(true), "equal").matches(&a));
        assert!(cond("percentOfTracks", json!("50.0"), "equal").matches(&a));
        assert!(cond("albumCount", json!(1), "greaterThan").matches(&a));
        assert!(!cond("albumCount", json!([]), "lessThan").matches(&a));
        assert!(cond("status", json!("CONT"), "contains").matches(&a));
        assert!(cond("unknown", json!("x"), "equal").matches(&a));
        let f = LidarrCustomFilter::from_json(&json!({"id": 1, "filters": [
            {"key": "monitored", "value": [true], "type": "equal"},
            {"key": "tags", "value": [9], "type": "contains"}
        ]}))
        .unwrap();
        assert!(!f.matches(&a));
    }

    #[test]
    fn album_and_release() {
        let al = LidarrAlbum::from_json(&json!({"albumType": "EP", "releaseDate": "2001-01-01T00:00:00Z",
            "statistics": {"trackFileCount": 1}}));
        assert_eq!(al.album_type, LidarrAlbumType::Ep);
        assert_eq!(al.year(), Some(2001));
        assert!(al.has_file);
        let r = LidarrRelease::from_json(&json!({"size": 1536, "rejections": ["a", {"reason": "b"}],
            "quality": {"quality": {"name": "FLAC"}}}));
        assert_eq!(r.rejections, vec!["a", "b"]);
        assert!(r.rejected);
        assert_eq!(r.quality, "FLAC");
        assert_eq!(r.formatted_size(), "2 KB");
        assert!(LidarrRootFolder::from_json(&json!({"id": 1})).is_err());
    }
}
