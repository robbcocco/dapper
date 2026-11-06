//! Per-server SQLite library cache, incremental sync, FTS5 search, windowed queries.

mod db;
mod fts;
mod library;
mod schema;
mod sync;
#[cfg(test)]
mod tests;
mod types;

pub use db::LibraryDb;
pub use library::Library;
pub use types::{
    AlbumSort, LibraryStatus, Page, SearchLimits, SongSort, SortDir, SyncPhase, SyncProgress,
    SyncReport,
};

/// Timestamp format Subsonic uses for `starred`/`created`.
pub(crate) fn now_iso() -> String {
    chrono::Utc::now().to_rfc3339_opts(chrono::SecondsFormat::Secs, true)
}
