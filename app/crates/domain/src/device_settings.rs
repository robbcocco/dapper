use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum FolderStructure {
    /// Artist / Album / track
    #[default]
    ArtistAlbum,
    /// Artist / Year - Album / track
    ArtistAlbumYear,
    /// Artist / track
    ArtistOnly,
    /// track (all in music root)
    Flat,
    /// user template, see [`DeviceSettings::custom_folder_template`]
    Custom,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum FilenameFormat {
    /// title.ext
    None,
    /// 01 title.ext
    Track,
    /// 1-01 - title.ext
    #[default]
    DiscTrack,
    /// user template, see [`DeviceSettings::custom_filename_template`]
    Custom,
}

/// Per-device transcoding target. `Original` ships the server's file as-is.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum TranscodeFormat {
    #[default]
    Original,
    Mp3,
    Opus,
    Aac,
}

impl TranscodeFormat {
    /// Subsonic `format` parameter; `None` means use plain /rest/download.
    pub fn api_name(self) -> Option<&'static str> {
        match self {
            Self::Original => None,
            Self::Mp3 => Some("mp3"),
            Self::Opus => Some("opus"),
            Self::Aac => Some("aac"),
        }
    }

    /// Extension for the transferred file; `None` keeps the source suffix.
    pub fn file_extension(self) -> Option<&'static str> {
        match self {
            Self::Original => None,
            Self::Mp3 => Some("mp3"),
            Self::Opus => Some("opus"),
            Self::Aac => Some("m4a"),
        }
    }

    pub fn label(self) -> &'static str {
        match self {
            Self::Original => "Original",
            Self::Mp3 => "MP3",
            Self::Opus => "Opus",
            Self::Aac => "AAC",
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct DeviceSettings {
    pub device_path: String,
    pub music_root_folder: String,
    pub playlist_folder: String,
    pub folder_structure: FolderStructure,
    pub filename_format: FilenameFormat,
    pub include_year: bool,
    pub overwrite_existing: bool,
    pub transcode_format: TranscodeFormat,
    /// kbps cap passed as `maxBitRate`; only meaningful when transcoding.
    pub transcode_max_bit_rate: Option<i64>,
    /// One zip per album from /rest/download; honoured only for `Original`.
    pub use_zip_download: bool,
    /// Used when `filename_format == Custom`; extension appended automatically.
    pub custom_filename_template: String,
    /// Used when `folder_structure == Custom`; `/` separates components.
    pub custom_folder_template: String,
    pub auto_clean_metadata: bool,
    pub auto_shrink_cover_art: bool,
}

impl Default for DeviceSettings {
    fn default() -> Self {
        Self::new("")
    }
}

impl DeviceSettings {
    pub fn new(device_path: impl Into<String>) -> Self {
        Self {
            device_path: device_path.into(),
            music_root_folder: String::new(),
            playlist_folder: "Playlists".into(),
            folder_structure: FolderStructure::ArtistAlbum,
            filename_format: FilenameFormat::DiscTrack,
            include_year: false,
            overwrite_existing: false,
            transcode_format: TranscodeFormat::Original,
            transcode_max_bit_rate: None,
            use_zip_download: true,
            custom_filename_template: String::new(),
            custom_folder_template: String::new(),
            auto_clean_metadata: true,
            auto_shrink_cover_art: true,
        }
    }

    /// Absolute music directory: `music_root_folder` (either slash style)
    /// joined onto `device_path` with the platform separator, like `p.joinAll`.
    pub fn resolved_music_root(&self) -> String {
        let trimmed = self.music_root_folder.trim();
        if trimmed.is_empty() {
            return self.device_path.clone();
        }
        let normalised = trimmed.replace('\\', "/");
        let parts: Vec<&str> = normalised.split('/').filter(|s| !s.is_empty() && *s != ".").collect();
        if parts.is_empty() {
            return self.device_path.clone();
        }
        let sep = std::path::MAIN_SEPARATOR;
        // p.split keeps a leading root, and joining an absolute part discards
        // everything before it.
        let mut out = if normalised.starts_with('/') { sep.to_string() } else { self.device_path.clone() };
        for part in parts {
            if !out.is_empty() && !out.ends_with(['/', sep]) {
                out.push(sep);
            }
            out.push_str(part);
        }
        out
    }

    pub fn is_transcoding(&self) -> bool {
        self.transcode_format != TranscodeFormat::Original
    }
}

/// `None` when valid, else a human-readable reason for inline error text.
pub fn validate_music_root_path(input: &str) -> Option<&'static str> {
    let trimmed = input.trim();
    if trimmed.is_empty() {
        return None;
    }
    if trimmed.starts_with('/') || trimmed.starts_with('\\') {
        return Some("Use a relative path (no leading slash)");
    }
    // Dart indexes UTF-16 units; only an ASCII ':' can match, so chars suffice.
    if trimmed.encode_utf16().nth(1) == Some(u16::from(b':')) {
        return Some("Use a relative path (no drive letter)");
    }
    if trimmed.replace('\\', "/").split('/').any(|s| s == "..") {
        return Some("Path cannot contain '..'");
    }
    None
}

