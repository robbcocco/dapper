//! Real-output smoke test: serves generated WAV/FLAC over a local HTTP server
//! (with byte-range support), plays through the default output device at
//! volume 0, seeks, and follows auto-advance and the transcode fallback.
//! Skips itself when the machine has no audio output device.

use std::f32::consts::TAU;
use std::sync::{Arc, Mutex};
use std::time::Duration;

use async_trait::async_trait;
use dapper_audio::{PlaybackState, Player, StreamResolver};
use dapper_domain::{ScrobbleSink, Song};
use tokio::sync::watch;
use url::Url;
use wiremock::matchers::{method, path};
use wiremock::{Mock, MockServer, Request, Respond, ResponseTemplate};

const RATE: u32 = 44_100;

fn pcm(seconds: f32) -> Vec<i16> {
    let frames = (RATE as f32 * seconds) as usize;
    (0..frames * 2)
        .map(|i| ((TAU * 440.0 * (i / 2) as f32 / RATE as f32).sin() * 1000.0) as i16)
        .collect()
}

fn wav(seconds: f32) -> Vec<u8> {
    let samples = pcm(seconds);
    let data_len = (samples.len() * 2) as u32;
    let mut out = Vec::with_capacity(44 + data_len as usize);
    out.extend_from_slice(b"RIFF");
    out.extend_from_slice(&(36 + data_len).to_le_bytes());
    out.extend_from_slice(b"WAVEfmt ");
    out.extend_from_slice(&16u32.to_le_bytes());
    out.extend_from_slice(&1u16.to_le_bytes()); // PCM
    out.extend_from_slice(&2u16.to_le_bytes());
    out.extend_from_slice(&RATE.to_le_bytes());
    out.extend_from_slice(&(RATE * 4).to_le_bytes());
    out.extend_from_slice(&4u16.to_le_bytes());
    out.extend_from_slice(&16u16.to_le_bytes());
    out.extend_from_slice(b"data");
    out.extend_from_slice(&data_len.to_le_bytes());
    for s in samples {
        out.extend_from_slice(&s.to_le_bytes());
    }
    out
}

fn crc8(bytes: &[u8]) -> u8 {
    bytes.iter().fold(0u8, |mut crc, &b| {
        crc ^= b;
        for _ in 0..8 {
            crc = if crc & 0x80 != 0 {
                (crc << 1) ^ 0x07
            } else {
                crc << 1
            };
        }
        crc
    })
}

fn crc16(bytes: &[u8]) -> u16 {
    bytes.iter().fold(0u16, |mut crc, &b| {
        crc ^= u16::from(b) << 8;
        for _ in 0..8 {
            crc = if crc & 0x8000 != 0 {
                (crc << 1) ^ 0x8005
            } else {
                crc << 1
            };
        }
        crc
    })
}

/// Minimal FLAC encoder: 16-bit stereo, fixed 4096-sample blocks, VERBATIM subframes.
fn flac(seconds: f32) -> Vec<u8> {
    const BLOCK: usize = 4096;
    let samples = pcm(seconds);
    let total = (samples.len() / 2) as u64;
    let mut out = b"fLaC".to_vec();
    out.extend_from_slice(&[0x80, 0, 0, 34]); // last block, STREAMINFO, 34 bytes
    out.extend_from_slice(&(BLOCK as u16).to_be_bytes());
    out.extend_from_slice(&(BLOCK as u16).to_be_bytes());
    out.extend_from_slice(&[0; 6]); // unknown min/max frame size
    let packed = (u64::from(RATE) << 44) | (1 << 41) | (15 << 36) | total;
    out.extend_from_slice(&packed.to_be_bytes());
    out.extend_from_slice(&[0; 16]); // MD5 unknown

    for (n, block) in samples.chunks(BLOCK * 2).enumerate() {
        let frame_start = out.len();
        out.extend_from_slice(&[0xFF, 0xF8, 0x79, 0x18]);
        // UTF-8 style coded frame number (< 2048 here).
        if n < 0x80 {
            out.push(n as u8);
        } else {
            out.push(0xC0 | (n >> 6) as u8);
            out.push(0x80 | (n & 0x3F) as u8);
        }
        out.extend_from_slice(&((block.len() / 2 - 1) as u16).to_be_bytes());
        out.push(crc8(&out[frame_start..]));
        for channel in 0..2 {
            out.push(0x02); // VERBATIM, no wasted bits
            for frame in block.chunks(2) {
                out.extend_from_slice(&frame[channel].to_be_bytes());
            }
        }
        let crc = crc16(&out[frame_start..]);
        out.extend_from_slice(&crc.to_be_bytes());
    }
    out
}

/// Serves a body honouring `Range: bytes=a-b` like Navidrome does.
struct RangeBody {
    body: Vec<u8>,
    mime: &'static str,
}

