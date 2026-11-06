use dapper_domain::{DeviceSettings, FilenameFormat, FolderStructure, Song, TranscodeFormat};

use crate::dart_path::Style::{Posix, Windows};
use crate::resolver::{build_album_folder_styled, build_song_path_styled, match_zip_entry_styled};
use crate::*;

fn song() -> Song {
    Song {
        id: "s1".into(),
        title: "My Song".into(),
        album: Some("My Album".into()),
        artist: Some("My Artist".into()),
        suffix: Some("mp3".into()),
        track: Some(1),
        disc_number: Some(1),
        ..Song::default()
    }
}

fn settings() -> DeviceSettings {
    DeviceSettings::new("/dev")
}

fn path(s: &Song, st: &DeviceSettings) -> String {
    build_song_path_styled(s, st, Posix, true).unwrap()
}

fn segments(p: &str) -> Vec<String> {
    Posix.split(p)
}

fn base(p: &str) -> String {
    Posix.basename(p)
}

fn ext(p: &str) -> String {
    let b = base(p);
    b[b.rfind('.').unwrap()..].to_string()
}

mod song_path {
    use super::*;

    #[test]
    fn default_layout() {
        assert_eq!(path(&song(), &settings()), "/dev/My Artist/My Album/1-01 - My Song.mp3");
    }

    #[test]
    fn prefers_album_artist() {
        let s = Song { artist: Some("Track Artist".into()), album_artist: Some("Album Artist".into()), ..song() };
        assert!(segments(&path(&s, &settings())).contains(&"Album Artist".into()));
    }

    #[test]
    fn unknown_fallbacks() {
        let s = Song { artist: None, album: None, album_artist: None, ..song() };
        let segs = segments(&path(&s, &settings()));
        assert!(segs.contains(&"Unknown Artist".into()) && segs.contains(&"Unknown Album".into()));
    }

    #[test]
    fn year_folders() {
        let s = Song { year: Some(1973), album: Some("Dark Side of the Moon".into()), ..song() };
        let forced = DeviceSettings { folder_structure: FolderStructure::ArtistAlbumYear, ..settings() };
        let incl = DeviceSettings { include_year: true, ..settings() };
        for st in [forced, incl] {
            assert!(segments(&path(&s, &st)).contains(&"1973 - Dark Side of the Moon".into()));
        }
    }

    #[test]
    fn no_year_when_null_or_zero() {
        let st = DeviceSettings { folder_structure: FolderStructure::ArtistAlbumYear, ..settings() };
        for y in [None, Some(0)] {
            assert!(segments(&path(&Song { year: y, ..song() }, &st)).contains(&"My Album".into()));
        }
    }

    #[test]
    fn filename_formats() {
        let none = DeviceSettings { filename_format: FilenameFormat::None, ..settings() };
        let track = DeviceSettings { filename_format: FilenameFormat::Track, ..settings() };
        assert_eq!(base(&path(&song(), &none)), "My Song.mp3");
        assert_eq!(base(&path(&Song { track: Some(7), ..song() }, &track)), "07 My Song.mp3");
        assert_eq!(base(&path(&Song { track: Some(7), disc_number: Some(2), ..song() }, &settings())), "2-07 - My Song.mp3");
        assert_eq!(base(&path(&Song { track: Some(7), disc_number: None, ..song() }, &settings())), "1-07 - My Song.mp3");
        assert_eq!(base(&path(&Song { track: None, ..song() }, &track)), "My Song.mp3");
    }

    #[test]
    fn extensions() {
        let flac = Song { suffix: Some("flac".into()), ..song() };
        assert_eq!(ext(&path(&flac, &settings())), ".flac");
        assert_eq!(ext(&path(&Song { suffix: None, ..song() }, &settings())), ".mp3");
        for (f, e) in [
            (TranscodeFormat::Mp3, ".mp3"),
            (TranscodeFormat::Opus, ".opus"),
            (TranscodeFormat::Aac, ".m4a"),
            (TranscodeFormat::Original, ".flac"),
        ] {
            assert_eq!(ext(&path(&flac, &DeviceSettings { transcode_format: f, ..settings() })), e);
        }
    }

