use std::sync::Arc;
use std::time::Duration;

use bytes::Bytes;
use dapper_domain::{AppError, Result};
use reqwest::header::{AUTHORIZATION, COOKIE, HeaderValue, SET_COOKIE};
use reqwest::multipart::{Form, Part};
use reqwest::{RequestBuilder, Response};
use serde_json::Value;
use url::Url;

use crate::http::{join, net_err, parse_base, same_origin_redirects};

struct Session {
    bearer: HeaderValue,
    cookie: Option<HeaderValue>,
}

/// Navidrome's native REST API (JWT from `/auth/login`), used for edits the
/// Subsonic API can't do: song tag PATCH and album cover upload.
pub struct NavidromeClient {
    http: reqwest::Client,
    base: Url,
    username: String,
    password: String,
    // Held across the login so concurrent first calls share one POST
    // /auth/login instead of racing and clobbering each other's token.
    session: tokio::sync::Mutex<Option<Arc<Session>>>,
}

impl NavidromeClient {
    pub fn new(base_url: &str, username: &str, password: &str) -> Result<Self> {
        Ok(Self {
            http: reqwest::Client::builder()
                .connect_timeout(Duration::from_secs(10))
                .read_timeout(Duration::from_secs(30))
                .redirect(same_origin_redirects())
                .build()
                .map_err(net_err)?,
            base: parse_base(base_url)?,
            username: username.into(),
            password: password.into(),
            session: tokio::sync::Mutex::new(None),
        })
    }

    async fn session(&self) -> Result<Arc<Session>> {
        let mut guard = self.session.lock().await;
        if let Some(s) = guard.as_ref() {
            return Ok(s.clone());
        }
        let s = Arc::new(self.login().await?);
        *guard = Some(s.clone());
        Ok(s)
    }

    async fn invalidate(&self, stale: &Arc<Session>) {
        let mut guard = self.session.lock().await;
        if guard.as_ref().is_some_and(|s| Arc::ptr_eq(s, stale)) {
            *guard = None;
        }
    }

    async fn login(&self) -> Result<Session> {
        tracing::debug!(username = %self.username, "navidrome login");
        let resp = self
            .http
            .post(join(&self.base, "/auth/login"))
            .json(&serde_json::json!({"username": self.username, "password": self.password}))
            .send()
            .await
            .map_err(net_err)?;
        let status = resp.status().as_u16();
        if !resp.status().is_success() {
            return Err(AppError::Other(format!(
                "Navidrome login failed — status {status}"
            )));
        }
        // Some Navidrome versions validate the session via cookie as well.
        let cookies: Vec<&str> = resp
            .headers()
            .get_all(SET_COOKIE)
            .iter()
            .filter_map(|c| c.to_str().ok())
            .map(|c| c.split(';').next().unwrap_or_default().trim())
            .collect();
        let cookie = if cookies.is_empty() {
            None
        } else {
            Some(cookies.join("; "))
        };
        let body: Value = resp.json().await.unwrap_or(Value::Null);
        let token = body
            .get("token")
            .and_then(Value::as_str)
            .map(str::trim)
            .unwrap_or_default();
        if token.is_empty() {
            return Err(AppError::Other(format!(
                "Login returned {status} but response had no token."
            )));
        }
        let mut bearer = HeaderValue::from_str(&format!("Bearer {token}"))
            .map_err(|_| AppError::Other("Navidrome returned an invalid token".into()))?;
        bearer.set_sensitive(true);
        let cookie = match cookie {
            Some(c) => {
                let mut v = HeaderValue::from_str(&c).map_err(|_| {
                    AppError::Other("Navidrome returned an invalid session cookie".into())
                })?;
                v.set_sensitive(true);
                Some(v)
            }
            None => None,
        };
        tracing::debug!("navidrome token obtained");
        Ok(Session { bearer, cookie })
    }

    fn authorize(rb: RequestBuilder, s: &Session) -> RequestBuilder {
        // Standard Bearer plus Navidrome's own header as a fallback.
        let rb = rb
            .header(AUTHORIZATION, s.bearer.clone())
            .header("X-Nd-Authorization", s.bearer.clone());
        match &s.cookie {
            Some(c) => rb.header(COOKIE, c.clone()),
            None => rb,
        }
    }

    async fn failure(resp: Response) -> (u16, String) {
        let status = resp.status().as_u16();
        (status, resp.text().await.unwrap_or_default())
    }

