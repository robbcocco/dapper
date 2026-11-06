use std::sync::Arc;
use std::time::Duration;

use dapper_domain::{RepeatMode, Song};
use rand::Rng;
use rand::seq::SliceRandom;

/// What `previous` asks the output engine to do.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PreviousAction {
    /// More than 3 s in: restart the current track instead of moving back.
    SeekToStart,
    /// The index moved; load and play the new current song.
    PlayCurrent,
    /// At the head of the queue without repeat-all: nothing to do.
    None,
}

/// What the output engine does once the current track has played to the end.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum CompletionAction {
    /// Repeat-one: replay the current song as a fresh playback.
    ReplayCurrent,
    /// The index advanced (or wrapped under repeat-all); play the new current song.
    PlayCurrent,
    /// End of the queue: stop.
    Finished,
}

/// Pure queue / navigation state of the player: ordering, shuffle, repeat.
#[derive(Debug, Clone, Default)]
pub struct PlayQueue {
    queue: Arc<[Song]>,
    index: usize,
    /// Pre-shuffle order; `Some` exactly while shuffled.
    original: Option<Arc<[Song]>>,
    repeat: RepeatMode,
}

impl PlayQueue {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn queue(&self) -> &Arc<[Song]> {
        &self.queue
    }

    pub fn index(&self) -> usize {
        self.index
    }

    pub fn current(&self) -> Option<&Song> {
        self.queue.get(self.index)
    }

    pub fn is_shuffled(&self) -> bool {
        self.original.is_some()
    }

    pub fn repeat(&self) -> RepeatMode {
        self.repeat
    }

    pub fn has_previous(&self) -> bool {
        self.index > 0 || self.repeat == RepeatMode::All
    }

    pub fn has_next(&self) -> bool {
        self.index + 1 < self.queue.len() || self.repeat == RepeatMode::All
    }

    /// Replaces the queue and starts at `start` (clamped into range). A new
    /// queue always drops shuffle and its saved original order.
    pub fn set_queue(&mut self, songs: Vec<Song>, start: usize) {
        self.index = start.min(songs.len().saturating_sub(1));
        self.queue = songs.into();
        self.original = None;
    }

    /// Plays a single song as its own queue (same reset rules as `set_queue`).
    pub fn play_song(&mut self, song: Song) {
        self.set_queue(vec![song], 0);
    }

    pub fn clear(&mut self) {
        self.set_queue(Vec::new(), 0);
    }

    /// Moves to the next song, wrapping under repeat-all. Returns whether the
    /// index moved (i.e. the new current song should be played).
    pub fn advance(&mut self) -> bool {
        if self.index + 1 < self.queue.len() {
            self.index += 1;
            true
        } else if self.repeat == RepeatMode::All && !self.queue.is_empty() {
            self.index = 0;
            true
        } else {
            false
        }
    }

    /// `position` is the playback position of the current song.
    pub fn previous(&mut self, position: Duration) -> PreviousAction {
        if position.as_secs() > 3 {
            PreviousAction::SeekToStart
        } else if self.index > 0 {
            self.index -= 1;
            PreviousAction::PlayCurrent
        } else if self.repeat == RepeatMode::All && !self.queue.is_empty() {
            self.index = self.queue.len() - 1;
            PreviousAction::PlayCurrent
        } else {
            PreviousAction::None
        }
    }

    pub fn on_completed(&mut self) -> CompletionAction {
        if self.repeat == RepeatMode::One {
            CompletionAction::ReplayCurrent
        } else if self.advance() {
            CompletionAction::PlayCurrent
        } else {
            CompletionAction::Finished
        }
    }

    /// Shuffling keeps the current song first and saves the original order;
    /// un-shuffling restores it and re-locates the current song by id.
    pub fn toggle_shuffle<R: Rng + ?Sized>(&mut self, rng: &mut R) {
        let current = self.current().cloned();
        if let Some(original) = self.original.take() {
            self.index = current
                .and_then(|c| original.iter().position(|s| s.id == c.id))
                .unwrap_or(0);
            self.queue = original;
        } else {
            let mut rest: Vec<Song> = self
                .queue
                .iter()
                .filter(|s| current.as_ref().is_none_or(|c| s.id != c.id))
                .cloned()
                .collect();
            rest.shuffle(rng);
            let shuffled: Vec<Song> = current.into_iter().chain(rest).collect();
            self.original = Some(std::mem::replace(&mut self.queue, shuffled.into()));
            self.index = 0;
        }
    }

