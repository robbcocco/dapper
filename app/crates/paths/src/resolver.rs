use std::sync::LazyLock;

use dapper_domain::{DeviceSettings, FilenameFormat, FolderStructure, Playlist, Song};
use regex::{Captures, Regex};

use crate::dart_path::Style;
use crate::safe_filename::{MAX_PATH_COMPONENT, dart_trim, to_safe_filename, trunc, trunc_utf16, utf16_len};

/// Computes the absolute target path for a song on the device.
pub fn build_song_path(song: &Song, settings: &DeviceSettings) -> String {
    build_song_path_styled(song, settings, Style::NATIVE, false).unwrap_or_default()
}

/// `strict`: see [render].
pub(crate) fn build_song_path_styled(song: &Song, settings: &DeviceSettings, style: Style, strict: bool) -> Option<String> {
    // When transcoding, the extension follows the target format rather than
    // the source suffix (a FLAC sent as MP3 must be named .mp3).
    let ext = settings.transcode_format.file_extension().or(song.suffix.as_deref()).unwrap_or("mp3");
    let filename = compose_filename(song, settings, &format!(".{ext}"), strict)?;
    let root = style.resolved_music_root(&settings.device_path, &settings.music_root_folder);
    let artist = || trunc(&to_safe_filename(song.album_artist.as_deref().or(song.artist.as_deref()).unwrap_or("Unknown Artist")));
    Some(match settings.folder_structure {
        FolderStructure::ArtistAlbum | FolderStructure::ArtistAlbumYear => {
            let album = album_folder_name(song.album.as_deref().unwrap_or("Unknown Album"), song.year, settings);
            style.join_all([root.as_str(), &artist(), &album, &filename])
        }
        FolderStructure::ArtistOnly => style.join_all([root.as_str(), &artist(), &filename]),
        FolderStructure::Flat => style.join_all([root.as_str(), &filename]),
        FolderStructure::Custom => {
            let parts = render_folder_template(&settings.custom_folder_template, song, strict)?;
            style.join_all(std::iter::once(root.as_str()).chain(parts.iter().map(String::as_str)).chain([filename.as_str()]))
        }
    })
}

fn album_folder_name(album: &str, year: Option<i32>, settings: &DeviceSettings) -> String {
    let raw = trunc(&to_safe_filename(album));
    let force_year = settings.folder_structure == FolderStructure::ArtistAlbumYear;
    match year {
        Some(y) if (force_year || settings.include_year) && y > 0 => trunc(&format!("{y} - {raw}")),
        _ => raw,
    }
}

/// Splits the template on `/`, renders, sanitises and truncates each
/// component. Empty segments are dropped BEFORE rendering — an empty segment
/// would otherwise fall through to the title fallback and inject the track
/// title as a folder name.
fn render_folder_template(template: &str, song: &Song, strict: bool) -> Option<Vec<String>> {
    if dart_trim(template).is_empty() {
        return Some(Vec::new());
    }
    let mut out = Vec::new();
    for seg in template.replace('\\', "/").split('/').filter(|seg| !dart_trim(seg).is_empty()) {
        let s = trunc(&to_safe_filename(&render(seg, song, strict)?));
        if !s.is_empty() {
            out.push(s);
        }
    }
    Some(out)
}

/// Validates a user-entered folder template. Returns `None` when usable.
pub fn validate_folder_template(template: &str) -> Option<&'static str> {
    let t = dart_trim(template);
    if t.is_empty() {
        return Some("Template cannot be empty");
    }
    if !t.contains("{album}") && !t.contains("{artist}") {
        return Some("Template must include {album} or {artist}");
    }
    if t.contains("{title}") {
        return Some("Folder template cannot include {title}");
    }
    None
}

