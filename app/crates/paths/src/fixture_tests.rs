//! Equality against golden fixtures generated from the Dart sources
//! (`app/fixtures/*.json`). A missing fixture file fails loudly.

use dapper_domain::{DeviceSettings, Playlist, Song};
use serde_json::Value;

use crate::dart_path::Style;
use crate::resolver::{build_album_folder_styled, build_playlist_path_styled, build_song_path_styled, match_zip_entry_styled, render};
use crate::*;

fn cases(name: &str) -> Vec<Value> {
    let path = format!("{}/../../fixtures/{name}.json", env!("CARGO_MANIFEST_DIR"));
    let text = std::fs::read_to_string(&path).unwrap_or_else(|e| panic!("{path}: {e}"));
    let v: Value = serde_json::from_str(&text).unwrap();
    v["cases"].as_array().unwrap().clone()
}

/// Expected value: `None` when Dart threw.
fn expected(c: &Value) -> Option<Value> {
    c.get("error").is_none().then(|| c["output"].clone())
}

fn style(input: &Value) -> Style {
    match input["platform"].as_str().unwrap() {
        "posix" => Style::Posix,
        "windows" => Style::Windows,
        p => panic!("platform {p}"),
    }
}

fn de<T: serde::de::DeserializeOwned>(v: &Value) -> T {
    serde_json::from_value(v.clone()).unwrap()
}

fn s(v: Option<String>) -> Value {
    v.map_or(Value::Null, Value::String)
}

/// Runs every case and reports all mismatches at once.
fn check(name: &str, f: impl Fn(&Value) -> Option<Value>) {
    let cases = cases(name);
    let mut failures = Vec::new();
    for c in &cases {
        let got = f(&c["input"]);
        let want = expected(c);
        if got != want {
            failures.push(format!("input {}\n  want {want:?}\n  got  {got:?}", c["input"]));
        }
    }
    let total = cases.len();
    assert!(failures.is_empty(), "{name}: {}/{total} mismatches\n{}", failures.len(), failures[..failures.len().min(20)].join("\n"));
    eprintln!("{name}: {total}/{total} agree");
}

#[test]
fn safe_filename() {
    check("safe_filename", |i| Some(Value::String(to_safe_filename(i.as_str().unwrap()))));
}

#[test]
fn song_path() {
    check("song_path", |i| {
        let song: Song = de(&i["song"]);
        let settings: DeviceSettings = de(&i["settings"]);
        build_song_path_styled(&song, &settings, style(i), true).map(Value::String)
    });
}

#[test]
fn filename_template() {
    check("filename_template", |i| {
        let t = i["template"].as_str().unwrap();
        match i["fn"].as_str().unwrap() {
            "renderFilenameTemplate" => render(t, &de(&i["song"]), true).map(Value::String),
            "validateFilenameTemplate" => Some(s(validate_filename_template(t).map(Into::into))),
            "validateFolderTemplate" => Some(s(validate_folder_template(t).map(Into::into))),
            f => panic!("fn {f}"),
        }
    });
}

#[test]
fn album_folder() {
    check("album_folder", |i| {
        let settings: DeviceSettings = de(&i["settings"]);
        match i["fn"].as_str().unwrap() {
            "buildAlbumFolder" => build_album_folder_styled(
                i["albumArtist"].as_str(),
                i["albumName"].as_str().unwrap(),
                i["year"].as_i64().map(|y| y as i32),
                &settings,
                style(i),
                true,
            )
            .map(s),
            "buildPlaylistPath" => {
                let playlist = Playlist { name: i["playlistName"].as_str().unwrap().into(), ..de(&serde_json::json!({"id": "p", "name": ""})) };
                Some(Value::String(build_playlist_path_styled(&playlist, &settings, style(i))))
            }
            f => panic!("fn {f}"),
        }
    });
}

#[test]
fn match_zip_entry() {
    check("match_zip_entry", |i| {
        let songs: Vec<Song> = de(&i["expected"]);
        Some(s(match_zip_entry_styled(i["entryPath"].as_str().unwrap(), &songs, style(i)).map(|m| m.id.clone())))
    });
}

/// misc.json also holds cases owned by other crates (parseDfOutput,
/// writePlaylistM3u); only this crate's functions are checked here.
#[test]
fn misc() {
    let all = cases("misc");
    let mut checked = 0;
    for c in &all {
        let i = &c["input"];
        let got = match i["fn"].as_str().unwrap() {
            "formatBytes" => Value::String(format_bytes(i["bytes"].as_i64().unwrap())),
            "estimateTotalBytes" => Value::from(estimate_total_bytes(&de(&i["song"]), &de(&i["settings"]))),
            "parseDfOutput" | "writePlaylistM3u" => continue,
            f => panic!("misc: unknown fn {f}"),
        };
        assert_eq!(Some(got), expected(c), "input {i}");
        checked += 1;
    }
    assert!(checked > 0);
    eprintln!("misc: {checked}/{checked} agree");
}