    /// none → all → one → none.
    pub fn cycle_repeat(&mut self) -> RepeatMode {
        self.repeat = match self.repeat {
            RepeatMode::None => RepeatMode::All,
            RepeatMode::All => RepeatMode::One,
            RepeatMode::One => RepeatMode::None,
        };
        self.repeat
    }
}

#[cfg(test)]
mod tests {
    use rand::SeedableRng;
    use rand::rngs::StdRng;

    use super::*;

    fn song(id: &str) -> Song {
        Song {
            id: id.into(),
            title: id.into(),
            ..Song::default()
        }
    }

    fn songs(ids: &[&str]) -> Vec<Song> {
        ids.iter().map(|id| song(id)).collect()
    }

    fn ids(q: &PlayQueue) -> Vec<&str> {
        q.queue().iter().map(|s| s.id.as_str()).collect()
    }

    fn queue_of(ids: &[&str], start: usize) -> PlayQueue {
        let mut q = PlayQueue::new();
        q.set_queue(songs(ids), start);
        q
    }

    #[test]
    fn set_queue_selects_start_and_clamps() {
        let q = queue_of(&["a", "b", "c"], 1);
        assert_eq!(q.current().unwrap().id, "b");
        let q = queue_of(&["a", "b"], 9);
        assert_eq!(q.index(), 1);
        let q = queue_of(&[], 3);
        assert_eq!(q.index(), 0);
        assert!(q.current().is_none());
    }

    #[test]
    fn next_stops_at_end_without_repeat() {
        let mut q = queue_of(&["a", "b"], 0);
        assert!(q.advance());
        assert_eq!(q.index(), 1);
        assert!(!q.advance());
        assert_eq!(q.index(), 1);
    }

    #[test]
    fn next_wraps_under_repeat_all() {
        let mut q = queue_of(&["a", "b"], 1);
        q.cycle_repeat();
        assert!(q.advance());
        assert_eq!(q.index(), 0);
    }

    #[test]
    fn next_on_empty_queue_is_noop_even_with_repeat_all() {
        let mut q = PlayQueue::new();
        q.cycle_repeat();
        assert!(!q.advance());
    }

    #[test]
    fn previous_restarts_after_three_seconds() {
        let mut q = queue_of(&["a", "b"], 1);
        assert_eq!(
            q.previous(Duration::from_secs(4)),
            PreviousAction::SeekToStart
        );
        assert_eq!(q.index(), 1);
        // Whole seconds, like Dart's `inSeconds > 3`.
        assert_eq!(
            q.previous(Duration::from_millis(3999)),
            PreviousAction::PlayCurrent
        );
        assert_eq!(q.index(), 0);
    }

    #[test]
    fn previous_at_head_wraps_only_under_repeat_all() {
        let mut q = queue_of(&["a", "b", "c"], 0);
        assert_eq!(q.previous(Duration::ZERO), PreviousAction::None);
        q.cycle_repeat();
        assert_eq!(q.previous(Duration::ZERO), PreviousAction::PlayCurrent);
        assert_eq!(q.index(), 2);
    }

    #[test]
    fn repeat_cycles_none_all_one_none() {
        let mut q = PlayQueue::new();
        assert_eq!(q.repeat(), RepeatMode::None);
        assert_eq!(q.cycle_repeat(), RepeatMode::All);
        assert_eq!(q.cycle_repeat(), RepeatMode::One);
        assert_eq!(q.cycle_repeat(), RepeatMode::None);
    }

