use std::sync::Arc;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::mpsc::{Receiver, RecvTimeoutError, Sender};
use std::time::{Duration, Instant};

use dapper_domain::{ScrobbleSink, Song};
use rodio::{CpalError, CpalErrorKind, DeviceSinkBuilder, MixerDeviceSink};
use tokio::runtime::Handle;
use tokio::sync::watch;
use tokio::task::JoinHandle;

use crate::player::PlaybackState;
use crate::queue::{CompletionAction, PlayQueue, PreviousAction};
use crate::scrobble_rule::should_scrobble;
use crate::stream::{LoadedTrack, Loader};

const TICK: Duration = Duration::from_millis(250);

pub(crate) enum Command {
    SetQueue(Vec<Song>, usize),
    PlaySong(Box<Song>),
    TogglePlayPause,
    Next,
    Previous,
    Seek(Duration),
    SetVolume(f32),
    ToggleShuffle,
    CycleRepeat,
    Stop,
    Loaded {
        generation: u64,
        result: Result<LoadedTrack, String>,
    },
    Shutdown,
}

/// Owns the output device and the current track; lives on its own thread.
pub(crate) struct Engine {
    commands: Receiver<Command>,
    /// Loader tasks report back through the same channel.
    loopback: Sender<Command>,
    runtime: Handle,
    loader: Arc<Loader>,
    scrobbler: Arc<dyn ScrobbleSink>,
    state: watch::Sender<PlaybackState>,
    position: watch::Sender<Duration>,

    queue: PlayQueue,
    output: Option<MixerDeviceSink>,
    /// Set from cpal's error callback when the output stream can't continue
    /// (device unplugged, stream invalidated); the engine then drops the sink.
    output_lost: Arc<AtomicBool>,
    track: Option<rodio::Player>,
    /// Bumped on every load so results for abandoned songs are discarded.
    generation: u64,
    load_task: Option<JoinHandle<()>>,
    is_playing: bool,
    is_buffering: bool,
    duration: Duration,
    volume: f32,
    error: Option<String>,
    /// Full scrobble already sent for this playback (reset per track and per repeat-one loop).
    scrobbled: bool,
}

impl Engine {
    pub fn new(
        commands: Receiver<Command>,
        loopback: Sender<Command>,
        runtime: Handle,
        loader: Arc<Loader>,
        scrobbler: Arc<dyn ScrobbleSink>,
        state: watch::Sender<PlaybackState>,
        position: watch::Sender<Duration>,
    ) -> Self {
        Self {
            commands,
            loopback,
            runtime,
            loader,
            scrobbler,
            state,
            position,
            queue: PlayQueue::new(),
            output: None,
            output_lost: Arc::new(AtomicBool::new(false)),
            track: None,
            generation: 0,
            load_task: None,
            is_playing: false,
            is_buffering: false,
            duration: Duration::ZERO,
            volume: 1.0,
            error: None,
            scrobbled: false,
        }
    }

    pub fn run(mut self) {
        let mut next_tick = Instant::now() + TICK;
        loop {
            match self
                .commands
                .recv_timeout(next_tick.saturating_duration_since(Instant::now()))
            {
                Ok(command) => {
                    if !self.handle(command) {
                        break;
                    }
                }
                Err(RecvTimeoutError::Disconnected) => break,
                Err(RecvTimeoutError::Timeout) => {}
            }
            if Instant::now() >= next_tick {
                self.tick();
                next_tick = Instant::now() + TICK;
            }
        }
        self.cancel_load();
    }

    /// Returns `false` once the engine should shut down.
    fn handle(&mut self, command: Command) -> bool {
        match command {
            Command::SetQueue(songs, start) => {
                self.queue.set_queue(songs, start);
                self.start_current();
            }
            Command::PlaySong(song) => {
                self.queue.play_song(*song);
                self.start_current();
            }
            Command::TogglePlayPause => self.toggle_play_pause(),
            Command::Next => {
                if self.queue.advance() {
                    self.start_current();
                }
            }
            Command::Previous => match self.queue.previous(self.current_position()) {
                PreviousAction::SeekToStart => self.seek(Duration::ZERO),
                PreviousAction::PlayCurrent => self.start_current(),
                PreviousAction::None => {}
            },
            Command::Seek(position) => self.seek(position),
            Command::SetVolume(volume) => {
                self.volume = volume.clamp(0.0, 1.0);
                if let Some(track) = &self.track {
                    track.set_volume(self.volume);
                }
                self.publish();
            }
            Command::ToggleShuffle => {
                self.queue.toggle_shuffle(&mut rand::rng());
                self.publish();
            }
            Command::CycleRepeat => {
                self.queue.cycle_repeat();
                self.publish();
            }
            Command::Stop => {
                self.queue.clear();
                self.cancel_load();
                self.track = None;
                self.is_playing = false;
                self.is_buffering = false;
                self.duration = Duration::ZERO;
                self.error = None;
                self.position.send_replace(Duration::ZERO);
                self.publish();
            }
            Command::Loaded { generation, result } => {
                if generation == self.generation {
                    self.load_task = None;
                    self.on_loaded(result);
                }
            }
            Command::Shutdown => return false,
        }
        true
    }

    fn toggle_play_pause(&mut self) {
        if let Some(track) = &self.track {
            if track.is_paused() {
                track.play();
                self.is_playing = true;
            } else {
                track.pause();
                self.is_playing = false;
            }
            self.publish();
        } else if self.load_task.is_none() && self.queue.current().is_some() {
            // Nothing loaded (finished queue or failed load): start the current song over.
            self.start_current();
        }
    }

