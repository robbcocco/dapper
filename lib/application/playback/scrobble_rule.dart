/// Pure decision logic for when to send a full Subsonic scrobble
/// (`submission=true`). Extracted from [PlaybackNotifier] so the rule can be
/// unit-tested without standing up an `AudioPlayer`.
///
/// Follows the de-facto Last.fm rule, which Navidrome and friends honour
/// when they forward scrobbles upstream:
///   - The track must be at least 30 seconds long (anything shorter is
///     considered a snippet / sound effect and never scrobbled).
///   - Then scrobble once we've played past 50% **or** past 4 minutes,
///     whichever comes first.
///
/// Returns false on missing / zero duration since we have no way to gauge
/// progress. The 4-minute cap is a hard floor used for long tracks where
/// 50% would take ages to reach.
bool shouldScrobble({
  required Duration position,
  required Duration duration,
}) {
  if (duration <= Duration.zero) return false;
  if (duration < const Duration(seconds: 30)) return false;
  if (position >= const Duration(minutes: 4)) return true;
  // 50% of duration. Compute in microseconds to dodge integer truncation
  // on odd-millisecond durations.
  return position.inMicroseconds * 2 >= duration.inMicroseconds;
}