    #[test]
    fn completion_advances_wraps_replays_and_finishes() {
        let mut q = queue_of(&["a", "b"], 0);
        assert_eq!(q.on_completed(), CompletionAction::PlayCurrent);
        assert_eq!(q.index(), 1);
        assert_eq!(q.on_completed(), CompletionAction::Finished);
        assert_eq!(q.index(), 1);

        q.cycle_repeat(); // all
        assert_eq!(q.on_completed(), CompletionAction::PlayCurrent);
        assert_eq!(q.index(), 0);

        q.cycle_repeat(); // one
        assert_eq!(q.on_completed(), CompletionAction::ReplayCurrent);
        assert_eq!(q.index(), 0);
    }

    #[test]
    fn has_next_and_previous_follow_dart_getters() {
        let mut q = queue_of(&["a", "b"], 0);
        assert!(!q.has_previous());
        assert!(q.has_next());
        q.advance();
        assert!(q.has_previous());
        assert!(!q.has_next());
        q.cycle_repeat();
        assert!(q.has_next());
    }

    #[test]
    fn shuffle_keeps_current_first_and_restores_original_order() {
        let mut rng = StdRng::seed_from_u64(7);
        let mut q = queue_of(&["a", "b", "c", "d", "e", "f"], 2);
        q.toggle_shuffle(&mut rng);
        assert!(q.is_shuffled());
        assert_eq!(q.index(), 0);
        assert_eq!(q.current().unwrap().id, "c");
        let mut sorted = ids(&q);
        sorted.sort_unstable();
        assert_eq!(sorted, ["a", "b", "c", "d", "e", "f"]);

        // Move within the shuffled queue; un-shuffling finds that song again.
        q.advance();
        let playing = q.current().unwrap().id.clone();
        q.toggle_shuffle(&mut rng);
        assert!(!q.is_shuffled());
        assert_eq!(ids(&q), ["a", "b", "c", "d", "e", "f"]);
        assert_eq!(q.current().unwrap().id, playing);
    }

    #[test]
    fn navigation_keeps_shuffle() {
        let mut rng = StdRng::seed_from_u64(1);
        let mut q = queue_of(&["a", "b", "c"], 0);
        q.toggle_shuffle(&mut rng);
        q.advance();
        q.on_completed();
        q.previous(Duration::ZERO);
        assert!(q.is_shuffled());
    }

    #[test]
    fn new_queue_resets_saved_original_order() {
        let mut rng = StdRng::seed_from_u64(3);
        let mut q = queue_of(&["a", "b", "c"], 0);
        q.toggle_shuffle(&mut rng);
        q.set_queue(songs(&["x", "y", "z"]), 1);
        assert!(!q.is_shuffled());
        assert_eq!(ids(&q), ["x", "y", "z"]);
        // Shuffling the new queue and back must restore *this* queue, not the old one.
        q.toggle_shuffle(&mut rng);
        q.toggle_shuffle(&mut rng);
        assert_eq!(ids(&q), ["x", "y", "z"]);
        assert_eq!(q.current().unwrap().id, "y");

        q.toggle_shuffle(&mut rng);
        q.play_song(song("solo"));
        assert!(!q.is_shuffled());
        q.toggle_shuffle(&mut rng);
        q.toggle_shuffle(&mut rng);
        assert_eq!(ids(&q), ["solo"]);
    }

    #[test]
    fn unshuffle_falls_back_to_first_when_current_missing() {
        let mut rng = StdRng::seed_from_u64(5);
        let mut q = PlayQueue::new();
        q.toggle_shuffle(&mut rng);
        assert!(q.is_shuffled());
        assert!(q.queue().is_empty());
        q.toggle_shuffle(&mut rng);
        assert!(!q.is_shuffled());
        assert_eq!(q.index(), 0);
    }

    #[test]
    fn shuffle_drops_other_copies_of_current_song_like_dart() {
        let mut rng = StdRng::seed_from_u64(9);
        let mut q = queue_of(&["a", "b", "a"], 0);
        q.toggle_shuffle(&mut rng);
        assert_eq!(q.queue().len(), 2);
        q.toggle_shuffle(&mut rng);
        assert_eq!(ids(&q), ["a", "b", "a"]);
    }
}
