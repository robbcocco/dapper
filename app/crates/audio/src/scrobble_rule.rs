use std::time::Duration;

/// Last.fm rule (honoured by Navidrome when forwarding upstream): tracks under
/// 30 s never scrobble; otherwise scrobble once past 50% or 4 minutes,
/// whichever comes first. Zero duration means progress can't be gauged.
pub fn should_scrobble(position: Duration, duration: Duration) -> bool {
    if duration.is_zero() || duration < Duration::from_secs(30) {
        return false;
    }
    if position >= Duration::from_secs(4 * 60) {
        return true;
    }
    // Compare in microseconds (like the Dart port) so odd-millisecond
    // durations don't round the half-way mark down.
    position.as_micros() * 2 >= duration.as_micros()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn secs(s: u64) -> Duration {
        Duration::from_secs(s)
    }

    #[test]
    fn zero_duration_is_false() {
        assert!(!should_scrobble(secs(30), Duration::ZERO));
    }

    #[test]
    fn short_track_never_scrobbles_even_when_fully_played() {
        assert!(!should_scrobble(secs(20), secs(20)));
    }

    #[test]
    fn exactly_30s_track_is_eligible() {
        assert!(should_scrobble(secs(16), secs(30)));
    }

    #[test]
    fn below_half_is_false() {
        assert!(!should_scrobble(secs(90), secs(240)));
    }

    #[test]
    fn exactly_half_is_true() {
        assert!(should_scrobble(secs(120), secs(240)));
    }

    #[test]
    fn above_half_is_true() {
        assert!(should_scrobble(secs(121), secs(240)));
    }

    #[test]
    fn long_track_scrobbles_at_four_minutes_below_half() {
        assert!(should_scrobble(secs(240), secs(720)));
    }

    #[test]
    fn just_under_four_minutes_on_long_track_is_false() {
        assert!(!should_scrobble(secs(239), secs(720)));
    }

    #[test]
    fn thirty_minute_epic_scrobbles_at_four_minutes_not_fifteen() {
        assert!(should_scrobble(secs(300), secs(1800)));
    }

    #[test]
    fn half_mark_uses_microsecond_precision() {
        let duration = Duration::from_secs(180) + Duration::from_millis(1);
        let half = (duration.as_micros() / 2) as u64;
        assert!(!should_scrobble(Duration::from_micros(half - 1), duration));
        assert!(should_scrobble(Duration::from_micros(half), duration));
    }
}
