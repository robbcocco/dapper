import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/datasources/remote/spotify_scraper.dart';
import '../../domain/models/song.dart';
import '../library/library_notifier.dart';
import '../providers/providers.dart';
import 'song_matcher.dart';
import 'spotify_import_state.dart';

class SpotifyImportNotifier extends Notifier<SpotifyImportState> {
  SpotifyImportNotifier({PlaylistScraper? scraper}) : _injected = scraper;

  /// Optional test/override scraper. When null, the notifier picks one
  /// automatically per-URL via [PlaylistScraper.detect].
  final PlaylistScraper? _injected;

  @override
  SpotifyImportState build() => const ImportIdle();

  /// Resets back to the URL-entry screen.
  void reset() {
    state = const ImportIdle();
  }

  /// Scrapes a Spotify playlist URL and matches every track against the
  /// active Navidrome library. Drops the user on the review screen.
  Future<void> startImport(String urlOrId) async {
    final repo = ref.read(libraryRepositoryProvider);
    if (repo == null) {
      state = const ImportError(
          'Connect a Navidrome server first, then try again.');
      return;
    }

    final scraper = _injected ?? PlaylistScraper.detect(urlOrId);
    if (scraper == null) {
      state = const ImportError(
          'That link is not from a supported provider. Paste a Spotify '
          'or Tidal playlist URL.');
      return;
    }

    state = const ImportScraping();
    try {
      final playlist = await scraper.fetchPlaylist(urlOrId);
      state = ImportMatching(
        playlistName: playlist.name,
        done: 0,
        total: playlist.tracks.length,
      );

      final matcher = SongMatcher(repo);
      final matches = <TrackMatch>[];
      for (var i = 0; i < playlist.tracks.length; i++) {
        final m = await matcher.match(playlist.tracks[i]);
        matches.add(m);
        state = ImportMatching(
          playlistName: playlist.name,
          done: i + 1,
          total: playlist.tracks.length,
        );
      }

      state = ImportReview(
        playlistName: playlist.name,
        truncated: playlist.truncated,
        matches: matches,
      );
    } on SpotifyScrapeException catch (e) {
      state = ImportError(e.message);
    } catch (e) {
      state = ImportError('Unexpected error: $e');
    }
  }

  /// User picked a specific Subsonic song for the [matchIndex]'th track.
  /// Passing null clears the selection (= "skip this track"). When [song]
  /// came from a manual search and isn't already in the candidate list,
  /// it is prepended so the UI can render the title/artist for it.
  void setSelection(int matchIndex, String? songId, {Song? song}) {
    final current = state;
    if (current is! ImportReview) return;
    final matches = [...current.matches];
    final m = matches[matchIndex];
    var candidates = m.candidates;
    if (song != null &&
        !candidates.any((c) => c.song.id == song.id)) {
      // Insert at the top with score 1.0 so the user's manual pick wins
      // any future auto-rank display.
      candidates = [RankedSong(song: song, score: 1.0), ...candidates];
      matches[matchIndex] = TrackMatch(
        source: m.source,
        candidates: candidates,
        bestScore: 1.0,
        selectedId: songId,
      );
    } else {
      m.selectedId = songId;
    }
    state = ImportReview(
      playlistName: current.playlistName,
      truncated: current.truncated,
      matches: matches,
    );
  }

  /// Manually overrides a candidate list for one track — used when the
  /// user types a custom search query on the review screen.
  Future<List<Song>> manualSearch(String query) async {
    final repo = ref.read(libraryRepositoryProvider);
    if (repo == null || query.trim().isEmpty) return const [];
    try {
      return await repo.search(query);
    } catch (_) {
      return const [];
    }
  }

  /// Sends the final playlist (everything with `selectedId != null`) to
  /// Navidrome. Uses [name] when supplied, otherwise the original Spotify
  /// playlist name.
  Future<void> commitImport({String? name}) async {
    final current = state;
    if (current is! ImportReview) return;

    final repo = ref.read(libraryRepositoryProvider);
    if (repo == null) {
      state = const ImportError(
          'Lost connection to the Navidrome server. Reconnect and try again.');
      return;
    }

    final songIds = <String>[];
    for (final m in current.matches) {
      final id = m.selectedId;
      if (id != null) songIds.add(id);
    }
    if (songIds.isEmpty) {
      state = const ImportError(
          'No songs are selected — nothing to send to Navidrome.');
      return;
    }

    state = const ImportCreating();
    try {
      await repo.createPlaylist(name ?? current.playlistName,
          songIds: songIds);
      // Refresh the sidebar's playlist list so the new entry shows up.
      ref.invalidate(playlistsProvider);
      state = ImportDone(
        playlistName: name ?? current.playlistName,
        importedCount: songIds.length,
        skippedCount: current.matches.length - songIds.length,
      );
    } catch (e) {
      state = ImportError('Could not create the playlist: $e');
    }
  }
}

final spotifyImportProvider =
    NotifierProvider<SpotifyImportNotifier, SpotifyImportState>(
  SpotifyImportNotifier.new,
);
