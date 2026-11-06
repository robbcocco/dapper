use serde::{Deserialize, Serialize};

/// One lyrics line; `start_ms` is the absolute timestamp (synced lyrics only).
#[derive(Debug, Clone, PartialEq, Eq, Hash, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct LyricsLine {
    pub text: String,
    pub start_ms: Option<i64>,
}

#[derive(Debug, Clone, PartialEq, Eq, Hash, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Lyrics {
    pub lines: Vec<LyricsLine>,
    pub synced: bool,
    pub lang: Option<String>,
}

impl Lyrics {
    pub fn is_empty(&self) -> bool {
        self.lines.is_empty()
    }

    pub fn is_not_empty(&self) -> bool {
        !self.lines.is_empty()
    }
}
