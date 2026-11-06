//! HTTP clients: Subsonic, Navidrome native, Lidarr, MusicBrainz, Spotify and Tidal scrapers.

mod download;
mod dto;
mod http;
mod lidarr_client;
mod musicbrainz_client;
mod navidrome_client;
mod spotify_scraper;
mod subsonic_api;
mod subsonic_client;
mod tidal_scraper;

pub use download::download_to_file;
pub use lidarr_client::LidarrClient;
pub use musicbrainz_client::MusicBrainzClient;
pub use navidrome_client::NavidromeClient;
pub use spotify_scraper::{PlaylistScraper, SpotifyScraper};
pub use subsonic_api::{ScanStatus, StarredIds, SubsonicApi};
pub use subsonic_client::{
    API_VERSION, CLIENT_NAME, Params, RESPONSE_FORMAT, SubsonicClient, endpoints,
};
pub use tidal_scraper::TidalScraper;
pub use tokio_util::sync::CancellationToken;
