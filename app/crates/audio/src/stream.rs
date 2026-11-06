use std::sync::Arc;
use std::time::Duration;

use dapper_domain::Song;
use rodio::{Decoder, Source};
use stream_download::http::HttpStream;
use stream_download::storage::temp::TempStorageProvider;
use stream_download::{Settings, StreamDownload};
use url::Url;

use crate::codec::is_natively_decodable;

/// Builds the signed stream URL for a song. `transcode = true` must request a
/// format every build can decode (Dapper maps it to `format=mp3&maxBitRate=320`).
pub trait StreamResolver: Send + Sync {
    fn stream_url(&self, song: &Song, transcode: bool) -> Url;
}

pub(crate) type TrackSource = Decoder<StreamDownload<TempStorageProvider>>;

pub(crate) struct LoadedTrack {
    pub source: TrackSource,
    pub duration: Duration,
}

enum OpenError {
    /// The server couldn't be reached or refused the request.
    Fetch(String),
    /// The bytes arrived but no enabled decoder accepted them.
    Decode(String),
}

impl OpenError {
    fn into_message(self) -> String {
        match self {
            Self::Fetch(m) | Self::Decode(m) => m,
        }
    }
}

pub(crate) struct Loader {
    client: reqwest::Client,
    resolver: Arc<dyn StreamResolver>,
}

impl Loader {
    pub fn new(resolver: Arc<dyn StreamResolver>) -> Self {
        Self {
            client: reqwest::Client::new(),
            resolver,
        }
    }

    /// Opens the original file when the enabled codecs can handle it, falling
    /// back to a server-side transcode when they can't (or the decoder rejects
    /// the stream at open).
    pub async fn load(&self, song: &Song) -> Result<LoadedTrack, String> {
        if is_natively_decodable(song) {
            match self.open(song, false).await {
                Ok(track) => return Ok(track),
                Err(OpenError::Decode(e)) => {
                    tracing::info!(song_id = %song.id, error = %e, "original stream not decodable; requesting transcode");
                }
                Err(e) => return Err(e.into_message()),
            }
        }
        self.open(song, true).await.map_err(OpenError::into_message)
    }

    async fn open(&self, song: &Song, transcode: bool) -> Result<LoadedTrack, OpenError> {
        let url = self.resolver.stream_url(song, transcode);
        // Error texts from reqwest/stream-download embed the URL, which carries
        // the Subsonic auth token: scrub it before anything is shown or logged.
        let redact = |msg: String| msg.replace(url.as_str(), "<stream url>");

        let stream = HttpStream::new(self.client.clone(), url.clone())
            .await
            .map_err(|e| {
                use stream_download::http::HttpStreamError;
                OpenError::Fetch(match e {
                    HttpStreamError::FetchFailure(e) => e.without_url().to_string(),
                    HttpStreamError::ResponseFailure(e) => {
                        format!("HTTP {}", e.response().status())
                    }
                })
            })?;
        let mime = stream
            .content_type()
            .as_ref()
            .map(|ct| format!("{}/{}", ct.r#type, ct.subtype));
        let reader = StreamDownload::from_stream(
            stream,
            TempStorageProvider::default(),
            Settings::default(),
        )
        .await
        .map_err(|e| OpenError::Fetch(redact(e.to_string())))?;
        let byte_len = reader.content_length();
        let hint = if transcode {
            Some("mp3".to_owned())
        } else {
            song.suffix.as_deref().map(str::to_ascii_lowercase)
        };

        let source = tokio::task::spawn_blocking(move || {
            let mut builder = Decoder::builder().with_data(reader).with_gapless(true);
            // Random access needs the length; without it (chunked transcodes)
            // only forward seeking is possible.
            if let Some(len) = byte_len {
                builder = builder.with_byte_len(len).with_seekable(true);
            }
            if let Some(hint) = &hint {
                builder = builder.with_hint(hint);
            }
            if let Some(mime) = &mime {
                builder = builder.with_mime_type(mime);
            }
            builder.build()
        })
        .await
        .map_err(|e| OpenError::Decode(e.to_string()))?
        .map_err(|e| OpenError::Decode(redact(e.to_string())))?;

        let duration = source
            .total_duration()
            .or_else(|| {
                song.duration
                    .filter(|d| *d > 0)
                    .map(|d| Duration::from_secs(d.unsigned_abs()))
            })
            .unwrap_or_default();
        Ok(LoadedTrack { source, duration })
    }
}
