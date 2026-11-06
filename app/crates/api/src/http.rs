use std::error::Error as _;

use dapper_domain::AppError;
use url::Url;

/// Transport failure → `AppError::Network`. The URL is stripped because
/// signed Subsonic URLs carry the `t`/`s` auth params.
pub(crate) fn net_err(e: reqwest::Error) -> AppError {
    let e = e.without_url();
    let mut msg = e.to_string();
    let mut source = e.source();
    while let Some(s) = source {
        msg.push_str(": ");
        msg.push_str(&s.to_string());
        source = s.source();
    }
    AppError::Network(msg)
}

/// Dio-style `DioExceptionType.name` for transport failures, used in
/// user-facing scraper messages.
pub(crate) fn failure_kind(e: &reqwest::Error) -> &'static str {
    if e.is_timeout() {
        if e.is_connect() {
            "connectionTimeout"
        } else {
            "receiveTimeout"
        }
    } else if e.is_connect() {
        "connectionError"
    } else {
        "unknown"
    }
}

/// `base` + `path` keeping any base-URL path prefix (reverse-proxy subpath
/// deployments) and dropping trailing slashes so no `//` appears.
pub(crate) fn join(base: &Url, path: &str) -> Url {
    let mut url = base.clone();
    let base_path = url.path().trim_end_matches('/').to_string();
    if path.starts_with('/') {
        url.set_path(&format!("{base_path}{path}"));
    } else {
        url.set_path(&format!("{base_path}/{path}"));
    }
    url.set_query(None);
    url.set_fragment(None);
    url
}

pub(crate) fn parse_base(base_url: &str) -> dapper_domain::Result<Url> {
    Url::parse(base_url.trim()).map_err(|e| {
        AppError::Other(format!(
            "Invalid server URL '{}': {e}",
            redact_userinfo(base_url)
        ))
    })
}

/// `raw` with any `user:pass@` authority prefix replaced by `***@`, for
/// echoing user-entered URLs in errors and logs. Works on unparsable input.
pub(crate) fn redact_userinfo(raw: &str) -> String {
    let authority_start = raw.find("://").map_or(0, |i| i + 3);
    let rest = &raw[authority_start..];
    let authority_end = rest.find(['/', '?', '#']).unwrap_or(rest.len());
    match rest[..authority_end].rfind('@') {
        Some(at) => format!("{}***{}", &raw[..authority_start], &rest[at..]),
        None => raw.to_string(),
    }
}

/// Follows redirects only within the original scheme/host/port, so custom
/// credential headers (`X-Api-Key`, `X-Nd-Authorization`) — which reqwest
/// does not strip on cross-host hops — never reach another origin.
pub(crate) fn same_origin_redirects() -> reqwest::redirect::Policy {
    reqwest::redirect::Policy::custom(|attempt| {
        let same_origin = attempt
            .previous()
            .last()
            .is_none_or(|prev| prev.origin() == attempt.url().origin());
        if attempt.previous().len() > 10 {
            attempt.error("too many redirects")
        } else if same_origin {
            attempt.follow()
        } else {
            attempt.stop()
        }
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn redacts_userinfo_only() {
        assert_eq!(
            redact_userinfo("https://bob:s3cret@host:8/p@x"),
            "https://***@host:8/p@x"
        );
        assert_eq!(redact_userinfo("bob:pw@host"), "***@host");
        assert_eq!(redact_userinfo("ht!tp://a:b@c d"), "ht!tp://***@c d");
        assert_eq!(
            redact_userinfo("https://host/path?q=a@b"),
            "https://host/path?q=a@b"
        );
        let err = parse_base("https://bob:s3cret@ho st")
            .unwrap_err()
            .to_string();
        assert!(
            !err.contains("s3cret") && err.contains("***@ho st"),
            "{err}"
        );
    }
}