fn compose_filename(song: &Song, settings: &DeviceSettings, dot_ext: &str, strict: bool) -> Option<String> {
    let ext_len = utf16_len(dot_ext);
    if settings.filename_format == FilenameFormat::Custom {
        let safe = to_safe_filename(&render(&settings.custom_filename_template, song, strict)?);
        let max_base = clamp_component(MAX_PATH_COMPONENT as i64 - ext_len as i64);
        return Some(format!("{}{dot_ext}", trunc_utf16(&safe, max_base)));
    }
    let padded = |n: i32| dart_pad_left(&n.to_string(), 2);
    let prefix_part = match (settings.filename_format, song.track) {
        (FilenameFormat::Track, Some(t)) => format!("{} ", padded(t)),
        (FilenameFormat::DiscTrack, Some(t)) => format!("{}-{} - ", song.disc_number.unwrap_or(1), padded(t)),
        _ => String::new(),
    };
    let max_title = clamp_component(MAX_PATH_COMPONENT as i64 - utf16_len(&prefix_part) as i64 - ext_len as i64);
    Some(format!("{prefix_part}{}{dot_ext}", trunc_utf16(&to_safe_filename(&song.title), max_title)))
}

fn clamp_component(n: i64) -> usize {
    n.clamp(1, MAX_PATH_COMPONENT as i64) as usize
}

/// Dart `String.padLeft(width, '0')` (counts UTF-16 units; `-5` → `0-5`).
fn dart_pad_left(s: &str, width: usize) -> String {
    let len = utf16_len(s);
    if len >= width { s.to_string() } else { "0".repeat(width - len) + s }
}

// Dart `\w`/`\d` are ASCII-only.
static TEMPLATE_TOKEN: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"\{([A-Za-z0-9_]+)(?::([0-9]+))?\}").unwrap());

/// Renders `template` with tokens substituted from `song`. Unknown tokens stay
/// verbatim so a typo is visible in the preview. NOT sanitised.
///
/// Tokens: `{track}`, `{track:N}`, `{disc}`, `{disc:N}`, `{year}`, `{year:N}`,
/// `{title}`, `{artist}` (falls back to album artist), `{albumArtist}` (falls
/// back to artist), `{album}`.
pub fn render_filename_template(template: &str, song: &Song) -> String {
    render(template, song, false).unwrap_or_default()
}

/// `None` where Dart throws: a `{tok:N}` width beyond `int.parse` range on a
/// numeric value. Production (`strict == false`) leaves such values unpadded.
pub(crate) fn render(template: &str, song: &Song, strict: bool) -> Option<String> {
    if template.is_empty() {
        return Some(song.title.clone());
    }
    let mut threw = false;
    let out = TEMPLATE_TOKEN
        .replace_all(template, |c: &Captures| {
            let Some(raw) = token_value(&c[1], song) else { return c[0].to_string() };
            if let Some(width) = c.get(2)
                && let Some(n) = dart_int_try_parse(&raw)
            {
                // Absurd widths would exhaust memory (Dart throws OutOfMemoryError).
                match width.as_str().parse::<i64>() {
                    Ok(w) if w <= 1 << 20 => return dart_pad_left(&n.to_string(), w as usize),
                    _ => threw = true,
                }
            }
            raw
        })
        .into_owned();
    (!(strict && threw)).then_some(out)
}

fn token_value(key: &str, song: &Song) -> Option<String> {
    match key {
        "track" => song.track.map(|t| t.to_string()),
        "disc" => Some(song.disc_number.unwrap_or(1).to_string()),
        "year" => song.year.map(|y| y.to_string()),
        "title" => Some(song.title.clone()),
        "artist" => song.artist.clone().or_else(|| song.album_artist.clone()),
        "albumArtist" => song.album_artist.clone().or_else(|| song.artist.clone()),
        "album" => song.album.clone(),
        _ => None,
    }
}

