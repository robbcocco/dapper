//! Golden fixtures generated from the Dart implementation (`app/fixtures/`).

use std::fs;
use std::path::{Path, PathBuf};

use base64::Engine;
use dapper_device::{
    AlbumManifest, DEFAULT_PICTURE_JPEG_QUALITY, DEFAULT_PICTURE_MAX_EDGE, DeviceCaches, MANIFEST_FILENAME,
    ManifestSong, parse_scrobbler_log, rewritten_scrobbler_log, sanitize_flac_tags, shrink_flac_embedded_picture,
};
use dapper_domain::Song;
use serde_json::{Value, json};

fn fixtures_dir() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR")).join("../../fixtures")
}

/// Cases of `name.json`, minus generator failures (marked with `error`).
fn cases(name: &str) -> Vec<Value> {
    let path = fixtures_dir().join(format!("{name}.json"));
    let doc: Value = serde_json::from_slice(&fs::read(&path).unwrap_or_else(|e| panic!("{}: {e}", path.display()))).unwrap();
    doc["cases"].as_array().unwrap().iter().filter(|c| c.get("error").is_none()).cloned().collect()
}

fn manifest_json(m: Option<&AlbumManifest>) -> Value {
    m.map_or(Value::Null, |m| {
        json!({
            "expectedSongCount": m.expected_song_count,
            "songs": m.songs.iter().map(|s| json!({
                "id": s.id, "title": s.title, "artist": s.artist, "album": s.album, "filename": s.filename,
            })).collect::<Vec<_>>(),
        })
    })
}

#[test]
fn manifest_fixtures() {
    let cases = cases("manifest");
    assert!(!cases.is_empty());
    for (i, case) in cases.iter().enumerate() {
        let input = &case["input"];
        let output = &case["output"];
        let dir = tempfile::tempdir().unwrap();
        let file = dir.path().join(MANIFEST_FILENAME);
        match output["kind"].as_str().unwrap() {
            "read" => {
                if let Some(text) = input["text"].as_str() {
                    fs::write(&file, text).unwrap();
                } else if let Some(b64) = input["base64"].as_str() {
                    fs::write(&file, base64::engine::general_purpose::STANDARD.decode(b64).unwrap()).unwrap();
                }
                let caches = DeviceCaches::new();
                let got = caches.read_manifest(dir.path());
                assert_eq!(manifest_json(got.as_deref()), output["manifest"], "case {i}: {input}");
            }
            "write" => {
                if let Some(existing) = input["existing"].as_str() {
                    fs::write(&file, existing).unwrap();
                }
                let entries: Vec<ManifestSong> = input["entries"]
                    .as_array()
                    .unwrap()
                    .iter()
                    .map(|e| {
                        let song: Song = serde_json::from_value(e["song"].clone()).unwrap();
                        ManifestSong::for_song(&song, e["filename"].as_str().map(Into::into))
                    })
                    .collect();
                DeviceCaches::new()
                    .add_songs_to_manifest(dir.path(), entries, input["expectedSongCount"].as_i64())
                    .unwrap();
                let text = fs::read_to_string(&file).ok();
                let expected = output["text"].as_str().map(str::to_owned).or_else(|| input["existing"].as_str().map(str::to_owned));
                assert_eq!(text, expected, "case {i}: {input}");
            }
            k => panic!("unknown kind {k}"),
        }
    }
}

#[test]
fn scrobbler_log_fixtures() {
    let cases = cases("scrobbler_log");
    assert!(!cases.is_empty());
    for (i, case) in cases.iter().enumerate() {
        let input = &case["input"];
        match input["fn"].as_str().unwrap() {
            "parse" => {
                let got: Vec<Value> = parse_scrobbler_log(input["contents"].as_str().unwrap())
                    .into_iter()
                    .map(|e| {
                        json!({
                            "artist": e.artist, "album": e.album, "title": e.title,
                            "trackNumber": e.track_number, "lengthSeconds": e.length_seconds,
                            "timestamp": e.timestamp, "musicBrainzId": e.music_brainz_id, "raw": e.raw,
                        })
                    })
                    .collect();
                let expected: Vec<Value> = case["output"]
                    .as_array()
                    .unwrap_or_else(|| panic!("case {i}: {case}"))
                    .iter()
                    .map(|e| {
                        let mut e = e.clone();
                        e.as_object_mut().unwrap().remove("timestampIso");
                        e
                    })
                    .collect();
                assert_eq!(got, expected, "case {i}: {input}");
            }
            "rewrite" => {
                let keep: Vec<String> = serde_json::from_value(input["keepRaws"].clone()).unwrap();
                assert_eq!(
                    rewritten_scrobbler_log(input["original"].as_str().unwrap(), &keep),
                    case["output"].as_str().unwrap(),
                    "case {i}: {input}"
                );
            }
            f => panic!("unknown fn {f}"),
        }
    }
}