    #[test]
    fn artist_only_and_flat() {
        let p = path(&song(), &DeviceSettings { folder_structure: FolderStructure::ArtistOnly, ..settings() });
        assert!(!segments(&p).contains(&"My Album".into()));
        assert!(segments(&p).contains(&"My Artist".into()));
        let p = path(&song(), &DeviceSettings { folder_structure: FolderStructure::Flat, ..settings() });
        assert_eq!(p, "/dev/1-01 - My Song.mp3");
    }

    #[test]
    fn no_traversal() {
        let s = Song { album: Some("../escape".into()), artist: Some("a/b".into()), ..song() };
        let p = path(&s, &settings());
        assert_eq!(p, "/dev/a-b/-escape/1-01 - My Song.mp3");
        assert!(segments(&p).iter().all(|s| s != ".." && s != "."));
    }

    #[test]
    fn long_title_truncated() {
        let b = base(&path(&Song { title: "x".repeat(500), ..song() }, &settings()));
        assert_eq!(b.len(), 255);
        assert!(b.starts_with("1-01 - ") && b.ends_with(".mp3"));
    }

    #[test]
    fn windows_style() {
        let st = DeviceSettings { music_root_folder: "Music/FLAC".into(), ..DeviceSettings::new("E:\\") };
        assert_eq!(build_song_path_styled(&song(), &st, Windows, true).unwrap(), "E:\\Music\\FLAC\\My Artist\\My Album\\1-01 - My Song.mp3");
    }

    #[test]
    fn music_root() {
        let st = DeviceSettings { music_root_folder: "  Music//./FLAC  ".into(), ..settings() };
        assert_eq!(path(&song(), &st), "/dev/Music/FLAC/My Artist/My Album/1-01 - My Song.mp3");
    }
}

mod album_folder {
    use super::*;

    fn folder(a: &str, b: &str, y: Option<i32>, st: &DeviceSettings) -> Option<String> {
        build_album_folder_styled(Some(a), b, y, st, Posix, true).unwrap()
    }

    #[test]
    fn none_for_flat_artist_only() {
        for fs in [FolderStructure::Flat, FolderStructure::ArtistOnly] {
            assert_eq!(folder("A", "B", None, &DeviceSettings { folder_structure: fs, ..settings() }), None);
        }
    }

    #[test]
    fn artist_album() {
        assert_eq!(folder("A", "B", None, &settings()).as_deref(), Some("/dev/A/B"));
        let st = DeviceSettings { folder_structure: FolderStructure::ArtistAlbumYear, ..settings() };
        assert_eq!(folder("A", "B", Some(1999), &st).as_deref(), Some("/dev/A/1999 - B"));
    }

    #[test]
    fn custom_matches_song_path() {
        let st = DeviceSettings { folder_structure: FolderStructure::Custom, custom_folder_template: "{albumArtist}/{year} - {album}".into(), ..settings() };
        let s = Song { album_artist: Some("A".into()), year: Some(2001), ..song() };
        let f = build_album_folder_styled(Some("A"), "My Album", Some(2001), &st, Posix, true).unwrap().unwrap();
        assert_eq!(f, "/dev/A/2001 - My Album");
        assert!(path(&s, &st).starts_with(&format!("{f}/")));
    }
}

mod template {
    use super::*;

    fn pf() -> Song {
        Song {
            id: "s".into(),
            title: "Astronomy Domine".into(),
            album: Some("The Piper at the Gates of Dawn".into()),
            artist: Some("Pink Floyd".into()),
            album_artist: Some("Pink Floyd".into()),
            track: Some(1),
            disc_number: Some(1),
            year: Some(1967),
            suffix: Some("flac".into()),
            ..Song::default()
        }
    }

