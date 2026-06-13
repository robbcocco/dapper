/// A track scraped from a public Spotify playlist embed. Has only the
/// metadata the embed exposes — no Spotify ID is kept because the import
/// flow doesn't need it.
class SpotifyTrack {
  const SpotifyTrack({
    required this.title,
    required this.artist,
    this.durationMs,
  });

  final String title;
  final String artist;
  final int? durationMs;

  @override
  String toString() => '$artist — $title';
}

class SpotifyPlaylistData {
  const SpotifyPlaylistData({
    required this.name,
    required this.tracks,
    required this.truncated,
  });

  final String name;
  final List<SpotifyTrack> tracks;

  /// True when the embed only exposed a partial list (Spotify caps the
  /// embed page at ~100 tracks). UI surfaces this so the user knows the
  /// resulting Navidrome playlist may be incomplete.
  final bool truncated;
}
