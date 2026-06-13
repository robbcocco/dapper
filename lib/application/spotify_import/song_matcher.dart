import '../../domain/models/song.dart';
import '../../domain/models/spotify_track.dart';
import '../../domain/repositories/library_repository.dart';

/// Result of trying to match one Spotify track against the Navidrome library.
class TrackMatch {
  TrackMatch({
    required this.source,
    required this.candidates,
    required this.bestScore,
    this.selectedId,
  });

  final SpotifyTrack source;

  /// Up to N candidates from Subsonic search, ranked by descending score.
  /// First element is the highest-scoring candidate.
  final List<RankedSong> candidates;

  /// Score of the best candidate (`candidates.first.score`) or 0 if no
  /// candidates were returned. Cached so the UI can show it without
  /// re-walking the list.
  final double bestScore;

  /// Either an auto-picked candidate (score ≥ autoMatchThreshold) or a
  /// manual override picked by the user. Null means "skip this track".
  String? selectedId;
}

class RankedSong {
  const RankedSong({required this.song, required this.score});
  final Song song;
  final double score;
}

class SongMatcher {
  SongMatcher(this._repo);

  final LibraryRepository _repo;

  /// Above this combined score we auto-pick the best candidate. Tuned for
  /// the simple Jaccard+duration scorer below — a perfect title+artist
  /// match with a duration within 5 s lands around 0.95.
  static const double autoMatchThreshold = 0.78;

  /// Searches Subsonic for [track] and returns the ranked candidate list.
  /// On any error returns an empty match so the UI can flag it for manual
  /// resolution instead of aborting the whole import.
  Future<TrackMatch> match(SpotifyTrack track) async {
    final query = _buildQuery(track);
    List<Song> hits;
    try {
      hits = await _repo.search(query);
    } catch (_) {
      hits = const [];
    }

    final ranked = <RankedSong>[];
    for (final song in hits) {
      final score = _score(track, song);
      if (score > 0) ranked.add(RankedSong(song: song, score: score));
    }
    ranked.sort((a, b) => b.score.compareTo(a.score));

    final best = ranked.isEmpty ? 0.0 : ranked.first.score;
    final selected =
        best >= autoMatchThreshold ? ranked.first.song.id : null;

    return TrackMatch(
      source: track,
      candidates: ranked.take(8).toList(),
      bestScore: best,
      selectedId: selected,
    );
  }

  String _buildQuery(SpotifyTrack t) {
    // Title carries the most signal; the primary artist (before any comma)
    // narrows duplicates without polluting the query with featured-artist
    // noise that Subsonic search treats literally.
    final primaryArtist = t.artist.split(RegExp(r'[,&]')).first.trim();
    return '${t.title} $primaryArtist'.trim();
  }

  double _score(SpotifyTrack t, Song s) {
    final titleScore = _similarity(t.title, s.title);
    final artistScore = _similarity(t.artist, s.artist ?? s.albumArtist ?? '');
    // Weight title heavier than artist; without a good title nothing else
    // matters.
    var score = titleScore * 0.65 + artistScore * 0.35;
    // Duration bonus: within 3 s → +0.08, within 8 s → +0.04. Subsonic
    // duration is seconds, Spotify is ms.
    if (t.durationMs != null && s.duration != null) {
      final deltaSec = (t.durationMs! / 1000 - s.duration!).abs();
      if (deltaSec <= 3) {
        score += 0.08;
      } else if (deltaSec <= 8) {
        score += 0.04;
      } else if (deltaSec > 30) {
        // Big mismatch is a strong negative — likely a different version.
        score -= 0.15;
      }
    }
    return score.clamp(0.0, 1.0);
  }

  /// Token-Jaccard similarity on normalized strings. Cheap, dependency-free,
  /// good enough for "Song Title (feat. X) - Remastered 2011" vs library
  /// variants.
  double _similarity(String a, String b) {
    final ta = _tokens(a);
    final tb = _tokens(b);
    if (ta.isEmpty || tb.isEmpty) return 0;
    final inter = ta.intersection(tb).length;
    final union = ta.union(tb).length;
    final jaccard = inter / union;
    // Exact normalized equality bumps the score so "Song" vs "Song" beats
    // the token-only ceiling and trips autoMatchThreshold reliably.
    if (_normalize(a) == _normalize(b)) return (jaccard + 1) / 2 + 0.1;
    return jaccard;
  }

  Set<String> _tokens(String s) {
    final n = _normalize(s);
    if (n.isEmpty) return const {};
    return n.split(' ').where((t) => t.isNotEmpty).toSet();
  }

  String _normalize(String s) {
    var out = s.toLowerCase();
    // Strip parenthetical bits like "(feat. X)", "[Remastered]" — they
    // routinely differ between Spotify and a library rip.
    out = out.replaceAll(RegExp(r'\([^)]*\)'), ' ');
    out = out.replaceAll(RegExp(r'\[[^\]]*\]'), ' ');
    // Drop punctuation but keep letters, digits, and spaces (including
    // unicode letters via \p{L}).
    out = out.replaceAll(RegExp(r'[^\p{L}\p{N}\s]', unicode: true), ' ');
    out = out.replaceAll(RegExp(r'\s+'), ' ').trim();
    return out;
  }
}