    #[test]
    fn render() {
        assert_eq!(
            render_filename_template("{albumArtist} - {album} ({year}) - {disc}.{track:02} - {title}", &pf()),
            "Pink Floyd - The Piper at the Gates of Dawn (1967) - 1.01 - Astronomy Domine"
        );
        assert_eq!(render_filename_template("{track:02}", &Song { track: Some(3), ..pf() }), "03");
        assert_eq!(render_filename_template("{track:03}", &Song { track: Some(12), ..pf() }), "012");
        assert_eq!(render_filename_template("{disc:02}", &pf()), "01");
        assert_eq!(render_filename_template("{year:04}", &Song { year: Some(999), ..pf() }), "0999");
        assert_eq!(render_filename_template("{bogus} - {title}", &pf()), "{bogus} - Astronomy Domine");
        assert_eq!(render_filename_template("{artist}", &Song { artist: None, ..pf() }), "Pink Floyd");
        assert_eq!(render_filename_template("{albumArtist}", &Song { album_artist: None, ..pf() }), "Pink Floyd");
        assert_eq!(render_filename_template("{album} - {title}", &Song { album: None, ..pf() }), "{album} - Astronomy Domine");
        assert_eq!(render_filename_template("", &pf()), "Astronomy Domine");
        assert_eq!(render_filename_template("{title:02}", &Song { title: "X".into(), ..pf() }), "X");
        // Dart int.tryParse: whitespace, sign and hex are numeric.
        assert_eq!(render_filename_template("{title:3}", &Song { title: " 7 ".into(), ..pf() }), "007");
        assert_eq!(render_filename_template("{title:4}", &Song { title: "0x1F".into(), ..pf() }), "0031");
        assert_eq!(render_filename_template("{title:3}", &Song { title: "-5".into(), ..pf() }), "0-5");
    }

    #[test]
    fn validate_filename() {
        for t in ["", "   ", "{album}", "{artist} - {album}", "{title}/{track}", r"{title}\{track}"] {
            assert!(validate_filename_template(t).is_some(), "{t}");
        }
        for t in ["{title}", "{album} - {title}", "{track}", "{track:02}"] {
            assert_eq!(validate_filename_template(t), None, "{t}");
        }
    }

    #[test]
    fn validate_folder() {
        for t in ["", "  ", "{year}", "{album}/{title}"] {
            assert!(validate_folder_template(t).is_some(), "{t}");
        }
        for t in ["{albumArtist}/{album}", "{artist}"] {
            assert_eq!(validate_folder_template(t), None, "{t}");
        }
    }

    fn custom(folder: &str, ff: FilenameFormat, file_tpl: &str) -> DeviceSettings {
        DeviceSettings {
            folder_structure: if folder.is_empty() { FolderStructure::ArtistAlbum } else { FolderStructure::Custom },
            custom_folder_template: folder.into(),
            filename_format: ff,
            custom_filename_template: file_tpl.into(),
            ..DeviceSettings::new("/Volumes/USB")
        }
    }

    #[test]
    fn custom_paths() {
        assert_eq!(
            path(&pf(), &custom("{albumArtist}/{year} - {album}", FilenameFormat::DiscTrack, "")),
            "/Volumes/USB/Pink Floyd/1967 - The Piper at the Gates of Dawn/1-01 - Astronomy Domine.flac"
        );
        assert_eq!(
            path(&pf(), &custom("{albumArtist}//{album}", FilenameFormat::None, "")),
            "/Volumes/USB/Pink Floyd/The Piper at the Gates of Dawn/Astronomy Domine.flac"
        );
        assert_eq!(
            path(&pf(), &custom("", FilenameFormat::Custom, "{track:02} - {title}")),
            "/Volumes/USB/Pink Floyd/The Piper at the Gates of Dawn/01 - Astronomy Domine.flac"
        );
        let s = Song { title: "Side A / Side B".into(), ..pf() };
        assert!(path(&s, &custom("", FilenameFormat::Custom, "{title}")).ends_with("Side A - Side B.flac"));
    }
}

mod zip {
    use super::*;

    fn s(id: &str, title: &str, track: i32, disc: i32) -> Song {
        Song { id: id.into(), title: title.into(), track: Some(track), disc_number: Some(disc), album: Some("A".into()), artist: Some("X".into()), ..Song::default() }
    }

