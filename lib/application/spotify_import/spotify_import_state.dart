import '../../domain/models/spotify_track.dart';
import 'song_matcher.dart';

sealed class SpotifyImportState {
  const SpotifyImportState();
}

class ImportIdle extends SpotifyImportState {
  const ImportIdle();
}

class ImportScraping extends SpotifyImportState {
  const ImportScraping();
}

class ImportMatching extends SpotifyImportState {
  const ImportMatching({
    required this.playlistName,
    required this.done,
    required this.total,
  });
  final String playlistName;
  final int done;
  final int total;
}

class ImportReview extends SpotifyImportState {
  const ImportReview({
    required this.playlistName,
    required this.truncated,
    required this.matches,
  });
  final String playlistName;
  final bool truncated;
  final List<TrackMatch> matches;

  int get autoMatchedCount =>
      matches.where((m) => m.selectedId != null).length;
  int get unmatchedCount =>
      matches.where((m) => m.selectedId == null).length;
}

class ImportCreating extends SpotifyImportState {
  const ImportCreating();
}

class ImportDone extends SpotifyImportState {
  const ImportDone({
    required this.playlistName,
    required this.importedCount,
    required this.skippedCount,
  });
  final String playlistName;
  final int importedCount;
  final int skippedCount;
}

class ImportError extends SpotifyImportState {
  const ImportError(this.message, {this.tracks});
  final String message;

  /// Set when the error happened after scraping succeeded — exposed so the
  /// UI can show what was found before the failure.
  final List<SpotifyTrack>? tracks;
}
