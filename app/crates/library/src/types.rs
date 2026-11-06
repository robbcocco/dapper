use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum SortDir {
    #[default]
    Asc,
    Desc,
}

impl SortDir {
    pub(crate) fn sql(self) -> &'static str {
        match self {
            Self::Asc => "ASC",
            Self::Desc => "DESC",
        }
    }
}

/// Album grid orderings. `Recent` orders by the server's `created` timestamp,
/// so `Desc` is newest first.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum AlbumSort {
    #[default]
    Name,
    Artist,
    Year,
    Recent,
}

impl AlbumSort {
    /// The direction only applies to the primary key; tiebreakers stay
    /// ascending so equal-year/equal-artist runs read naturally.
    pub(crate) fn order_by(self, dir: SortDir) -> String {
        let d = dir.sql();
        match self {
            Self::Name => format!("sort_name {d}, sort_artist, id"),
            Self::Artist => format!("sort_artist {d}, year, sort_name, id"),
            Self::Year => format!("year IS NULL, year {d}, sort_artist, sort_name, id"),
            Self::Recent => format!("created IS NULL, created {d}, id"),
        }
    }

    /// Closest `getAlbumList2` type for the server fallback.
    pub(crate) fn list_type(self) -> &'static str {
        match self {
            Self::Name | Self::Year => "alphabeticalByName",
            Self::Artist => "alphabeticalByArtist",
            Self::Recent => "newest",
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum SongSort {
    #[default]
    Title,
    Artist,
    Album,
    Year,
    Duration,
    /// Album order with disc/track kept ascending — same keys as `Album`,
    /// exposed separately so the UI's track column maps one-to-one.
    Track,
}

impl SongSort {
    pub(crate) fn order_by(self, dir: SortDir) -> String {
        let d = dir.sql();
        match self {
            Self::Title => format!("sort_title {d}, id"),
            Self::Artist => format!("sort_artist {d}, sort_album, disc_number, track, id"),
            Self::Album | Self::Track => format!("sort_album {d}, disc_number, track, id"),
            Self::Year => {
                format!("year IS NULL, year {d}, sort_artist, sort_album, disc_number, track, id")
            }
            Self::Duration => format!("duration {d}, id"),
        }
    }
}

/// One window of a sorted list. `total` is `None` when the window came from
/// the server (before the first completed sync), where callers page until a
/// short window instead.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Page<T> {
    pub items: Vec<T>,
    pub total: Option<i64>,
}

/// Per-kind result caps for [`crate::LibraryDb::search`].
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SearchLimits {
    pub artists: i64,
    pub albums: i64,
    pub songs: i64,
}

impl Default for SearchLimits {
    fn default() -> Self {
        Self {
            artists: 20,
            albums: 40,
            songs: 100,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum SyncPhase {
    ScanStatus,
    Artists,
    Albums,
    Songs,
    Starred,
    Genres,
    Playlists,
    Sweep,
    Done,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SyncProgress {
    pub phase: SyncPhase,
    pub done: i64,
    pub total: Option<i64>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SyncReport {
    /// True when the server's scan status matched the last completed sync, so
    /// only starred flags and playlists were refreshed.
    pub skipped: bool,
    pub artists: i64,
    pub albums: i64,
    pub songs: i64,
    pub removed_artists: i64,
    pub removed_albums: i64,
    pub removed_songs: i64,
}

/// Snapshot of the cache for status displays.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct LibraryStatus {
    /// A full sync has completed at least once; reads are served from cache.
    pub ready: bool,
    /// RFC 3339 time the last full sync completed.
    pub completed_at: Option<String>,
    /// Server `lastScan` recorded by the last full sync.
    pub last_scan: Option<String>,
    pub artists: i64,
    pub albums: i64,
    pub songs: i64,
    pub playlists: i64,
}
