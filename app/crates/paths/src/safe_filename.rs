/// FAT32 limit: 255 UTF-16 code units per path component.
pub const MAX_PATH_COMPONENT: usize = 255;

/// Dart `s.length > max ? s.substring(0, max) : s` over UTF-16 code units.
/// When the cut splits a surrogate pair Dart keeps a lone high surrogate, which
/// `dart:io` encodes as U+FFFD; we produce that same character.
pub fn trunc_utf16(s: &str, max: usize) -> String {
    let mut units = 0;
    for (i, c) in s.char_indices() {
        let w = c.len_utf16();
        if units + w > max {
            let mut out = s[..i].to_string();
            if units < max {
                out.push('\u{FFFD}');
            }
            return out;
        }
        units += w;
    }
    s.to_string()
}

pub(crate) fn trunc(s: &str) -> String {
    trunc_utf16(s, MAX_PATH_COMPONENT)
}

/// Dart `String.length`.
pub fn utf16_len(s: &str) -> usize {
    s.chars().map(char::len_utf16).sum()
}

/// Dart `String.trim()` whitespace set.
pub(crate) fn dart_trim(s: &str) -> &str {
    s.trim_matches(|c: char| {
        matches!(c, '\t'..='\r' | ' ' | '\u{85}' | '\u{A0}' | '\u{1680}' | '\u{2000}'..='\u{200A}'
            | '\u{2028}' | '\u{2029}' | '\u{202F}' | '\u{205F}' | '\u{3000}' | '\u{FEFF}')
    })
}

pub trait ToSafeFilename {
    fn to_safe_filename(&self) -> String;
}

impl ToSafeFilename for str {
    fn to_safe_filename(&self) -> String {
        to_safe_filename(self)
    }
}

pub fn to_safe_filename(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    for c in s.chars() {
        match c {
            '…' => out.push_str("..."),
            '–' | '—' | '/' | '\\' => out.push('-'),
            ':' | '*' | '?' | '"' | '<' | '>' | '|' | '\x00'..='\x1F' | '\x7F' => {}
            ' ' if out.ends_with(' ') => {}
            _ => out.push(c),
        }
    }
    let trimmed = out.trim_matches(['.', ' ']);
    if trimmed.is_empty() {
        return "_".into();
    }
    if is_windows_reserved(trimmed) {
        return format!("_{trimmed}");
    }
    trimmed.to_string()
}

// Windows blocks these as filenames even with an extension.
fn is_windows_reserved(s: &str) -> bool {
    let l = s.to_ascii_lowercase();
    match l.as_bytes() {
        b"con" | b"prn" | b"aux" | b"nul" => true,
        [a, b, c, d] => matches!(&[*a, *b, *c], b"com" | b"lpt") && (b'1'..=b'9').contains(d),
        _ => false,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn plain() {
        assert_eq!("Hello World".to_safe_filename(), "Hello World");
    }

    #[test]
    fn ellipsis_and_dashes() {
        assert_eq!(to_safe_filename("Foo…Bar"), "Foo...Bar");
        assert_eq!(to_safe_filename("Foo–Bar"), "Foo-Bar");
        assert_eq!(to_safe_filename("Foo—Bar"), "Foo-Bar");
    }

    #[test]
    fn separators() {
        assert_eq!(to_safe_filename("a/b/c"), "a-b-c");
        assert_eq!(to_safe_filename(r"a\b\c"), "a-b-c");
        assert_eq!(to_safe_filename("../etc/passwd"), "-etc-passwd");
    }

    #[test]
    fn fat32_illegal() {
        assert_eq!(to_safe_filename("foo:bar*baz?qux\"x<y>z|end"), "foobarbazquxxyzend");
    }

    #[test]
    fn control_chars() {
        assert_eq!(to_safe_filename("foo\x00bar\x1Fbaz\x7Fend"), "foobarbazend");
    }

    #[test]
    fn spaces() {
        assert_eq!(to_safe_filename("a   b    c"), "a b c");
        // Collapsing happens after drops, as in Dart's sequential replaces.
        assert_eq!(to_safe_filename("a :  b"), "a b");
    }

    #[test]
    fn strip_dots_spaces() {
        assert_eq!(to_safe_filename("   .hidden   "), "hidden");
        assert_eq!(to_safe_filename("trailing... "), "trailing");
        assert_eq!(to_safe_filename("..dotdot"), "dotdot");
    }

    #[test]
    fn empty_sentinel() {
        assert_eq!(to_safe_filename("..."), "_");
        assert_eq!(to_safe_filename("::::"), "_");
        assert_eq!(to_safe_filename(""), "_");
    }

    #[test]
    fn unicode() {
        assert_eq!(to_safe_filename("Sigur Rós"), "Sigur Rós");
        assert_eq!(to_safe_filename("Mötley Crüe"), "Mötley Crüe");
    }

    #[test]
    fn long_untruncated() {
        assert_eq!(to_safe_filename(&"a".repeat(500)).len(), 500);
    }

    #[test]
    fn reserved() {
        for (i, o) in [("con", "_con"), ("CON", "_CON"), ("PRN", "_PRN"), ("aux", "_aux"), ("NUL", "_NUL"), ("com1", "_com1"), ("LPT9", "_LPT9")] {
            assert_eq!(to_safe_filename(i), o);
        }
        for s in ["Conrad", "COM10", "AUXILIARY", "com0"] {
            assert_eq!(to_safe_filename(s), s);
        }
    }

    #[test]
    fn truncation() {
        assert_eq!(trunc_utf16("abc", 2), "ab");
        assert_eq!(trunc_utf16("abc", 3), "abc");
        assert_eq!(trunc_utf16("a😀b", 2), "a\u{FFFD}");
        assert_eq!(trunc_utf16("a😀b", 3), "a😀");
        assert_eq!(utf16_len("a😀"), 3);
    }
}