impl Respond for RangeBody {
    fn respond(&self, request: &Request) -> ResponseTemplate {
        let len = self.body.len();
        let range = request
            .headers
            .get("range")
            .and_then(|v| v.to_str().ok())
            .and_then(|v| v.strip_prefix("bytes="))
            .and_then(|v| v.split_once('-'))
            .and_then(|(a, b)| {
                let start: usize = a.parse().ok()?;
                let end = if b.is_empty() {
                    len - 1
                } else {
                    b.parse::<usize>().ok()?.min(len - 1)
                };
                (start <= end).then_some((start, end))
            });
        match range {
            Some((start, end)) => ResponseTemplate::new(206)
                .insert_header("accept-ranges", "bytes")
                .insert_header("content-range", format!("bytes {start}-{end}/{len}"))
                .set_body_raw(self.body[start..=end].to_vec(), self.mime),
            None => ResponseTemplate::new(200)
                .insert_header("accept-ranges", "bytes")
                .set_body_raw(self.body.clone(), self.mime),
        }
    }
}

struct Resolver(Url);

impl StreamResolver for Resolver {
    fn stream_url(&self, song: &Song, transcode: bool) -> Url {
        let kind = if transcode { "transcode" } else { "stream" };
        self.0
            .join(&format!("/{kind}/{}?t=secret", song.id))
            .unwrap()
    }
}

#[derive(Default)]
struct Scrobbles(Mutex<Vec<(String, bool)>>);

#[async_trait]
impl ScrobbleSink for Scrobbles {
    async fn scrobble(
        &self,
        song_id: &str,
        submission: bool,
        _time_ms: Option<i64>,
    ) -> dapper_domain::Result<()> {
        self.0
            .lock()
            .unwrap()
            .push((song_id.to_owned(), submission));
        Ok(())
    }
}

fn song(id: &str, suffix: &str, seconds: i64) -> Song {
    Song {
        id: id.into(),
        title: id.into(),
        suffix: Some(suffix.into()),
        duration: Some(seconds),
        ..Song::default()
    }
}

async fn mount(server: &MockServer, route: &str, body: Vec<u8>, mime: &'static str) {
    Mock::given(method("GET"))
        .and(path(route))
        .respond_with(RangeBody { body, mime })
        .mount(server)
        .await;
}

async fn wait_state(
    rx: &mut watch::Receiver<PlaybackState>,
    what: &str,
    f: impl FnMut(&PlaybackState) -> bool,
) -> PlaybackState {
    let waited = tokio::time::timeout(Duration::from_secs(15), rx.wait_for(f))
        .await
        .map(|r| r.expect("engine alive").clone());
    waited.unwrap_or_else(|_| panic!("timed out waiting for {what}: {:?}", *rx.borrow()))
}

async fn wait_position(rx: &mut watch::Receiver<Duration>, what: &str, min: Duration) -> Duration {
    let waited = tokio::time::timeout(Duration::from_secs(15), rx.wait_for(|p| *p >= min))
        .await
        .map(|r| *r.expect("engine alive"));
    waited.unwrap_or_else(|_| panic!("timed out waiting for {what}: {:?}", *rx.borrow()))
}

/// Initial (non-range) GETs of `route`; seeking adds range requests on top.
async fn hits(server: &MockServer, route: &str) -> usize {
    server
        .received_requests()
        .await
        .unwrap_or_default()
        .iter()
        .filter(|r| r.url.path() == route && !r.headers.contains_key("range"))
        .count()
}