    fn seek(&mut self, position: Duration) {
        // rodio's seek waits on the audio callback, which a dead stream never runs.
        if self.output_lost.load(Ordering::Relaxed) {
            return;
        }
        let Some(track) = &self.track else { return };
        if let Err(e) = track.try_seek(position) {
            tracing::warn!(error = %e, "seek failed");
        }
        self.position.send_replace(track.get_pos());
    }

    fn current_position(&self) -> Duration {
        match &self.track {
            Some(track) => track.get_pos(),
            None => *self.position.borrow(),
        }
    }

    /// Begins a fresh playback of the queue's current song.
    fn start_current(&mut self) {
        self.cancel_load();
        self.track = None;
        self.duration = Duration::ZERO;
        self.position.send_replace(Duration::ZERO);
        self.scrobbled = false;
        let Some(song) = self.queue.current().cloned() else {
            self.is_playing = false;
            self.is_buffering = false;
            self.publish();
            return;
        };
        self.error = None;
        self.is_buffering = true;
        self.publish();

        let generation = self.generation;
        let loader = self.loader.clone();
        let reply = self.loopback.clone();
        self.load_task = Some(self.runtime.spawn(async move {
            let result = loader.load(&song).await;
            if let Err(e) = &result {
                tracing::warn!(song_id = %song.id, error = %e, "playback load failed");
            }
            let _ = reply.send(Command::Loaded { generation, result });
        }));
    }

    fn cancel_load(&mut self) {
        self.generation += 1;
        if let Some(task) = self.load_task.take() {
            task.abort();
        }
    }

    fn on_loaded(&mut self, result: Result<LoadedTrack, String>) {
        let track = match result.and_then(|loaded| self.output_player().map(|p| (p, loaded))) {
            Ok((player, loaded)) => {
                player.set_volume(self.volume);
                player.append(loaded.source);
                self.duration = loaded.duration;
                player
            }
            Err(e) => {
                self.is_buffering = false;
                self.is_playing = false;
                self.error = Some(format!("Playback failed: {e}"));
                self.publish();
                return;
            }
        };
        self.track = Some(track);
        self.is_buffering = false;
        self.is_playing = true;
        self.publish();
        // "Now playing" only once the stream was accepted, so failed loads don't ping.
        if let Some(song) = self.queue.current() {
            self.scrobble(song.id.clone(), false);
        }
    }

    /// A fresh rodio player on the (lazily opened) default output device.
    fn output_player(&mut self) -> Result<rodio::Player, String> {
        if self.output.is_none() {
            self.output_lost.store(false, Ordering::Relaxed);
            let lost = self.output_lost.clone();
            let on_error = move |e: CpalError| match e.kind() {
                CpalErrorKind::DeviceNotAvailable
                | CpalErrorKind::StreamInvalidated
                | CpalErrorKind::HostUnavailable => {
                    tracing::warn!(error = %e, "audio output lost");
                    lost.store(true, Ordering::Relaxed);
                }
                CpalErrorKind::Xrun => tracing::debug!(error = %e, "audio output xrun"),
                _ => tracing::warn!(error = %e, "audio output error"),
            };
            let mut sink = DeviceSinkBuilder::from_default_device()
                .and_then(|b| b.with_error_callback(on_error).open_sink_or_fallback())
                .map_err(|e| format!("no audio output device: {e}"))?;
            sink.log_on_drop(false);
            self.output = Some(sink);
        }
        let output = self.output.as_ref().expect("opened above");
        Ok(rodio::Player::connect_new(output.mixer()))
    }

    fn tick(&mut self) {
        if self.output.is_some() && self.output_lost.load(Ordering::Relaxed) {
            // Drop the dead stream; the next play reopens the (new) default device.
            self.track = None;
            self.output = None;
            self.is_playing = false;
            self.error = Some("Audio output device was lost".into());
            self.publish();
            return;
        }
        let Some(track) = &self.track else { return };
        let position = track.get_pos();
        let finished = track.empty();
        self.position
            .send_if_modified(|p| std::mem::replace(p, position) != position);
        self.maybe_scrobble(position);
        if finished {
            self.on_completed();
        }
    }

    fn maybe_scrobble(&mut self, position: Duration) {
        if self.scrobbled || !should_scrobble(position, self.duration) {
            return;
        }
        let Some(song) = self.queue.current() else {
            return;
        };
        self.scrobbled = true;
        self.scrobble(song.id.clone(), true);
    }

    fn on_completed(&mut self) {
        self.track = None;
        match self.queue.on_completed() {
            // Each repeat-one loop is a fresh playback in Last.fm terms:
            // start_current resets the scrobble flag and re-sends now-playing.
            CompletionAction::ReplayCurrent | CompletionAction::PlayCurrent => self.start_current(),
            CompletionAction::Finished => {
                self.is_playing = false;
                self.publish();
            }
        }
    }

    /// Best-effort side channel: failures are logged, never surfaced.
    fn scrobble(&self, song_id: String, submission: bool) {
        let sink = self.scrobbler.clone();
        self.runtime.spawn(async move {
            if let Err(e) = sink.scrobble(&song_id, submission, None).await {
                tracing::warn!(%song_id, submission, error = %e, "scrobble failed");
            }
        });
    }

    fn publish(&self) {
        let next = PlaybackState {
            current_song: self.queue.current().cloned(),
            queue: self.queue.queue().clone(),
            current_index: self.queue.index(),
            is_playing: self.is_playing,
            is_buffering: self.is_buffering,
            duration: self.duration,
            volume: self.volume,
            is_shuffled: self.queue.is_shuffled(),
            repeat_mode: self.queue.repeat(),
            error_message: self.error.clone(),
        };
        self.state.send_if_modified(|s| {
            if *s == next {
                false
            } else {
                *s = next;
                true
            }
        });
    }
}
