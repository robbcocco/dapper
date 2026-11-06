use std::path::Path;

use dapper_domain::{AppError, Result};
use tokio::io::{AsyncWriteExt, BufWriter};
use tokio_util::sync::CancellationToken;

use crate::http::net_err;

const WRITE_BUFFER: usize = 256 * 1024;

/// Streams `url` into `dest` (created/truncated) chunk by chunk, never holding
/// the body in memory. `on_progress(received, total)` fires after every chunk;
/// `total` is the server's Content-Length when known. On failure or
/// cancellation the partial file is removed (Dio's `deleteOnError`).
/// HTTP 401/403 → `AppError::Auth`; other non-2xx → `AppError::Network`.
pub async fn download_to_file(
    http: &reqwest::Client,
    url: &str,
    dest: &Path,
    mut on_progress: impl FnMut(u64, Option<u64>),
    cancel: CancellationToken,
) -> Result<u64> {
    let mut created = false;
    let result = async {
        let mut resp = tokio::select! {
            _ = cancel.cancelled() => return Err(AppError::Cancelled),
            r = http.get(url).send() => r.map_err(net_err)?,
        };
        let status = resp.status();
        if status.as_u16() == 401 || status.as_u16() == 403 {
            return Err(AppError::Auth);
        }
        if !status.is_success() {
            return Err(AppError::Network(format!(
                "Download failed: HTTP {}",
                status.as_u16()
            )));
        }
        let total = resp.content_length();
        let file = tokio::fs::File::create(dest).await?;
        created = true;
        let mut out = BufWriter::with_capacity(WRITE_BUFFER, file);
        let mut received = 0u64;
        loop {
            let chunk = tokio::select! {
                _ = cancel.cancelled() => return Err(AppError::Cancelled),
                c = resp.chunk() => c.map_err(net_err)?,
            };
            let Some(chunk) = chunk else { break };
            out.write_all(&chunk).await?;
            received += chunk.len() as u64;
            on_progress(received, total);
        }
        out.flush().await?;
        out.into_inner().sync_all().await?;
        Ok(received)
    }
    .await;
    if result.is_err() && created {
        match tokio::fs::remove_file(dest).await {
            Ok(()) => {}
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => {}
            Err(e) => {
                tracing::warn!(path = %dest.display(), error = %e, "could not remove partial download")
            }
        }
    }
    result
}

#[cfg(test)]
mod tests {
    use super::*;
    use wiremock::matchers::{method, path};
    use wiremock::{Mock, MockServer, ResponseTemplate};

    #[tokio::test]
    async fn streams_body_to_file_with_progress() {
        let server = MockServer::start().await;
        let body: Vec<u8> = (0..200_000u32).map(|i| (i % 251) as u8).collect();
        Mock::given(method("GET"))
            .and(path("/f"))
            .respond_with(ResponseTemplate::new(200).set_body_bytes(body.clone()))
            .mount(&server)
            .await;
        let dir = tempfile::tempdir().unwrap();
        let dest = dir.path().join("out.bin");
        let mut last = (0, None);
        let n = download_to_file(
            &reqwest::Client::new(),
            &format!("{}/f", server.uri()),
            &dest,
            |r, t| last = (r, t),
            CancellationToken::new(),
        )
        .await
        .unwrap();
        assert_eq!(n, body.len() as u64);
        assert_eq!(last, (body.len() as u64, Some(body.len() as u64)));
        assert_eq!(std::fs::read(&dest).unwrap(), body);
    }

    #[tokio::test]
    async fn cancelled_and_failed_downloads_leave_no_file() {
        let server = MockServer::start().await;
        Mock::given(path("/ok"))
            .respond_with(ResponseTemplate::new(200).set_body_bytes(vec![1u8; 10]))
            .mount(&server)
            .await;
        Mock::given(path("/gone"))
            .respond_with(ResponseTemplate::new(404))
            .mount(&server)
            .await;
        Mock::given(path("/auth"))
            .respond_with(ResponseTemplate::new(403))
            .mount(&server)
            .await;
        let dir = tempfile::tempdir().unwrap();
        let dest = dir.path().join("x");
        let http = reqwest::Client::new();

        let token = CancellationToken::new();
        token.cancel();
        let r = download_to_file(
            &http,
            &format!("{}/ok", server.uri()),
            &dest,
            |_, _| {},
            token,
        )
        .await;
        assert_eq!(r, Err(AppError::Cancelled));
        assert!(!dest.exists());

        let r = download_to_file(
            &http,
            &format!("{}/gone", server.uri()),
            &dest,
            |_, _| {},
            CancellationToken::new(),
        )
        .await;
        assert!(matches!(r, Err(AppError::Network(_))));
        assert!(!dest.exists());

        let r = download_to_file(
            &http,
            &format!("{}/auth", server.uri()),
            &dest,
            |_, _| {},
            CancellationToken::new(),
        )
        .await;
        assert_eq!(r, Err(AppError::Auth));
    }
}
