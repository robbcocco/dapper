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

  /// Max concurrent library searches while matching a playlist.
  static const _matchConcurrency = 6;

  // Bumped whenever a new import starts or the user resets. Async work checks
  // it before writing state so a stale in-flight match run (e.g. after the
  // user hit "back") can't clobber the current screen.
  int _epoch = 0;

  @override
  SpotifyImportState build() => const ImportIdle();

  /// Resets back to the URL-entry screen.
  void reset() {
    _epoch++;
    state = const ImportIdle();
  }

  /// Scrapes a Spotify playlist URL and matches every track against the
  /// active Navidrome library. Drops the user on the review screen.
  Future<void> startImport(String urlOrId) async {
    final epoch = ++_epoch;
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
      if (epoch != _epoch) return;
      final total = playlist.tracks.length;
      state = ImportMatching(
        playlistName: playlist.name,
        done: 0,
        total: total,
      );

      // Match in bounded-parallel — SongMatcher is stateless, so several
      // library searches can run at once instead of one sequential round-trip
      // per track. Results are written to their original index to preserve
      // playlist order.
      final matcher = SongMatcher(repo);
      final matches = List<TrackMatch?>.filled(total, null);
      var done = 0;
      var cursor = 0;
      Future<void> worker() async {
        while (true) {
          final i = cursor++;
          if (i >= total) break;
          final m = await matcher.match(playlist.tracks[i]);
          if (epoch != _epoch) return;
          matches[i] = m;
          done++;
          state = ImportMatching(
            playlistName: playlist.name,
            done: done,
            total: total,
          );
        }
      }

      await Future.wait([
        for (var w = 0; w < _matchConcurrency; w++) worker(),
      ]);
      if (epoch != _epoch) return;

      state = ImportReview(
        playlistName: playlist.name,
        truncated: playlist.truncated,
        matches: [for (final m in matches) m!],
      );
    } on SpotifyScrapeException catch (e) {
      if (epoch != _epoch) return;
      state = ImportError(e.message);
    } catch (e) {
      if (epoch != _epoch) return;
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
