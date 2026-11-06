//! Playlist `.m3u` files written next to synced music.

use std::fs;
use std::io;
use std::path::{Component, Path, PathBuf};

use dapper_domain::{DeviceSettings, Playlist, Song};

/// M3U text for `songs` (each paired with its device path) as seen from
/// `playlist_dir`. Entries use forward slashes: the target DAPs are often
/// Android-based regardless of the host OS.
pub fn render_m3u<'a>(playlist_dir: &Path, songs: impl IntoIterator<Item = (&'a Song, &'a Path)>) -> String {
    let mut buf = String::from("#EXTM3U\n");
    for (song, song_path) in songs {
        let rel = relative(song_path, playlist_dir).replace('\\', "/");
        let duration = song.duration.unwrap_or(-1);
        let artist = song.artist.as_deref().unwrap_or("");
        buf.push_str(&format!("#EXTINF:{duration},"));
        if !artist.is_empty() {
            buf.push_str(artist);
            buf.push_str(" - ");
        }
        buf.push_str(&song.title);
        buf.push('\n');
        buf.push_str(&rel);
        buf.push('\n');
    }
    buf
}

/// Writes the playlist's `.m3u` listing only the songs already present on
/// the device. Writes nothing (returns `false`) when none are. Blocking.
pub fn write_playlist_m3u(playlist: &Playlist, settings: &DeviceSettings) -> io::Result<bool> {
    let playlist_path = PathBuf::from(dapper_paths::build_playlist_path(playlist, settings));
    let playlist_dir = playlist_path.parent().unwrap_or(Path::new("")).to_path_buf();
    let present: Vec<(&Song, PathBuf)> = playlist
        .songs
        .iter()
        .map(|s| (s, PathBuf::from(dapper_paths::build_song_path(s, settings))))
        .filter(|(_, p)| p.is_file())
        .collect();
    if present.is_empty() {
        return Ok(false);
    }
    let text = render_m3u(&playlist_dir, present.iter().map(|(s, p)| (*s, p.as_path())));
    fs::create_dir_all(&playlist_dir)?;
    fs::write(&playlist_path, text)?;
    dapper_platform::remove_macos_sidecar(&playlist_path);
    Ok(true)
}

pub fn playlist_exists_on_device(playlist: &Playlist, settings: &DeviceSettings) -> bool {
    Path::new(&dapper_paths::build_playlist_path(playlist, settings)).is_file()
}

fn normalise(path: &Path) -> Vec<Component<'_>> {
    let mut out: Vec<Component> = Vec::new();
    for c in path.components() {
        match c {
            Component::CurDir => {}
            Component::ParentDir if matches!(out.last(), Some(Component::Normal(_))) => {
                out.pop();
            }
            c => out.push(c),
        }
    }
    out
}

fn same_component(a: &Component, b: &Component) -> bool {
    if cfg!(windows) {
        a.as_os_str().to_string_lossy().eq_ignore_ascii_case(&b.as_os_str().to_string_lossy())
    } else {
        a == b
    }
}

/// Dart `p.relative(path, from: from)` for the absolute, separator-only
/// paths used on devices. Differing roots return `path` unchanged.
fn relative(path: &Path, from: &Path) -> String {
    let p = normalise(path);
    let f = normalise(from);
    let is_root = |c: &Component| matches!(c, Component::Prefix(_) | Component::RootDir);
    let p_root: Vec<_> = p.iter().take_while(|c| is_root(c)).collect();
    let f_root: Vec<_> = f.iter().take_while(|c| is_root(c)).collect();
    if p_root.len() != f_root.len() || !p_root.iter().zip(&f_root).all(|(a, b)| same_component(a, b)) {
        return path.to_string_lossy().into_owned();
    }
    let common = p.iter().zip(&f).take_while(|(a, b)| same_component(a, b)).count();
    let parts: Vec<String> = std::iter::repeat_n("..".to_owned(), f.len() - common)
        .chain(p[common..].iter().map(|c| c.as_os_str().to_string_lossy().into_owned()))
        .collect();
    if parts.is_empty() { ".".to_owned() } else { parts.join(std::path::MAIN_SEPARATOR_STR) }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn song(id: &str, title: &str, artist: Option<&str>, duration: Option<i64>) -> Song {
        Song {
            id: id.into(),
            title: title.into(),
            artist: artist.map(Into::into),
            duration,
            ..Default::default()
        }
    }

    #[cfg(unix)]
    #[test]
    fn relative_paths() {
        assert_eq!(relative(Path::new("/d/Music/A/B/1.flac"), Path::new("/d/Playlists")), "../Music/A/B/1.flac");
        assert_eq!(relative(Path::new("/d/Playlists/x.flac"), Path::new("/d/Playlists/")), "x.flac");
        assert_eq!(relative(Path::new("/d/a/./b/../c.mp3"), Path::new("/d/p/q")), "../../a/c.mp3");
        assert_eq!(relative(Path::new("/d"), Path::new("/d")), ".");
    }

    #[cfg(unix)]
    #[test]
    fn renders_extinf_lines() {
        let a = song("1", "One", Some("Art"), Some(200));
        let b = song("2", "Two", None, None);
        let c = song("3", "Three", Some(""), Some(5));
        let pa = PathBuf::from("/d/Music/Art/Alb/01 One.flac");
        let pb = PathBuf::from("/d/Music/Unknown Artist/Alb/02 Two.mp3");
        let pc = PathBuf::from("/d/Music/x/3.mp3");
        let text = render_m3u(Path::new("/d/Playlists"), [(&a, pa.as_path()), (&b, pb.as_path()), (&c, pc.as_path())]);
        assert_eq!(
            text,
            "#EXTM3U\n#EXTINF:200,Art - One\n../Music/Art/Alb/01 One.flac\n\
             #EXTINF:-1,Two\n../Music/Unknown Artist/Alb/02 Two.mp3\n\
             #EXTINF:5,Three\n../Music/x/3.mp3\n"
        );
    }

    #[test]
    fn writes_only_present_songs_and_skips_empty() {
        let dir = tempfile::tempdir().unwrap();
        let settings = DeviceSettings::new(dir.path().to_string_lossy());
        let present = Song { album: Some("Alb".into()), album_artist: Some("Art".into()), ..song("1", "One", Some("Art"), Some(10)) };
        let missing = Song { album: Some("Alb".into()), ..song("2", "Two", Some("Art"), Some(20)) };
        let playlist = Playlist { id: "p".into(), name: "Mix/1".into(), songs: vec![present.clone(), missing], ..Default::default() };

        assert!(!write_playlist_m3u(&playlist, &settings).unwrap());
        assert!(!playlist_exists_on_device(&playlist, &settings));

        let song_path = PathBuf::from(dapper_paths::build_song_path(&present, &settings));
        fs::create_dir_all(song_path.parent().unwrap()).unwrap();
        fs::write(&song_path, b"x").unwrap();

        assert!(write_playlist_m3u(&playlist, &settings).unwrap());
        assert!(playlist_exists_on_device(&playlist, &settings));
        let written = fs::read_to_string(dapper_paths::build_playlist_path(&playlist, &settings)).unwrap();
        let rel = song_path.strip_prefix(dir.path()).unwrap().to_string_lossy().replace('\\', "/");
        assert_eq!(written, format!("#EXTM3U\n#EXTINF:10,Art - One\n../{rel}\n"));
    }
}