#[tokio::test(flavor = "multi_thread")]
async fn plays_seeks_advances_and_falls_back_to_transcode() {
    if let Err(e) = rodio::DeviceSinkBuilder::open_default_sink() {
        eprintln!("skipping playback smoke test: no audio output device ({e})");
        return;
    }

    let server = MockServer::start().await;
    mount(&server, "/stream/w", wav(3.0), "audio/wav").await;
    mount(&server, "/stream/f", flac(2.0), "audio/flac").await;
    mount(&server, "/transcode/o", wav(1.0), "audio/wav").await;
    mount(&server, "/stream/bad", vec![0x5A; 64 * 1024], "audio/flac").await;
    mount(&server, "/transcode/bad", wav(1.0), "audio/wav").await;
    mount(&server, "/stream/long", wav(30.0), "audio/wav").await;

    let scrobbles = Arc::new(Scrobbles::default());
    let player = Player::new(
        tokio::runtime::Handle::current(),
        Arc::new(Resolver(Url::parse(&server.uri()).unwrap())),
        scrobbles.clone(),
    )
    .unwrap();
    let mut state = player.subscribe();
    let mut position = player.subscribe_position();

    player.set_volume(0.0);
    player.set_queue(vec![song("w", "wav", 3), song("f", "flac", 2)], 0);

    let playing = |s: &PlaybackState| s.is_playing && !s.is_buffering;
    let s = wait_state(&mut state, "wav playing", |s| {
        playing(s) && s.current_index == 0
    })
    .await;
    assert_eq!(s.current_song.as_ref().unwrap().id, "w");
    assert_eq!(s.volume, 0.0);
    assert!(!s.is_buffering);
    assert!(
        (s.duration.as_secs_f32() - 3.0).abs() < 0.05,
        "wav duration {:?}",
        s.duration
    );

    tokio::time::sleep(Duration::from_secs(1)).await;
    let p = player.position();
    assert!(
        p >= Duration::from_millis(500),
        "wav position after 1 s: {p:?}"
    );

    player.seek(Duration::from_secs(2));
    wait_position(&mut position, "wav seek", Duration::from_secs(2)).await;

    let s = wait_state(&mut state, "auto-advance to flac", |s| {
        playing(s) && s.current_index == 1
    })
    .await;
    assert_eq!(s.current_song.as_ref().unwrap().id, "f");
    assert!(
        (s.duration.as_secs_f32() - 2.0).abs() < 0.05,
        "flac duration {:?}",
        s.duration
    );
    wait_position(&mut position, "flac progress", Duration::from_millis(300)).await;

    player.seek(Duration::from_millis(1500));
    wait_position(&mut position, "flac seek", Duration::from_millis(1500)).await;

    let s = wait_state(&mut state, "end of queue", |s| !s.is_playing).await;
    assert_eq!(s.current_index, 1);
    assert!(s.error_message.is_none());

    // Undecodable suffix goes straight to the transcode endpoint.
    player.play_song(song("o", "opus", 1));
    wait_state(&mut state, "opus via transcode", |s| {
        playing(s) && s.current_song.as_ref().is_some_and(|c| c.id == "o")
    })
    .await;
    assert_eq!(hits(&server, "/stream/o").await, 0);
    assert_eq!(hits(&server, "/transcode/o").await, 1);

    // Decoder rejects the original at open → re-requested as a transcode.
    player.play_song(song("bad", "flac", 1));
    let s = wait_state(&mut state, "bad flac via transcode", |s| {
        playing(s) && s.current_song.as_ref().is_some_and(|c| c.id == "bad")
    })
    .await;
    assert!(s.error_message.is_none());
    assert!(hits(&server, "/stream/bad").await >= 1);
    assert_eq!(hits(&server, "/transcode/bad").await, 1);

    // Scrobble pings run as detached tasks; poll until the expected count lands.
    let calls = || scrobbles.0.lock().unwrap().clone();
    let settle = |n: usize| async move {
        for _ in 0..40 {
            if calls().len() >= n {
                break;
            }
            tokio::time::sleep(Duration::from_millis(50)).await;
        }
    };
    settle(4).await;
    let now_playing = |c: &[(String, bool)]| -> Vec<String> {
        c.iter()
            .filter(|(_, sub)| !sub)
            .map(|(id, _)| id.clone())
            .collect()
    };
    // Tracks under 30 s never get a full scrobble.
    assert_eq!(
        calls(),
        [("w", false), ("f", false), ("o", false), ("bad", false)]
            .map(|(id, s)| (id.to_owned(), s))
    );

    // Repeat-one on a 30 s track: past 50% → one submission; the loop replays
    // the song as a fresh playback (new now-playing, submission allowed again).
    player.cycle_repeat();
    player.cycle_repeat();
    player.play_song(song("long", "wav", 30));
    let s = wait_state(&mut state, "long playing", |s| {
        playing(s) && s.current_song.as_ref().is_some_and(|c| c.id == "long")
    })
    .await;
    assert_eq!(s.repeat_mode, dapper_domain::RepeatMode::One);
    player.seek(Duration::from_millis(29_500));
    wait_position(&mut position, "long seek", Duration::from_millis(29_500)).await;
    settle(6).await;
    let after_loop = calls();
    assert_eq!(
        after_loop[4..6],
        [("long".to_owned(), false), ("long".to_owned(), true)]
    );
    // Replay restarts from zero.
    tokio::time::timeout(
        Duration::from_secs(5),
        position.wait_for(|p| *p < Duration::from_secs(1)),
    )
    .await
    .expect("repeat-one replay")
    .unwrap();
    settle(7).await;
    let c = calls();
    assert_eq!(c[6..], [("long".to_owned(), false)]);
    assert_eq!(now_playing(&c), ["w", "f", "o", "bad", "long", "long"]);
    assert_eq!(hits(&server, "/stream/long").await, 2);

    player.stop();
    let s = wait_state(&mut state, "stopped", |s| s.queue.is_empty()).await;
    assert!(!s.is_playing && s.current_song.is_none());
    assert_eq!(s.repeat_mode, dapper_domain::RepeatMode::One);
}
