//! The subset of Dart's `package:path` used for device paths, in both styles.
//! Dart builds paths with the host OS style, so [Style::NATIVE] is what
//! production code uses; the other style exists for tests.

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Style {
    Posix,
    Windows,
}

impl Style {
    #[cfg(windows)]
    pub const NATIVE: Style = Style::Windows;
    #[cfg(not(windows))]
    pub const NATIVE: Style = Style::Posix;

    fn separator(self) -> char {
        match self {
            Style::Posix => '/',
            Style::Windows => '\\',
        }
    }

    fn is_separator(self, c: char) -> bool {
        match self {
            Style::Posix => c == '/',
            Style::Windows => c == '/' || c == '\\',
        }
    }

    /// Byte length of the root prefix (`/`, `C:\`, `\\server\share`), 0 if relative.
    fn root_length(self, path: &str) -> usize {
        let b = path.as_bytes();
        match self {
            Style::Posix => usize::from(b.first() == Some(&b'/')),
            Style::Windows => {
                if b.is_empty() {
                    return 0;
                }
                let sep = |c: u8| c == b'/' || c == b'\\';
                if sep(b[0]) {
                    if b.len() < 2 || b[1] != b'\\' {
                        return 1;
                    }
                    // UNC: \\server\share
                    let Some(i) = path[2..].find('\\').map(|i| i + 2) else { return path.len() };
                    return path[i + 1..].find('\\').map_or(path.len(), |j| i + 1 + j);
                }
                if b.len() < 3 || !b[0].is_ascii_alphabetic() || b[1] != b':' || !sep(b[2]) {
                    return 0;
                }
                3
            }
        }
    }

    fn is_root_relative(self, path: &str) -> bool {
        self.root_length(path) == 1
    }

    fn needs_separator(self, path: &str) -> bool {
        path.chars().last().is_some_and(|c| !self.is_separator(c))
    }

    /// `p.joinAll`.
    pub fn join_all<'a>(self, parts: impl IntoIterator<Item = &'a str>) -> String {
        let mut buf = String::new();
        let mut needs_sep = false;
        let mut absolute_not_root_relative = false;
        for part in parts.into_iter().filter(|p| !p.is_empty()) {
            if self.is_root_relative(part) && absolute_not_root_relative {
                // Windows `\foo` joined onto `C:\bar` keeps the drive.
                let root = buf[..self.root_length(&buf)].to_string();
                buf = root;
                if self.needs_separator(&buf) {
                    buf.push(self.separator());
                }
                buf.push_str(part.trim_start_matches(|c| self.is_separator(c)));
            } else if self.root_length(part) > 0 {
                absolute_not_root_relative = !self.is_root_relative(part);
                buf.clear();
                buf.push_str(part);
            } else {
                if !part.starts_with(|c| self.is_separator(c)) && needs_sep {
                    buf.push(self.separator());
                }
                buf.push_str(part);
            }
            needs_sep = self.needs_separator(part);
        }
        buf
    }

    /// `p.basename`.
    pub fn basename(self, path: &str) -> String {
        let root = self.root_length(path);
        let trimmed = path.trim_end_matches(|c| self.is_separator(c));
        if trimmed.len() <= root {
            // Only a root (or nothing) remains.
            return if root > 0 { path[..root].to_string() } else { trimmed.to_string() };
        }
        let start = trimmed.rfind(|c| self.is_separator(c)).map_or(0, |i| i + 1).max(root);
        trimmed[start..].to_string()
    }

    /// `p.basenameWithoutExtension`.
    pub fn basename_without_extension(self, path: &str) -> String {
        let base = self.basename(path);
        match base.rfind('.') {
            Some(i) if i > 0 && base != ".." => base[..i].to_string(),
            _ => base,
        }
    }
    /// `p.split`.
    pub fn split(self, path: &str) -> Vec<String> {
        let root = self.root_length(path);
        let mut out = Vec::new();
        if root > 0 {
            out.push(path[..root].to_string());
        }
        out.extend(path[root..].split(|c| self.is_separator(c)).filter(|s| !s.is_empty()).map(String::from));
        out
    }

    /// `DeviceSettings.resolvedMusicRoot` evaluated in this style.
    pub fn resolved_music_root(self, device_path: &str, music_root_folder: &str) -> String {
        let trimmed = crate::safe_filename::dart_trim(music_root_folder);
        if trimmed.is_empty() {
            return device_path.to_string();
        }
        let parts = self.split(&trimmed.replace('\\', "/"));
        let parts: Vec<&str> = parts.iter().map(String::as_str).filter(|s| *s != ".").collect();
        if parts.is_empty() {
            return device_path.to_string();
        }
        self.join_all(std::iter::once(device_path).chain(parts))
    }
}

pub fn join_all<'a>(parts: impl IntoIterator<Item = &'a str>) -> String {
    Style::NATIVE.join_all(parts)
}

pub fn join(a: &str, b: &str) -> String {
    Style::NATIVE.join_all([a, b])
}

pub fn basename(path: &str) -> String {
    Style::NATIVE.basename(path)
}

pub fn basename_without_extension(path: &str) -> String {
    Style::NATIVE.basename_without_extension(path)
}

#[cfg(test)]
mod tests {
    use super::Style::*;

    #[test]
    fn join_posix() {
        assert_eq!(Posix.join_all(["/a", "b", "c.mp3"]), "/a/b/c.mp3");
        assert_eq!(Posix.join_all(["/a/", "b"]), "/a/b");
        assert_eq!(Posix.join_all(["/a", "", "b"]), "/a/b");
        assert_eq!(Posix.join_all(["/a", "/b"]), "/b");
        assert_eq!(Posix.join_all(["a", "b\\c"]), "a/b\\c");
    }

    #[test]
    fn join_windows() {
        assert_eq!(Windows.join_all(["E:\\", "Music", "a.mp3"]), "E:\\Music\\a.mp3");
        assert_eq!(Windows.join_all(["E:\\x", "Playlists/sub"]), "E:\\x\\Playlists/sub");
        assert_eq!(Windows.join_all(["E:\\x", "\\y"]), "E:\\y");
        assert_eq!(Windows.join_all(["E:\\x", "F:\\y"]), "F:\\y");
    }

    #[test]
    fn basenames() {
        assert_eq!(Posix.basename_without_extension("a/b/01 - T.flac"), "01 - T");
        assert_eq!(Posix.basename_without_extension("a/.hidden"), ".hidden");
        assert_eq!(Posix.basename_without_extension("a/b.c.d"), "b.c");
        assert_eq!(Posix.basename("a/b/"), "b");
        assert_eq!(Posix.basename("/"), "/");
        assert_eq!(Posix.basename_without_extension("a\\b.mp3"), "a\\b");
        assert_eq!(Windows.basename_without_extension("a\\b.mp3"), "b");
    }
}