    /// Runs `build` with fresh auth; on 401 re-logs in and retries once.
    async fn call(&self, description: &str, build: impl Fn() -> RequestBuilder) -> Result<()> {
        let session = self.session().await?;
        let resp = Self::authorize(build(), &session)
            .send()
            .await
            .map_err(net_err)?;
        if resp.status().is_success() {
            return Ok(());
        }
        let (status, body) = Self::failure(resp).await;
        tracing::debug!(%description, status, "navidrome request failed");
        if status == 401 {
            self.invalidate(&session).await;
            let session = self.session().await?;
            let resp = Self::authorize(build(), &session)
                .send()
                .await
                .map_err(net_err)?;
            if resp.status().is_success() {
                return Ok(());
            }
            let (s, b) = Self::failure(resp).await;
            return Err(AppError::Other(format!(
                "{description} failed after re-auth — status {s}, body: {b}"
            )));
        }
        Err(AppError::Other(format!(
            "{description} failed — status {status}, body: {body}"
        )))
    }

    /// `PATCH /api/song/{id}` with a JSON object of tag fields.
    pub async fn update_song(&self, id: &str, fields: &Value) -> Result<()> {
        let url = join(&self.base, &format!("/api/song/{id}"));
        self.call(&format!("PATCH /api/song/{id}"), || {
            self.http.patch(url.clone()).json(fields)
        })
        .await
    }

    /// `POST /api/album/{id}/image` multipart (`file`, `cover.jpg`).
    pub async fn upload_album_cover(&self, album_id: &str, image: impl Into<Bytes>) -> Result<()> {
        let image: Bytes = image.into();
        let url = join(&self.base, &format!("/api/album/{album_id}/image"));
        self.call(&format!("POST /api/album/{album_id}/image"), || {
            let part =
                Part::stream_with_length(reqwest::Body::from(image.clone()), image.len() as u64)
                    .file_name("cover.jpg")
                    .mime_str("application/octet-stream")
                    .expect("valid mime");
            self.http
                .post(url.clone())
                .multipart(Form::new().part("file", part))
        })
        .await
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use wiremock::matchers::{body_json, header, method, path};
    use wiremock::{Mock, MockServer, ResponseTemplate};

    async fn login_mock(server: &MockServer, token: &str, expect: u64) {
        Mock::given(method("POST"))
            .and(path("/nd/auth/login"))
            .and(body_json(
                serde_json::json!({"username": "u", "password": "p"}),
            ))
            .respond_with(
                ResponseTemplate::new(200)
                    .insert_header("set-cookie", "nd=abc; Path=/; HttpOnly")
                    .set_body_json(serde_json::json!({"token": token})),
            )
            .up_to_n_times(1)
            .expect(expect)
            .mount(server)
            .await;
    }

    #[tokio::test]
    async fn concurrent_calls_share_one_login_and_send_auth_headers() {
        let server = MockServer::start().await;
        login_mock(&server, "tok1", 1).await;
        Mock::given(method("PATCH"))
            .and(path("/nd/api/song/s1"))
            .and(header("authorization", "Bearer tok1"))
            .and(header("x-nd-authorization", "Bearer tok1"))
            .and(header("cookie", "nd=abc"))
            .respond_with(ResponseTemplate::new(200))
            .expect(2)
            .mount(&server)
            .await;
        let c = NavidromeClient::new(&format!("{}/nd/", server.uri()), "u", "p").unwrap();
        let fields = serde_json::json!({"title": "x"});
        let (a, b) = tokio::join!(c.update_song("s1", &fields), c.update_song("s1", &fields));
        a.unwrap();
        b.unwrap();
    }

    #[tokio::test]
    async fn retries_once_after_401_with_a_fresh_token() {
        let server = MockServer::start().await;
        login_mock(&server, "old", 1).await;
        Mock::given(method("POST"))
            .and(path("/nd/api/album/a1/image"))
            .and(header("authorization", "Bearer old"))
            .respond_with(ResponseTemplate::new(401))
            .mount(&server)
            .await;
        let c = NavidromeClient::new(&format!("{}/nd", server.uri()), "u", "p").unwrap();
        c.session().await.unwrap();
        login_mock(&server, "new", 1).await;
        Mock::given(method("POST"))
            .and(path("/nd/api/album/a1/image"))
            .and(header("authorization", "Bearer new"))
            .respond_with(ResponseTemplate::new(200))
            .expect(1)
            .mount(&server)
            .await;
        c.upload_album_cover("a1", vec![1u8, 2, 3]).await.unwrap();
    }

    #[tokio::test]
    async fn failure_after_reauth_reports_status() {
        let server = MockServer::start().await;
        Mock::given(path("/auth/login"))
            .respond_with(
                ResponseTemplate::new(200).set_body_json(serde_json::json!({"token": "t"})),
            )
            .mount(&server)
            .await;
        Mock::given(path("/api/song/s"))
            .respond_with(ResponseTemplate::new(401).set_body_string("no"))
            .mount(&server)
            .await;
        let c = NavidromeClient::new(&server.uri(), "u", "p").unwrap();
        let err = c
            .update_song("s", &serde_json::json!({}))
            .await
            .unwrap_err();
        assert_eq!(
            err,
            AppError::Other("PATCH /api/song/s failed after re-auth — status 401, body: no".into())
        );
    }
}