#[cfg(unix)]
#[test]
fn m3u_fixtures() {
    use dapper_domain::{DeviceSettings, Playlist};

    let cases: Vec<Value> = cases("misc").into_iter().filter(|c| c["input"]["fn"] == "writePlaylistM3u").collect();
    assert!(!cases.is_empty());
    for (i, case) in cases.iter().enumerate() {
        let input = &case["input"];
        // Dart's temp device root was named `device`; cases whose playlist
        // folder escapes the device (`../Outside`) see that name.
        let dir = tempfile::tempdir().unwrap();
        let root = dir.path().join("device");
        fs::create_dir(&root).unwrap();
        let device = root.to_str().unwrap();
        let mut settings: DeviceSettings = serde_json::from_value(input["settings"].clone()).unwrap();
        settings.device_path = settings.device_path.replace("<device>", device);
        settings.music_root_folder = settings.music_root_folder.replace("<device>", device);
        let songs: Vec<Song> = serde_json::from_value(input["playlist"]["songs"].clone()).unwrap();
        let present: Vec<&str> = input["presentSongIds"].as_array().unwrap().iter().map(|v| v.as_str().unwrap()).collect();
        for s in songs.iter().filter(|s| present.contains(&s.id.as_str())) {
            let p = PathBuf::from(dapper_paths::build_song_path(s, &settings));
            fs::create_dir_all(p.parent().unwrap()).unwrap();
            fs::write(&p, b"x").unwrap();
        }
        let playlist = Playlist { name: input["playlist"]["name"].as_str().unwrap().into(), songs, ..Default::default() };
        let wrote = dapper_device::write_playlist_m3u(&playlist, &settings).unwrap();
        let path = dapper_paths::build_playlist_path(&playlist, &settings);
        assert_eq!(path, case["output"]["path"].as_str().unwrap().replace("<device>", device), "case {i}");
        let content = fs::read_to_string(&path).ok();
        assert_eq!(content.as_deref(), case["output"]["content"].as_str(), "case {i}: {input}");
        assert_eq!(wrote, content.is_some(), "case {i}");
        assert_eq!(dapper_device::playlist_exists_on_device(&playlist, &settings), wrote, "case {i}");
    }
}

/// Copies a fixture into a temp dir under the name the function must see.
fn stage(input: &Value) -> (tempfile::TempDir, PathBuf, Vec<u8>) {
    let bytes = fs::read(fixtures_dir().join(input["inFile"].as_str().unwrap())).unwrap();
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join(input["fileName"].as_str().unwrap());
    fs::write(&path, &bytes).unwrap();
    (dir, path, bytes)
}

#[test]
fn flac_sanitize_fixtures() {
    let cases = cases("flac_sanitize");
    assert!(!cases.is_empty());
    for case in &cases {
        let (input, output) = (&case["input"], &case["output"]);
        let (_dir, path, _) = stage(input);
        let changed = sanitize_flac_tags(&path);
        let expected = fs::read(fixtures_dir().join(output["outFile"].as_str().unwrap())).unwrap();
        assert_eq!(changed, output["changed"].as_bool().unwrap(), "{}", input["name"]);
        assert!(fs::read(&path).unwrap() == expected, "{}: bytes differ", input["name"]);
    }
}

struct Block {
    block_type: u8,
    is_last: bool,
    body: Vec<u8>,
}

