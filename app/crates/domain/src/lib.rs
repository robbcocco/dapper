//! Shared models, enums, errors and cross-crate traits.

mod album;
mod app_exception;
mod app_settings;
mod artist;
mod connected_device;
mod device_settings;
mod genre;
mod lidarr_instance;
mod lidarr_models;
mod lyrics;
mod musicbrainz_result;
mod navidrome_server;
mod num_format;
mod playlist;
mod search_results;
mod song;
mod spotify_track;
mod status;
mod traits;
mod transfer_task;

pub use album::Album;
pub use app_exception::{AppError, Result};
pub use app_settings::AppSettings;
pub use artist::Artist;
pub use connected_device::{ConnectedDevice, EjectResult};
pub use device_settings::{
    DeviceSettings, FilenameFormat, FolderStructure, TranscodeFormat, validate_music_root_path,
};
pub use genre::Genre;
pub use lidarr_instance::LidarrInstance;
pub use lidarr_models::{
    LidarrAlbum, LidarrAlbumLookup, LidarrAlbumType, LidarrArtist, LidarrCustomFilter,
    LidarrFilterCondition, LidarrQualityProfile, LidarrRelease, LidarrRootFolder,
};
pub use lyrics::{Lyrics, LyricsLine};
pub use musicbrainz_result::MbReleaseGroup;
pub use navidrome_server::NavidromeServer;
pub use num_format::to_string_as_fixed;
pub use playlist::Playlist;
pub use search_results::SearchResults;
pub use song::Song;
pub use spotify_track::{PlaylistProvider, SpotifyPlaylistData, SpotifyTrack};
pub use status::{AlbumSyncStatus, ArtistSyncStatus, RepeatMode};
pub use traits::{LibraryReader, ScrobbleSink};
pub use transfer_task::{TransferStatus, TransferTask};
