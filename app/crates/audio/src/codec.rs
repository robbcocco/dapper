use dapper_domain::Song;

/// Container suffixes the enabled symphonia demuxers/decoders can open. Their
/// codec may still be unsupported (e.g. Opus in Ogg/WebM); that surfaces as a
/// decoder error at open, which also triggers the transcode fallback.
const DECODABLE_SUFFIXES: &[&str] = &[
    "mp3", "mp2", "mp1", "flac", "wav", "wave", "aif", "aiff", "aifc", "caf", "m4a", "m4b", "mp4",
    "aac", "adts", "ogg", "oga", "mka", "mkv", "webm",
];

const DECODABLE_CONTENT_TYPES: &[&str] = &[
    "audio/mpeg",
    "audio/mp3",
    "audio/mpeg3",
    "audio/x-mpeg",
    "audio/flac",
    "audio/x-flac",
    "audio/wav",
    "audio/wave",
    "audio/x-wav",
    "audio/vnd.wave",
    "audio/aiff",
    "audio/x-aiff",
    "audio/x-caf",
    "audio/mp4",
    "audio/m4a",
    "audio/x-m4a",
    "audio/aac",
    "audio/aacp",
    "audio/x-aac",
    "audio/ogg",
    "audio/vorbis",
    "audio/x-matroska",
    "audio/webm",
];

/// Whether the original file is worth handing to the decoder, judged from the
/// song's suffix (preferred) or content type. Unknown metadata → try it.
pub fn is_natively_decodable(song: &Song) -> bool {
    if let Some(suffix) = song
        .suffix
        .as_deref()
        .map(str::trim)
        .filter(|s| !s.is_empty())
    {
        let suffix = suffix.to_ascii_lowercase();
        return DECODABLE_SUFFIXES.contains(&suffix.as_str());
    }
    if let Some(ct) = song.content_type.as_deref() {
        let mime = ct
            .split(';')
            .next()
            .unwrap_or_default()
            .trim()
            .to_ascii_lowercase();
        if !mime.is_empty() {
            return DECODABLE_CONTENT_TYPES.contains(&mime.as_str());
        }
    }
    true
}

#[cfg(test)]
mod tests {
    use super::*;

    fn song(suffix: Option<&str>, content_type: Option<&str>) -> Song {
        Song {
            suffix: suffix.map(Into::into),
            content_type: content_type.map(Into::into),
            ..Song::default()
        }
    }

    #[test]
    fn decodable_suffixes() {
        for s in ["mp3", "FLAC", "wav", "m4a", "ogg", "aiff", "caf"] {
            assert!(is_natively_decodable(&song(Some(s), None)), "{s}");
        }
    }

    #[test]
    fn undecodable_suffixes_need_transcode() {
        for s in ["opus", "ape", "wma", "wv", "dsf", "dff", "mpc", "tta"] {
            assert!(
                !is_natively_decodable(&song(Some(s), Some("audio/mpeg"))),
                "{s}"
            );
        }
    }

    #[test]
    fn content_type_used_when_suffix_missing() {
        assert!(is_natively_decodable(&song(None, Some("audio/flac"))));
        assert!(is_natively_decodable(&song(
            Some(""),
            Some("audio/mpeg; charset=x")
        )));
        assert!(!is_natively_decodable(&song(None, Some("audio/x-ms-wma"))));
        assert!(!is_natively_decodable(&song(None, Some("audio/opus"))));
    }

    #[test]
    fn unknown_metadata_tries_original() {
        assert!(is_natively_decodable(&song(None, None)));
    }
}