    fn m<'a>(entry: &str, list: &'a [Song]) -> Option<&'a str> {
        match_zip_entry_styled(entry, list, Posix).map(|s| s.id.as_str())
    }

    #[test]
    fn piper() {
        let e = [
            s("1", "Astronomy Domine", 1, 1),
            s("2", "Lucifer Sam", 2, 1),
            s("3", "Matilda Mother", 3, 1),
            s("4", "Flaming", 4, 1),
            s("5", "Pow R. Toc H.", 5, 1),
        ];
        assert_eq!(m("Pink Floyd/Piper at the Gates/02 - Lucifer Sam.flac", &e), Some("2"));
        assert_eq!(m("1-03 Matilda Mother.flac", &e), Some("3"));
        assert_eq!(m("04 Flaming.mp3", &e), Some("4"));
        assert_eq!(m("Astronomy Domine.flac", &e), Some("1"));
        assert_eq!(m("05 Pow R Toc H.flac", &e), Some("5"));
        assert_eq!(m("99 - Unknown Song.flac", &e), None);
        assert_eq!(m("01 - Foo.flac", &[]), None);
        assert_eq!(m("Lucifer Sam.flac", &e), Some("2"));
        assert_eq!(m("Artist/Album/03 - Matilda Mother.flac", &e), Some("3"));
        assert_eq!(m("alt-J - An Awesome Wave - 02 - Lucifer Sam.flac", &e), Some("2"));
    }

    #[test]
    fn multi_disc() {
        let e = [s("a", "Side A", 1, 1), s("b", "Side B", 1, 2)];
        assert_eq!(m("1-01 - Side A.flac", &e), Some("a"));
        assert_eq!(m("2-01 - Side B.flac", &e), Some("b"));
    }

    #[test]
    fn interludes_and_digits() {
        let e = [s("two", "Interlude II", 9, 1), s("three", "Interlude III", 11, 1)];
        assert_eq!(m("alt‐J - An Awesome Wave - 11 - Interlude III.flac", &e), Some("three"));
        let e = [s("studio", "Taro", 12, 1), s("live", "Taro (Live from the Africa Centre, 14.04.12)", 15, 1)];
        assert_eq!(m("alt‐J - An Awesome Wave - 15 - Taro (live from the Africa Centre 14.04.12).flac", &e), Some("live"));
        let e = [s("eleven", "Interlude", 11, 1), s("four", "Interlude III", 4, 1)];
        assert_eq!(m("Artist - Album - 11 - Interlude III.flac", &e), Some("eleven"));
        let e = [s("7", "Breezeblocks", 7, 1)];
        assert_eq!(m("alt‐J - An Awesome Wave - 07 - Breezeblocks.flac", &e), Some("7"));
    }
}

mod estimate {
    use super::*;

    fn s(size: Option<i64>, duration: Option<i64>) -> Song {
        Song { id: "s".into(), title: "T".into(), size, duration, ..Song::default() }
    }

    fn st(f: TranscodeFormat, cap: Option<i64>) -> DeviceSettings {
        DeviceSettings { transcode_format: f, transcode_max_bit_rate: cap, ..DeviceSettings::new("/dev") }
    }

    #[test]
    fn cases() {
        use TranscodeFormat::*;
        assert_eq!(estimate_total_bytes(&s(Some(8_000_000), Some(240)), &st(Original, None)), 8_000_000);
        assert_eq!(estimate_total_bytes(&s(None, Some(240)), &st(Original, None)), 0);
        assert_eq!(estimate_total_bytes(&s(Some(5_000_000), Some(240)), &st(Mp3, Some(128))), 3_840_000);
        assert_eq!(estimate_total_bytes(&s(Some(5_000_000), Some(240)), &st(Opus, Some(320))), 9_600_000);
        assert_eq!(estimate_total_bytes(&s(Some(4_000_000), None), &st(Mp3, Some(128))), 4_000_000);
        assert_eq!(estimate_total_bytes(&s(Some(4_000_000), Some(240)), &st(Mp3, Some(0))), 4_000_000);
        assert_eq!(estimate_total_bytes(&s(Some(6_000_000), Some(240)), &st(Mp3, None)), 6_000_000);
        assert_eq!(estimate_total_bytes(&s(None, Some(240)), &st(Mp3, None)), 0);
    }
}
