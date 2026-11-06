import '../../../../../lib/application/spotify_import/song_matcher.dart';
import '../../../../../lib/domain/models/song.dart';
import '../../../../../lib/domain/models/spotify_track.dart';
import '../../../../../lib/domain/repositories/library_repository.dart';
import 'common.dart';
import 'corpus.dart';

/// Returns the configured hits for whatever query SongMatcher builds and
/// records that query. Every other repository method is unreachable.
class _FakeRepo implements LibraryRepository {
  _FakeRepo(this.hits, {this.throws = false});
  final List<Song> hits;
  final bool throws;
  String? lastQuery;

  @override
  Future<List<Song>> search(String query) async {
    lastQuery = query;
    if (throws) throw StateError('search failed');
    return hits;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('unexpected ${invocation.memberName}');
}

Song _c(String id, String title,
        {String? artist, String? albumArtist, int? duration}) =>
    Song(id: id, title: title, artist: artist, albumArtist: albumArtist, duration: duration);

Future<void> songMatcher() async {
  final sets = <(SpotifyTrack, List<Song>, bool)>[
    (
      const SpotifyTrack(title: 'Song', artist: 'Artist', durationMs: 200000),
      [
        _c('exact', 'Song', artist: 'Artist', duration: 200),
        _c('live', 'Song (Live)', artist: 'Artist', duration: 260),
        _c('remaster', 'Song - Remastered 2011', artist: 'Artist', duration: 201),
        _c('other-artist', 'Song', artist: 'Someone Else', duration: 200),
        _c('off5', 'Song', artist: 'Artist', duration: 205),
        _c('off10', 'Song', artist: 'Artist', duration: 210),
        _c('off40', 'Song', artist: 'Artist', duration: 240),
        _c('unrelated', 'Completely Different', artist: 'Nobody', duration: 200),
      ],
      false
    ),
    (
      const SpotifyTrack(title: 'Title (feat. Guest)', artist: 'Main, Guest', durationMs: 180500),
      [
        _c('plain', 'Title', artist: 'Main', duration: 180),
        _c('feat', 'Title (feat. Guest)', artist: 'Main', duration: 183),
        _c('bracket', 'Title [Remastered]', artist: 'Main feat. Guest', duration: 188),
        _c('aa', 'Title', albumArtist: 'Main', duration: 189),
        _c('noartist', 'Title', duration: 180),
        _c('nodur', 'Title', artist: 'Main'),
      ],
      false
    ),
    (
      const SpotifyTrack(title: 'Café', artist: 'Beyoncé & Jay-Z', durationMs: 1000),
      [
        _c('nfc', 'Café', artist: 'Beyoncé', duration: 1),
        _c('nfd', 'Cafe\u0301', artist: 'Beyonce\u0301', duration: 1),
        _c('ascii', 'Cafe', artist: 'Beyonce', duration: 4),
        _c('upper', 'CAFÉ', artist: 'BEYONCÉ & JAY-Z', duration: 9),
      ],
      false
    ),
    (
      const SpotifyTrack(title: 'İstanbul (Not Constantinople)', artist: 'They Might Be Giants'),
      [
        _c('i1', 'Istanbul (Not Constantinople)', artist: 'They Might Be Giants'),
        _c('i2', 'istanbul', artist: 'they might be giants'),
        _c('i3', 'İSTANBUL', artist: 'They Might Be Giants'),
        _c('i4', 'i̇stanbul', artist: 'They Might Be Giants'),
      ],
      false
    ),
    (
      const SpotifyTrack(title: '坂本龍一 Merry Christmas Mr. Lawrence', artist: '坂本龍一', durationMs: 290000),
      [
        _c('cjk1', 'Merry Christmas Mr. Lawrence', artist: '坂本龍一', duration: 291),
        _c('cjk2', '戦場のメリークリスマス', artist: '坂本龍一', duration: 290),
        _c('cjk3', 'Merry Christmas, Mr. Lawrence', artist: 'Ryuichi Sakamoto', duration: 300),
      ],
      false
    ),
    (
      const SpotifyTrack(title: '🎵🎵', artist: '!!!', durationMs: 60000),
      [
        _c('e1', '🎵🎵', artist: '!!!', duration: 60),
        _c('e2', 'Music', artist: 'Chk Chk Chk', duration: 60),
      ],
      false
    ),
    (
      const SpotifyTrack(title: '1979', artist: 'The Smashing Pumpkins', durationMs: 266000),
      [
        _c('n1', '1979', artist: 'The Smashing Pumpkins', duration: 266),
        _c('n2', '1979 (Remastered 2012)', artist: 'Smashing Pumpkins', duration: 266),
        _c('n3', '١٩٧٩', artist: 'The Smashing Pumpkins', duration: 266),
        _c('n4', '1979 1979', artist: 'The The', duration: 100),
      ],
      false
    ),
    (
      const SpotifyTrack(title: 'Unclosed (feat. X', artist: 'A & B, C', durationMs: 120000),
      [
        _c('u1', 'Unclosed', artist: 'A', duration: 120),
        _c('u2', 'Unclosed (feat. X', artist: 'A & B, C', duration: 120),
        _c('u3', 'Unclosed feat X', artist: 'A B C', duration: 121),
      ],
      false
    ),
    (
      const SpotifyTrack(title: 'Ties', artist: 'Same', durationMs: 100000),
      [
        _c('t1', 'Ties', artist: 'Same', duration: 100),
        _c('t2', 'Ties', artist: 'Same', duration: 100),
        _c('t3', 'Ties', artist: 'Same', duration: 101),
        _c('t4', 'Ties!', artist: 'Same.', duration: 99),
        _c('t5', 'ties', artist: 'same', duration: 100),
      ],
      false
    ),
    (
      const SpotifyTrack(title: '', artist: '', durationMs: 0),
      [_c('empty', '', artist: '', duration: 0), _c('x', 'X', artist: 'Y', duration: 0)],
      false
    ),
    (
      const SpotifyTrack(title: '...', artist: '---', durationMs: 5000),
      [_c('p1', '...', artist: '---', duration: 5), _c('p2', '…', artist: '—', duration: 5)],
      false
    ),
    (
      const SpotifyTrack(title: '\u00a0Spaced\u00a0Out\u3000Title\t', artist: ' Artist ', durationMs: 150000),
      [
        _c('s1', 'Spaced Out Title', artist: 'Artist', duration: 150),
        _c('s2', 'spaced  out   title', artist: 'artist', duration: 158),
        _c('s3', 'Spaced\u200bOut Title', artist: 'Artist', duration: 141),
      ],
      false
    ),
    (
      const SpotifyTrack(title: 'Thrown', artist: 'Error', durationMs: 1),
      [_c('never', 'Thrown', artist: 'Error', duration: 1)],
      true
    ),
    (
      const SpotifyTrack(title: 'Nothing Found', artist: 'Ghost'),
      [],
      false
    ),
    (
      const SpotifyTrack(title: 'Many', artist: 'Candidates', durationMs: 200000),
      [
        for (var i = 0; i < 20; i++)
          _c('m$i', i.isEven ? 'Many' : 'Many Version $i', artist: i % 3 == 0 ? 'Candidates' : 'Candidate', duration: 200 + i * 3),
      ],
      false
    ),
    (
      const SpotifyTrack(title: 'Long Duration Edge', artist: 'Edge', durationMs: 203000),
      [
        _c('d0', 'Long Duration Edge', artist: 'Edge', duration: 200),
        _c('d1', 'Long Duration Edge', artist: 'Edge', duration: 195),
        _c('d2', 'Long Duration Edge', artist: 'Edge', duration: 211),
        _c('d3', 'Long Duration Edge', artist: 'Edge', duration: 233),
        _c('d4', 'Long Duration Edge', artist: 'Edge', duration: 234),
        _c('d5', 'Long Duration Edge', artist: 'Edge', duration: 172),
        _c('d6', 'Long Duration Edge', artist: 'Edge', duration: -5),
      ],
      false
    ),
    (
      const SpotifyTrack(title: 'Half Second', artist: 'Ms', durationMs: 203500),
      [
        _c('h1', 'Half Second', artist: 'Ms', duration: 200),
        _c('h2', 'Half Second', artist: 'Ms', duration: 207),
        _c('h3', 'Half Second', artist: 'Ms', duration: 211),
        _c('h4', 'Half Second', artist: 'Ms', duration: 234),
      ],
      false
    ),
  ];

  // Seeded fuzz over a small word bank so token overlaps are frequent.
  const words = [
    'love', 'Love', 'night', 'NIGHT', '(live)', '[demo]', 'feat.', 'the', 'The',
    'à', 'deux', '2', 'two', 'Ⅱ', 'Σ', 'σ', 'ς', '—', '&', ',', 'remix', 'İ', 'i',
  ];
  final rnd = seeded(20);
  String phrase() =>
      [for (var i = rnd.nextInt(5) + 1; i > 0; i--) words[rnd.nextInt(words.length)]].join(' ');
  for (var n = 0; n < 60; n++) {
    final track = SpotifyTrack(
        title: phrase(),
        artist: phrase(),
        durationMs: rnd.nextBool() ? 120000 + rnd.nextInt(90000) : null);
    final cands = [
      for (var i = rnd.nextInt(10) + 1; i > 0; i--)
        _c('f$n-$i', phrase(),
            artist: rnd.nextInt(4) == 0 ? null : phrase(),
            albumArtist: rnd.nextBool() ? phrase() : null,
            duration: rnd.nextBool() ? 100 + rnd.nextInt(150) : null),
    ];
    sets.add((track, cands, false));
  }

  final cases = <Case>[];
  for (final (track, hits, throws) in sets) {
    final input = {
      'track': {
        'title': track.title,
        'artist': track.artist,
        'album': track.album,
        'durationMs': track.durationMs,
      },
      'searchResults': [for (final s in hits) songToJson(s)],
      'searchThrows': throws,
    };
    final repo = _FakeRepo(hits, throws: throws);
    cases.add(await runAsync(input, () async {
      final m = await SongMatcher(repo).match(track);
      return {
        'query': repo.lastQuery,
        'candidates': [
          for (final c in m.candidates) {'id': c.song.id, 'score': c.score}
        ],
        'bestScore': m.bestScore,
        'selectedId': m.selectedId,
      };
    }));
  }

  writeFixture(
    'song_matcher',
    'SongMatcher.match (lib/application/spotify_import/song_matcher.dart) with a fake repository whose '
        'search(query) returns input.searchResults (or throws when searchThrows). input {track: {title, artist, '
        'album, durationMs}, searchResults: [Song], searchThrows} → output {query: string passed to search, '
        'candidates: [{id, score}] (score>0 only, descending, max 8; equal scores keep search order — Dart '
        'insertion sort, ≤32 hits), bestScore (0.0 when none), selectedId (best id when bestScore >= 0.78)}. '
        'Scores are IEEE doubles; reproduce the exact operation order for bit-identical results.',
    cases,
  );
}
