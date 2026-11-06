use serde::{Deserialize, Serialize};
use serde_json::Value;

use crate::{AppError, Result};

#[derive(Debug, Clone, PartialEq, Eq, Hash, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct MbReleaseGroup {
    pub id: String,
    pub title: String,
    pub artist_name: Option<String>,
    pub first_release_date: Option<String>,
}

impl MbReleaseGroup {
    pub fn year(&self) -> Option<String> {
        let d = self.first_release_date.as_deref().filter(|d| !d.is_empty())?;
        Some(d.split('-').next().unwrap_or_default().to_string())
    }

    pub fn cover_art_thumb_url(&self) -> String {
        format!("https://coverartarchive.org/release-group/{}/front-250", self.id)
    }

    /// Parses a MusicBrainz release-group JSON object; `id`/`title` are required.
    pub fn from_json(json: &Value) -> Result<Self> {
        let req = |k: &str| {
            json.get(k)
                .and_then(Value::as_str)
                .map(str::to_string)
                .ok_or_else(|| AppError::Other(format!("release-group missing '{k}'")))
        };
        let artist_name = json
            .get("artist-credit")
            .and_then(Value::as_array)
            .and_then(|c| c.first())
            .and_then(|f| f.get("name"))
            .and_then(Value::as_str)
            .map(str::to_string);
        Ok(Self {
            id: req("id")?,
            title: req("title")?,
            artist_name,
            first_release_date: json.get("first-release-date").and_then(Value::as_str).map(str::to_string),
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses() {
        let g = MbReleaseGroup::from_json(&serde_json::json!({
            "id": "x", "title": "T", "first-release-date": "1999-05-01",
            "artist-credit": [{"name": "A"}]
        }))
        .unwrap();
        assert_eq!(g.artist_name.as_deref(), Some("A"));
        assert_eq!(g.year().as_deref(), Some("1999"));
        assert!(MbReleaseGroup::from_json(&serde_json::json!({"id": "x"})).is_err());
    }
}