/// Minimal FLAC metadata split for structural assertions.
fn split_flac(bytes: &[u8]) -> (Vec<Block>, &[u8]) {
    assert_eq!(&bytes[..4], b"fLaC");
    let mut off = 4;
    let mut blocks = Vec::new();
    loop {
        let h = &bytes[off..off + 4];
        let size = (usize::from(h[1]) << 16) | (usize::from(h[2]) << 8) | usize::from(h[3]);
        let block = Block { block_type: h[0] & 0x7f, is_last: h[0] & 0x80 != 0, body: bytes[off + 4..off + 4 + size].to_vec() };
        off += 4 + size;
        let last = block.is_last;
        blocks.push(block);
        if last {
            return (blocks, &bytes[off..]);
        }
    }
}

fn be32(b: &[u8], off: &mut usize) -> u32 {
    let v = u32::from_be_bytes(b[*off..*off + 4].try_into().unwrap());
    *off += 4;
    v
}

fn take<'a>(b: &'a [u8], off: &mut usize, len: usize) -> &'a [u8] {
    let s = &b[*off..*off + len];
    *off += len;
    s
}

#[test]
fn flac_shrink_fixtures() {
    let cases = cases("flac_shrink");
    assert!(!cases.is_empty());
    for case in &cases {
        let (input, output) = (&case["input"], &case["output"]);
        let name = &input["name"];
        let (_dir, path, original) = stage(input);
        let changed = shrink_flac_embedded_picture(&path, DEFAULT_PICTURE_MAX_EDGE, DEFAULT_PICTURE_JPEG_QUALITY);
        assert_eq!(changed, output["changed"].as_bool().unwrap(), "{name}");
        let after = fs::read(&path).unwrap();
        if !changed {
            assert!(after == original, "{name}: unchanged file was modified");
            continue;
        }
        assert!(after.len() < original.len(), "{name}");
        let (in_blocks, in_audio) = split_flac(&original);
        let (blocks, audio) = split_flac(&after);
        assert!(audio == in_audio, "{name}: audio moved incorrectly");
        assert_eq!(audio.len() as u64, output["audioLength"].as_u64().unwrap(), "{name}");
        let expected_blocks = output["blocks"].as_array().unwrap();
        assert_eq!(blocks.len(), expected_blocks.len(), "{name}");
        let pic_idx = blocks.iter().position(|b| b.block_type == 6).unwrap();
        for (i, (b, e)) in blocks.iter().zip(expected_blocks).enumerate() {
            assert_eq!(u64::from(b.block_type), e["type"].as_u64().unwrap(), "{name} block {i}");
            assert_eq!(b.is_last, e["isLast"].as_bool().unwrap(), "{name} block {i}");
            if i != pic_idx {
                assert!(b.body == in_blocks[i].body, "{name} block {i} changed");
            }
        }
        let pic = &blocks[pic_idx].body;
        let exp = &output["picture"];
        let mut off = 0;
        assert_eq!(u64::from(be32(pic, &mut off)), exp["pictureType"].as_u64().unwrap(), "{name}");
        let n = be32(pic, &mut off) as usize;
        assert_eq!(take(pic, &mut off, n), exp["mime"].as_str().unwrap().as_bytes(), "{name}");
        let n = be32(pic, &mut off) as usize;
        assert_eq!(take(pic, &mut off, n), exp["description"].as_str().unwrap().as_bytes(), "{name}");
        for key in ["width", "height", "depth", "colors"] {
            assert_eq!(u64::from(be32(pic, &mut off)), exp[key].as_u64().unwrap(), "{name} {key}");
        }
        let n = be32(pic, &mut off) as usize;
        let data = take(pic, &mut off, n);
        assert_eq!(off, pic.len(), "{name}");
        assert_eq!(exp["decodedFormat"], "jpg", "{name}");
        let img = image::load_from_memory_with_format(data, image::ImageFormat::Jpeg).unwrap();
        assert_eq!(u64::from(img.width()), exp["decodedWidth"].as_u64().unwrap(), "{name}");
        assert_eq!(u64::from(img.height()), exp["decodedHeight"].as_u64().unwrap(), "{name}");
    }
}
