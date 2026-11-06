use std::sync::Arc;
use std::sync::mpsc;
use std::time::Duration;

use dapper_domain::{AppError, RepeatMode, Result, ScrobbleSink, Song};
use serde::{Serialize, Serializer};
use tokio::sync::watch;

use crate::engine::{Command, Engine};
use crate::stream::{Loader, StreamResolver};

/// Snapshot of the player, published on every change except position (which
/// has its own, higher-frequency channel).
#[derive(Debug, Clone, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct PlaybackState {
    pub current_song: Option<Song>,
    pub queue: Arc<[Song]>,
    pub current_index: usize,
    pub is_playing: bool,
    pub is_buffering: bool,
    /// Serialised as whole milliseconds.
    #[serde(serialize_with = "as_millis")]
    pub duration: Duration,
    pub volume: f32,
    pub is_shuffled: bool,
    pub repeat_mode: RepeatMode,
    /// Last load / decode / network error; cleared when a new song starts loading.
    pub error_message: Option<String>,
}

impl Default for PlaybackState {
    fn default() -> Self {
        Self {
            current_song: None,
            queue: Arc::from([]),
            current_index: 0,
            is_playing: false,
            is_buffering: false,
            duration: Duration::ZERO,
            volume: 1.0,
            is_shuffled: false,
            repeat_mode: RepeatMode::None,
            error_message: None,
        }
    }
}

impl PlaybackState {
    pub fn has_previous(&self) -> bool {
        self.current_index > 0 || self.repeat_mode == RepeatMode::All
    }

    pub fn has_next(&self) -> bool {
        self.current_index + 1 < self.queue.len() || self.repeat_mode == RepeatMode::All
    }
}

fn as_millis<S: Serializer>(d: &Duration, s: S) -> std::result::Result<S::Ok, S::Error> {
    s.serialize_u64(u64::try_from(d.as_millis()).unwrap_or(u64::MAX))
}

/// Handle to the audio engine thread. `Send + Sync`; dropping it shuts the
/// engine down and stops output.
pub struct Player {
    commands: mpsc::Sender<Command>,
    state: watch::Receiver<PlaybackState>,
    position: watch::Receiver<Duration>,
}

impl Player {
    /// Spawns the engine thread. Streams are fetched and scrobbles sent on
    /// `runtime`; output runs on a dedicated thread because rodio's device
    /// sink isn't `Send`.
    pub fn new(
        runtime: tokio::runtime::Handle,
        resolver: Arc<dyn StreamResolver>,
        scrobbler: Arc<dyn ScrobbleSink>,
    ) -> Result<Self> {
        let (commands, rx) = mpsc::channel();
        let (state_tx, state) = watch::channel(PlaybackState::default());
        let (position_tx, position) = watch::channel(Duration::ZERO);
        let engine = Engine::new(
            rx,
            commands.clone(),
            runtime,
            Arc::new(Loader::new(resolver)),
            scrobbler,
            state_tx,
            position_tx,
        );
        std::thread::Builder::new()
            .name("dapper-audio".into())
            .spawn(move || engine.run())
            .map_err(|e| AppError::Other(format!("Could not start audio engine: {e}")))?;
        Ok(Self {
            commands,
            state,
            position,
        })
    }

    /// Replaces the queue and plays `songs[start]` (clamped). Resets shuffle.
    pub fn set_queue(&self, songs: Vec<Song>, start: usize) {
        self.send(Command::SetQueue(songs, start));
    }

    /// Plays one song as a single-item queue. Resets shuffle.
    pub fn play_song(&self, song: Song) {
        self.send(Command::PlaySong(Box::new(song)));
    }

    pub fn toggle_play_pause(&self) {
        self.send(Command::TogglePlayPause);
    }

    pub fn next(&self) {
        self.send(Command::Next);
    }

    /// Restarts the current song when more than 3 s in, otherwise steps back.
    pub fn previous(&self) {
        self.send(Command::Previous);
    }

    pub fn seek(&self, position: Duration) {
        self.send(Command::Seek(position));
    }

    /// `0.0..=1.0`; out-of-range values are clamped.
    pub fn set_volume(&self, volume: f32) {
        self.send(Command::SetVolume(volume));
    }

    pub fn toggle_shuffle(&self) {
        self.send(Command::ToggleShuffle);
    }

    /// none → all → one → none.
    pub fn cycle_repeat(&self) {
        self.send(Command::CycleRepeat);
    }

    /// Stops output and clears the queue (volume and repeat mode are kept).
    pub fn stop(&self) {
        self.send(Command::Stop);
    }

    pub fn subscribe(&self) -> watch::Receiver<PlaybackState> {
        self.state.clone()
    }

    /// Position of the current song, updated ~4 times a second while loaded.
    pub fn subscribe_position(&self) -> watch::Receiver<Duration> {
        self.position.clone()
    }

    pub fn state(&self) -> PlaybackState {
        self.state.borrow().clone()
    }

    pub fn position(&self) -> Duration {
        *self.position.borrow()
    }

    fn send(&self, command: Command) {
        if self.commands.send(command).is_err() {
            tracing::error!("audio engine thread is not running");
        }
    }
}

impl Drop for Player {
    fn drop(&mut self) {
        let _ = self.commands.send(Command::Shutdown);
    }
}