/// Dart `int.tryParse` (no radix): surrounding whitespace, optional sign,
/// decimal or `0x` hex.
fn dart_int_try_parse(s: &str) -> Option<i64> {
    let t = dart_trim(s);
    let (neg, body) = match t.as_bytes().first() {
        Some(b'-') => (true, &t[1..]),
        Some(b'+') => (false, &t[1..]),
        _ => (false, t),
    };
    let (digits, radix) = match body.get(..2) {
        Some("0x" | "0X") => (&body[2..], 16),
        _ => (body, 10),
    };
    if digits.is_empty() || !digits.chars().all(|c| c.is_digit(radix)) {
        return None;
    }
    let mag = i128::from_str_radix(digits, radix).ok()?;
    i64::try_from(if neg { -mag } else { mag }).ok()
}

/// Validates a user-entered filename template. Returns `None` when usable.
pub fn validate_filename_template(template: &str) -> Option<&'static str> {
    let t = dart_trim(template);
    if t.is_empty() {
        return Some("Template cannot be empty");
    }
    if !t.contains("{title}") && !t.contains("{track") {
        return Some("Template must include {title} or {track} to avoid collisions");
    }
    if t.contains('/') || t.contains('\\') {
        return Some("Template cannot contain path separators");
    }
    None
}

/// Expected directory for an album on the device; `None` for structures
/// without a distinct per-album folder (flat, artistOnly). For custom
/// templates this is the rendered template, matching what [build_song_path]
/// renders for any song of the album.
pub fn build_album_folder(album_artist: Option<&str>, album_name: &str, year: Option<i32>, settings: &DeviceSettings) -> Option<String> {
    build_album_folder_styled(album_artist, album_name, year, settings, Style::NATIVE, false).flatten()
}

/// Outer `None` = Dart threw (strict mode only, see [render]).
pub(crate) fn build_album_folder_styled(
    album_artist: Option<&str>,
    album_name: &str,
    year: Option<i32>,
    settings: &DeviceSettings,
    style: Style,
    strict: bool,
) -> Option<Option<String>> {
    let root = style.resolved_music_root(&settings.device_path, &settings.music_root_folder);
    Some(match settings.folder_structure {
        FolderStructure::Flat | FolderStructure::ArtistOnly => None,
        FolderStructure::Custom => {
            let synthetic = Song {
                id: "__album__".into(),
                album: Some(album_name.into()),
                artist: album_artist.map(Into::into),
                album_artist: album_artist.map(Into::into),
                year,
                ..Song::default()
            };
            let parts = render_folder_template(&settings.custom_folder_template, &synthetic, strict)?;
            (!parts.is_empty()).then(|| style.join_all(std::iter::once(root.as_str()).chain(parts.iter().map(String::as_str))))
        }
        FolderStructure::ArtistAlbum | FolderStructure::ArtistAlbumYear => {
            let artist = trunc(&to_safe_filename(album_artist.unwrap_or("Unknown Artist")));
            Some(style.join_all([root.as_str(), &artist, &album_folder_name(album_name, year, settings)]))
        }
    })
}

/// `<music root>/<safe artist name>`: the artist directory used by the
/// artist-level sync scan and the artist-folder existence check.
pub fn artist_folder(settings: &DeviceSettings, artist_name: &str) -> String {
    let s = Style::NATIVE;
    s.join_all([s.resolved_music_root(&settings.device_path, &settings.music_root_folder).as_str(), &to_safe_filename(artist_name)])
}

/// Path of a playlist's M3U file on the device.
pub fn build_playlist_path(playlist: &Playlist, settings: &DeviceSettings) -> String {
    build_playlist_path_styled(playlist, settings, Style::NATIVE)
}

pub(crate) fn build_playlist_path_styled(playlist: &Playlist, settings: &DeviceSettings, style: Style) -> String {
    let dir = style.join_all([settings.device_path.as_str(), &settings.playlist_folder]);
    style.join_all([dir.as_str(), &format!("{}.m3u", to_safe_filename(&playlist.name))])
}