#[cfg(test)]
mod tests {
    use super::*;

    fn with_root(device: &str, root: &str) -> DeviceSettings {
        DeviceSettings { music_root_folder: root.into(), ..DeviceSettings::new(device) }
    }

    #[test]
    fn api_name() {
        assert_eq!(TranscodeFormat::Original.api_name(), None);
        assert_eq!(TranscodeFormat::Mp3.api_name(), Some("mp3"));
        assert_eq!(TranscodeFormat::Opus.api_name(), Some("opus"));
        assert_eq!(TranscodeFormat::Aac.api_name(), Some("aac"));
    }

    #[test]
    fn file_extension() {
        assert_eq!(TranscodeFormat::Original.file_extension(), None);
        assert_eq!(TranscodeFormat::Mp3.file_extension(), Some("mp3"));
        assert_eq!(TranscodeFormat::Opus.file_extension(), Some("opus"));
        assert_eq!(TranscodeFormat::Aac.file_extension(), Some("m4a"));
    }

    #[test]
    fn is_transcoding() {
        assert!(!DeviceSettings::new("/x").is_transcoding());
        for f in [TranscodeFormat::Mp3, TranscodeFormat::Opus, TranscodeFormat::Aac] {
            assert!(DeviceSettings { transcode_format: f, ..DeviceSettings::new("/x") }.is_transcoding());
        }
    }

    #[cfg(unix)]
    #[test]
    fn resolved_music_root() {
        let d = "/Volumes/USB";
        assert_eq!(DeviceSettings::new(d).resolved_music_root(), "/Volumes/USB");
        assert_eq!(with_root(d, "Music").resolved_music_root(), "/Volumes/USB/Music");
        assert_eq!(with_root(d, "Music/FLAC/Library").resolved_music_root(), "/Volumes/USB/Music/FLAC/Library");
        assert_eq!(with_root(d, r"Music\FLAC").resolved_music_root(), "/Volumes/USB/Music/FLAC");
        assert_eq!(with_root(d, "  Music//FLAC  ").resolved_music_root(), "/Volumes/USB/Music/FLAC");
    }

    #[cfg(windows)]
    #[test]
    fn resolved_music_root() {
        let d = r"E:\";
        assert_eq!(DeviceSettings::new(d).resolved_music_root(), r"E:\");
        assert_eq!(with_root(d, "Music").resolved_music_root(), r"E:\Music");
        assert_eq!(with_root(d, "Music/FLAC/Library").resolved_music_root(), r"E:\Music\FLAC\Library");
        assert_eq!(with_root(d, r"Music\FLAC").resolved_music_root(), r"E:\Music\FLAC");
        assert_eq!(with_root(d, "  Music//FLAC  ").resolved_music_root(), r"E:\Music\FLAC");
        assert_eq!(with_root("E:", "Music").resolved_music_root(), r"E:\Music");
    }

    #[test]
    fn validate() {
        assert_eq!(validate_music_root_path(""), None);
        assert_eq!(validate_music_root_path("   "), None);
        assert_eq!(validate_music_root_path("Music"), None);
        assert_eq!(validate_music_root_path("Music/FLAC"), None);
        assert_eq!(validate_music_root_path(r"Music\FLAC"), None);
        assert!(validate_music_root_path("/Music").is_some());
        assert!(validate_music_root_path(r"\Music").is_some());
        assert!(validate_music_root_path("C:/Music").is_some());
        assert!(validate_music_root_path(r"C:\Music").is_some());
        assert!(validate_music_root_path("Music/../Other").is_some());
        assert!(validate_music_root_path("..").is_some());
    }

    #[test]
    fn serde_defaults_and_names() {
        let s: DeviceSettings = serde_json::from_str(r#"{"devicePath":"/v","folderStructure":"artistAlbumYear"}"#).unwrap();
        assert_eq!(s.folder_structure, FolderStructure::ArtistAlbumYear);
        assert_eq!(s.playlist_folder, "Playlists");
        assert!(s.use_zip_download);
        assert_eq!(serde_json::to_value(FilenameFormat::DiscTrack).unwrap(), "discTrack");
    }
}
