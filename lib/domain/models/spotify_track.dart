/// One track lifted from an external playlist (Spotify, Tidal, …). The
/// class kept its Spotify-flavoured name when Tidal support was bolted on
/// to avoid churning every caller; treat it as a provider-neutral DTO.
class SpotifyTrack {
  const SpotifyTrack({
    required this.title,
    required this.artist,
    this.album,
    this.durationMs,
  });

  final String title;
  final String artist;

  /// Album the track belongs to, when the source exposes it. Spotify's
  /// embed payload doesn't — Tidal's API does. Used to seed the Lidarr
  /// "add album" search.
  final String? album;

  final int? durationMs;

  @override
  String toString() => '$artist — $title';
}

enum PlaylistProvider { spotify, tidal }

class SpotifyPlaylistData {
  const SpotifyPlaylistData({
    required this.name,
    required this.tracks,
    required this.truncated,
    required this.provider,
  });

  final String name;
  final List<SpotifyTrack> tracks;

  /// True when the source only returned a partial track list (e.g. the
  /// Spotify embed caps at ~100 tracks). UI surfaces this so the user
  /// knows the resulting Navidrome playlist may be incomplete.
  final bool truncated;

  final PlaylistProvider provider;
}