/// Matches a zip entry's archive path against the expected songs.
///
/// A track number appearing as any digit run in the basename is
/// authoritative; title overlap only tie-breaks or handles number-less
/// filenames ("Interlude II" must not capture the "Interlude III" file).
pub fn match_zip_entry<'a>(entry_path: &str, expected: &'a [Song]) -> Option<&'a Song> {
    match_zip_entry_styled(entry_path, expected, Style::NATIVE)
}

pub(crate) fn match_zip_entry_styled<'a>(entry_path: &str, expected: &'a [Song], style: Style) -> Option<&'a Song> {
    if expected.is_empty() {
        return None;
    }
    let basename = style.basename_without_extension(entry_path);
    let norm_full = normalise_title(&basename);
    if norm_full.is_empty() {
        return None;
    }
    let tokens = numeric_tokens(&basename);
    let by_track: Vec<&Song> = expected.iter().filter(|s| s.track.is_some_and(|t| t > 0 && tokens.contains(&i64::from(t)))).collect();
    match by_track.len() {
        1 => Some(by_track[0]),
        0 => best_title_overlap(expected.iter(), &norm_full),
        _ => {
            // Multi-disc albums or coincidental hits: narrow by disc when the
            // filename references exactly one, then title overlap.
            let by_disc: Vec<&Song> = by_track
                .iter()
                .copied()
                .filter(|s| {
                    let d = s.disc_number.unwrap_or(1);
                    d > 0 && tokens.contains(&i64::from(d))
                })
                .collect();
            let pool = if by_disc.len() == 1 { by_disc } else { by_track };
            best_title_overlap(pool.into_iter(), &norm_full)
        }
    }
}

fn best_title_overlap<'a>(candidates: impl Iterator<Item = &'a Song>, norm_full: &str) -> Option<&'a Song> {
    let mut best = None;
    let mut best_score = 0;
    let full_len = utf16_len(norm_full);
    for s in candidates {
        let norm = normalise_title(&s.title);
        if norm.is_empty() {
            continue;
        }
        let score = if norm == norm_full {
            return Some(s);
        } else if norm_full.contains(&norm) {
            utf16_len(&norm)
        } else if norm.contains(norm_full) {
            // Filename shorter than the title — half credit so tiny basenames
            // don't randomly win.
            full_len / 2
        } else {
            continue;
        };
        if score > best_score {
            best_score = score;
            best = Some(s);
        }
    }
    best
}

fn normalise_title(s: &str) -> String {
    // Dart's toLowerCase uses simple (1:1) case mapping; the only char whose
    // full mapping expands is U+0130 'İ', whose simple lowercase is 'i' — the
    // first char of the full mapping.
    s.chars()
        .filter_map(|c| c.to_lowercase().next())
        .filter(|&c| c.is_ascii_digit() || c.is_ascii_lowercase() || c as u32 > 0x7f)
        .collect()
}

/// Every ASCII digit run in `s`, parsed with Dart's wrapping int arithmetic.
fn numeric_tokens(s: &str) -> Vec<i64> {
    let mut out = Vec::new();
    let mut cur: Option<i64> = None;
    for b in s.bytes() {
        if b.is_ascii_digit() {
            cur = Some(cur.unwrap_or(0).wrapping_mul(10).wrapping_add(i64::from(b - b'0')));
        } else if let Some(n) = cur.take() {
            out.push(n);
        }
    }
    out.extend(cur);
    out
}

/// Expected download size: the song's size, or for transcodes with a bitrate
/// cap, kbps × seconds × 1000 / 8.
pub fn estimate_total_bytes(song: &Song, settings: &DeviceSettings) -> i64 {
    let size = song.size.unwrap_or(0);
    if !settings.is_transcoding() {
        return size;
    }
    match (settings.transcode_max_bit_rate, song.duration) {
        (Some(cap), Some(d)) if cap > 0 && d > 0 => cap.wrapping_mul(d).wrapping_mul(1000) / 8,
        _ => size,
    }
}
