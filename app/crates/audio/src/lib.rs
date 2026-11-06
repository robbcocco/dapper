//! Pure-Rust playback engine.

mod codec;
mod engine;
mod player;
mod queue;
mod scrobble_rule;
mod stream;

pub use codec::is_natively_decodable;
pub use player::{PlaybackState, Player};
pub use queue::{CompletionAction, PlayQueue, PreviousAction};
pub use scrobble_rule::should_scrobble;
pub use stream::StreamResolver;
