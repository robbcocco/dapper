//! Spotify/Tidal playlist import: matcher and workflow.

pub mod matcher;
pub mod ports;
pub mod session;

pub use matcher::{AUTO_MATCH_THRESHOLD, RankedSong, SongMatcher, TrackMatch};
pub use ports::{PlaylistSink, PlaylistSource, SongSearch};
pub use session::{ImportSession, ImportState, MATCH_CONCURRENCY};
