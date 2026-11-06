import 'dart:convert';
import 'dart:io';

import '../../../../../lib/application/playback/scrobble_rule.dart';
import '../../../../../lib/application/transfer/device_manifest.dart';
import '../../../../../lib/application/transfer/playlist_sync_writer.dart';
import '../../../../../lib/application/transfer/transfer_path_resolver.dart';
import '../../../../../lib/core/format/byte_format.dart';
import '../../../../../lib/data/datasources/local/scrobbler_log.dart';
import '../../../../../lib/domain/models/playlist.dart';
import '../../../../../lib/domain/models/song.dart';
import '../copies/extracted.dart';
import 'common.dart';
import 'corpus.dart';

// ── manifest ────────────────────────────────────────────────────────────────

Map<String, Object?>? _manifestToJson(AlbumManifest? m) => m == null
    ? null
    : {
        'expectedSongCount': m.expectedSongCount,
        'songs': [
          for (final s in m.songs)
            {
              'id': s.id,
              'title': s.title,
              'artist': s.artist,
              'album': s.album,
              'filename': s.filename,
            }
        ],
      };

Song _ms(String id, String title,
        {String? artist, String? albumArtist, String? album}) =>
    Song(id: id, title: title, artist: artist, albumArtist: albumArtist, album: album);

Future<void> manifest(Directory tmp) async {
  final cases = <Case>[];
  var n = 0;
  Directory fresh() {
    n++;
    clearDeviceCaches();
    return Directory('${tmp.path}/manifest$n')..createSync(recursive: true);
  }

  final weird = [
    'Quote " and \\ backslash',
    'Slash / not escaped',
    'Ctrl \u0000\u0001\u0008\t\n\u000b\u000c\r\u001f\u007f',
    'Line sep \u2028 \u2029',
    'Emoji 🎵 👨‍👩‍👧‍👦',
    'NFD Cafe\u0301 vs NFC Café',
    '坂本龍一',
    '<script>&amp;</script>',
    '',
    ' ',
  ];

  // Write path: sequences of entries against an optional existing file.
  final writeOps = <({String? existing, String mode, List<(Song, String?)> entries, int? expected})>[
    (existing: null, mode: 'batch', entries: [(_ms('1', 'One', artist: 'A', album: 'Alb'), '01 One.flac')], expected: null),
    (existing: null, mode: 'batch', entries: [(_ms('1', 'One'), null)], expected: 12),
    (existing: null, mode: 'single', entries: [(_ms('1', 'One', artist: 'A', albumArtist: 'AA', album: 'Alb'), '1-01 - One.flac')], expected: 3),
    (existing: null, mode: 'single', entries: [(_ms('1', 'One'), null)], expected: null),
    (existing: null, mode: 'batch', entries: [], expected: 5),
    (
      existing: null,
      mode: 'batch',
      entries: [
        for (var i = 0; i < weird.length; i++)
          (_ms('w$i', weird[i], artist: weird[(i + 1) % weird.length], album: weird[(i + 2) % weird.length]), '${weird[i]}.flac')
      ],
      expected: weird.length
    ),
    (
      existing: '{"version":1,"expectedSongCount":9,"songs":[{"id":"1","title":"Old One"},{"id":"2","title":"Two","artist":"X","album":"Y","filename":"02 Two.flac"}]}',
      mode: 'batch',
      entries: [(_ms('1', 'New One', albumArtist: 'AA'), '01 New One.flac'), (_ms('3', 'Three'), null)],
      expected: null
    ),
    (
      existing: '{"version":1,"expectedSongCount":9,"songs":[{"id":"1","title":"Old One"}]}',
      mode: 'single',
      entries: [(_ms('2', 'Two'), 'two.mp3')],
      expected: null
    ),
    (
      existing: '{"version":1,"expectedSongCount":9,"songs":[{"id":"1","title":"Old One"}]}',
      mode: 'batch',
      entries: [(_ms('2', 'Two'), 'two.mp3')],
      expected: 4
    ),
    (
      existing: 'not json',
      mode: 'batch',
      entries: [(_ms('1', 'One'), null)],
      expected: null
    ),
    (
      existing: 'not json',
      mode: 'single',
      entries: [(_ms('1', 'One'), null)],
      expected: null
    ),
    (
      existing: '{"songs":[{"id":1,"title":"bad id"}],"expectedSongCount":2}',
      mode: 'batch',
      entries: [(_ms('1', 'One'), null)],
      expected: null
    ),
    (
      existing: '{"songs":"nope","expectedSongCount":2}',
      mode: 'batch',
      entries: [(_ms('1', 'One'), null)],
      expected: null
    ),
    (
      existing: '{"songs":[{"id":"a","title":"A"},42,"x",null,{"id":"b","title":"B","extra":true}],"version":7}',
      mode: 'single',
      entries: [(_ms('c', 'C'), 'c.flac')],
      expected: null
    ),
    (
      existing: null,
      mode: 'batch',
      entries: [(_ms('dup', 'First'), 'a.flac'), (_ms('dup', 'Second'), 'b.flac')],
      expected: 0
    ),
    (
      existing: '{"songs":[{"id":"1","title":"T"}],"expectedSongCount":9007199254740993}',
      mode: 'batch',
      entries: [(_ms('2', 'T2'), null)],
      expected: null
    ),
    (
      existing: '{"songs":[],"expectedSongCount":-4}',
      mode: 'single',
      entries: [(_ms('2', 'T2'), null)],
      expected: null
    ),
  ];
  for (final op in writeOps) {
    final dir = fresh();
    final file = File('${dir.path}/$kManifestFilename');
    if (op.existing != null) file.writeAsStringSync(op.existing!);
    final input = {
      'existing': op.existing,
      'mode': op.mode,
      'entries': [
        for (final (song, filename) in op.entries)
          {'song': songToJson(song), 'filename': filename}
      ],
      'expectedSongCount': op.expected,
    };
    cases.add(await runAsync(input, () async {
      if (op.mode == 'single') {
        final (song, filename) = op.entries.single;
        addSongToManifest(dir.path, song,
            expectedSongCount: op.expected, filename: filename);
      } else {
        await addSongsToManifestAsync(
            dir.path,
            [for (final (song, filename) in op.entries) (song: song, filename: filename)],
            expectedSongCount: op.expected);
      }
      final written = file.existsSync() ? file.readAsStringSync() : null;
      if (File('${dir.path}/$kManifestFilename.tmp').existsSync()) {
        throw StateError('tmp left behind');
      }
      return {'kind': 'write', 'text': written};
    }));
  }

  // Read path: tolerant parsing of arbitrary file contents.
  final reads = <Object>[
    '{"version":1,"songs":[]}',
    '{"version":1,"expectedSongCount":3,"songs":[{"id":"1","title":"One","artist":"A","album":"B","filename":"01 One.flac"}]}',
    '{"songs":[{"id":"1","title":"One"}]}',
    '{}',
    '[]',
    'null',
    '',
    '   ',
    'not json',
    '{"songs":null}',
    '{"songs":{"id":"1"}}',
    '{"songs":[1,"x",null,[],{"id":"a","title":"A"}]}',
    '{"songs":[{"id":1,"title":"x"}]}',
    '{"songs":[{"id":"1"}]}',
    '{"songs":[{"id":"1","title":null}]}',
    '{"songs":[{"id":"1","title":"t","artist":5}]}',
    '{"songs":[{"id":"1","title":"t","filename":null,"album":null}]}',
    '{"songs":[],"expectedSongCount":3.0}',
    '{"songs":[],"expectedSongCount":"3"}',
    '{"songs":[],"expectedSongCount":null}',
    '{"songs":[],"expectedSongCount":-1}',
    '{"songs":[],"expectedSongCount":1e2}',
    '{"songs":[],"expectedSongCount":9223372036854775807}',
    '{"songs":[],"expectedSongCount":9223372036854775808}',
    '{"songs":[{"id":"1","title":"a"},{"id":"1","title":"b"}]}',
    '{"songs":[{"id":"1","title":"a"}],"songs":[{"id":"2","title":"b"}]}',
    '\ufeff{"songs":[]}',
    '{"songs":[]} trailing',
    '{"songs":[],}',
    "{'songs':[]}",
    '{"songs":[{"id":"\\u00e9\\ud83c\\udfb5","title":"esc\\n\\t\\"q\\""}]}',
    '{"version":2,"songs":[{"id":"x","title":"y","unknown":{"deep":[1,2]}}]}',
    {'base64': base64.encode([0xff, 0xfe, 0x7b, 0x7d])},
    {'base64': base64.encode(utf8.encode('{"songs":[{"id":"1","title":"Café"}]}'))},
    {'base64': base64.encode([...utf8.encode('{"songs":[{"id":"1","title":"'), 0xc3, 0x28, ...utf8.encode('"}]}')])},
  ];
  for (final r in reads) {
    final dir = fresh();
    final file = File('${dir.path}/$kManifestFilename');
    if (r is String) {
      file.writeAsStringSync(r);
    } else {
      file.writeAsBytesSync(base64.decode((r as Map)['base64'] as String));
    }
    final input = r is String ? {'text': r} : r;
    cases.add(run(input, () => {'kind': 'read', 'manifest': _manifestToJson(readManifest(dir.path))}));
  }
  {
    final dir = fresh();
    cases.add(run({'text': null}, () => {'kind': 'read', 'manifest': _manifestToJson(readManifest(dir.path))}));
  }
  clearDeviceCaches();

  writeFixture(
    'manifest',
    '.dapper.json manifest (lib/application/transfer/device_manifest.dart). '
        'WRITE cases: input {existing: file text|null (absent file), mode: "batch" (addSongsToManifestAsync) | '
        '"single" (addSongToManifest; exactly one entry), entries: [{song: Song, filename: str|null}], '
        'expectedSongCount: int|null} → output {kind: "write", text: exact file text after the call (null = no file written)}. '
        'Text is JsonEncoder.withIndent("  ") with no trailing newline; non-ASCII is not escaped. '
        'READ cases: input {text: file contents|null (no file)} or {base64: raw file bytes} → output '
        '{kind: "read", manifest: {expectedSongCount, songs: [{id,title,artist,album,filename}]} | null} '
        '(readManifest; null = missing/unreadable/invalid).',
    cases,
  );
}

// ── scrobbler log ───────────────────────────────────────────────────────────

Map<String, Object?> _entryToJson(ScrobblerLogEntry e) => {
      'artist': e.artist,
      'album': e.album,
      'title': e.title,
      'trackNumber': e.trackNumber,
      'lengthSeconds': e.lengthSeconds,
      'timestamp': e.timestamp.millisecondsSinceEpoch ~/ 1000,
      'timestampIso': e.timestamp.toIso8601String(),
      'musicBrainzId': e.musicBrainzId,
      'raw': e.raw,
    };

Future<void> scrobblerLog(Directory tmp) async {
  const header = '#AUDIOSCROBBLER/1.1\n#TZ/UTC\n#CLIENT/Rockbox sansaclipplus \$Revision\$\n';
  String row(List<String> f) => f.join('\t');
  final rows = <String>[
    row(['Artist', 'Album', 'Title', '1', '240', 'L', '1700000000', 'mbid-123']),
    row(['Artist', 'Album', 'Title', '1', '240', 'L', '1700000000']),
    row(['Artist', 'Album', 'Title', '1', '240', 'L', '1700000000', '']),
    row(['Artist', 'Album', 'Title', '1', '240', 'L', '1700000000', '  ']),
    row(['Artist', 'Album', 'Title', '1', '240', 'L', '1700000000', 'mbid', 'extra', 'cols']),
    row(['Artist', 'Album', 'Skipped', '2', '200', 'S', '1700000100', '']),
    row(['Artist', 'Album', 'lower l', '2', '200', 'l', '1700000100', '']),
    row(['Artist', 'Album', 'spaced L', '2', '200', ' L ', '1700000100', '']),
    row(['Artist', 'Album', 'LL', '2', '200', 'LL', '1700000100', '']),
    row(['Artist', 'Album', 'Short']),
    row(['Artist', 'Album', 'Six', '1', '2', 'L']),
    row(['  Padded Artist  ', '  Padded Album ', '  Padded Title  ', ' 03 ', ' 0180 ', 'L', ' 1700000200 ', ' mb ']),
    row(['', 'Album', 'No Artist', '1', '1', 'L', '1700000300', '']),
    row(['   ', 'Album', 'Blank Artist', '1', '1', 'L', '1700000300', '']),
    row(['Artist', 'Album', '', '1', '1', 'L', '1700000300', '']),
    row(['Artist', '', 'No Album', '', '', 'L', '1700000400', '']),
    row(['Artist', 'Album', 'Bad ts', '1', '1', 'L', 'abc', '']),
    row(['Artist', 'Album', 'Zero ts', '1', '1', 'L', '0', '']),
    row(['Artist', 'Album', 'Neg ts', '1', '1', 'L', '-5', '']),
    row(['Artist', 'Album', 'Plus ts', '+7', '+60', 'L', '+1700000500', '']),
    row(['Artist', 'Album', 'Hex', '0x0A', '0x10', 'L', '0x6553F100', '']),
    row(['Artist', 'Album', 'Float', '1.0', '2.5', 'L', '1700000600.5', '']),
    row(['Artist', 'Album', 'Big track', '99999999999999999999', '9223372036854775807', 'L', '1700000700', '']),
    row(['Artist', 'Album', 'Max ts', '1', '1', 'L', '8640000000000', '']),
    row(['Artist', 'Album', 'Unicode digits', '٣', '１２', 'L', '1700000800', '']),
    row(['Mötley Crüe', 'Dr. Feelgood', 'Kickstart My Heart', '1', '282', 'L', '1700000900', '']),
    row(['Beyonce\u0301', '坂本龍一', '🎵 Emoji', '1', '1', 'L', '1700001000', '']),
    row(['\u00a0NBSP\u00a0', '\ufeffBOM', '\u3000Ideo\u3000', '1', '1', 'L', '1700001100', '\u0085']),
    row(['Artist', 'Album', 'Tab\u000bVT', '1', '1', 'L', '1700001200', '']),
    '#comment-looking row\tAlbum\tTitle\t1\t1\tL\t1700001300\t',
    ' #leading space\tAlbum\tTitle\t1\t1\tL\t1700001300\t',
  ];

  final contents = <String>[
    '',
    header,
    '$header${rows.first}\n',
    '$header${rows.join('\n')}\n',
    '${header.replaceAll('\n', '\r\n')}${rows.join('\r\n')}\r\n',
    rows.join('\n'),
    '$header${rows.take(5).join('\r')}',
    '$header${rows[0]}\n\n\n${rows[1]}',
    '$header${rows[0]}\r\r\n',
    '${rows[0]}\n#late header\n${rows[1]}\n',
    '\ufeff$header${rows[0]}\n',
    '$header${rows[0].substring(0, 20)}',
    for (final r in rows) '$header$r\n',
    // DateTime range overflow throws out of parseScrobblerLog, losing every
    // row; kept separate so the multi-row cases above stay meaningful.
    '$header${rows[0]}\n${row(['Artist', 'Album', 'Past max ts', '1', '1', 'L', '8640000000001', ''])}\n',
  ];

  final cases = <Case>[];
  for (final c in contents) {
    cases.add(run({'fn': 'parse', 'contents': c}, () {
      return [for (final e in parseScrobblerLog(c)) _entryToJson(e)];
    }));
  }

  // Rewrite: header preservation + kept raw lines.
  final file = File('${tmp.path}/scrobbler.log');
  final rewrites = <(String, List<String>)>[
    ('$header${rows[0]}\n${rows[5]}\n', [rows[0]]),
    ('$header${rows[0]}\n', []),
    ('', []),
    ('', ['orphan raw']),
    (rows.join('\n'), [rows[1]]),
    ('${header.replaceAll('\n', '\r\n')}${rows[0]}\r\n', [rows[0]]),
    ('#AUDIOSCROBBLER/1.1\n\n#TZ/UTC\n${rows[0]}', [rows[0], rows[2]]),
    ('#only header no newline', []),
    ('#h1\n#h2\n', ['a', 'b', '']),
    ('$header${rows.join('\n')}', rows.where((r) => r.contains('L')).take(4).toList()),
    ('${rows[0]}\n#late header\n', []),
    ('\ufeff#AUDIOSCROBBLER/1.1\n${rows[0]}\n', [rows[0]]),
  ];
  for (final (orig, keep) in rewrites) {
    if (file.existsSync()) file.deleteSync();
    file.writeAsStringSync('stale contents that must be replaced');
    cases.add(await runAsync({'fn': 'rewrite', 'original': orig, 'keepRaws': keep}, () async {
      await rewriteScrobblerLog(file, orig, keep);
      return file.readAsStringSync();
    }));
  }

  writeFixture(
    'scrobbler_log',
    'AudioScrobbler 1.1 log (lib/data/datasources/local/scrobbler_log.dart). '
        'input {fn: "parse", contents} → output [{artist, album, title, trackNumber: int|null, '
        'lengthSeconds: int|null, timestamp: unix seconds, timestampIso: UTC ISO-8601 as Dart prints it, '
        'musicBrainzId: str|null, raw}] (parseScrobblerLog; Dart int.tryParse accepts +/- sign and 0x hex, '
        'rejects >64-bit; String.trim strips Unicode whitespace incl. U+FEFF/U+0085). `error` = the whole '
        'parse threw (DateTime out of range). input {fn: "rewrite", original, keepRaws: [str]} → output: '
        'exact file text written by rewriteScrobblerLog.',
    cases,
  );
}

// ── scrobble rule ───────────────────────────────────────────────────────────

void scrobbleRule() {
  const s = 1000000;
  final durations = <int>[
    -1, 0, 1, 29 * s, 30 * s - 1, 30 * s, 30 * s + 1, 31 * s, 60 * s, 61 * s + 1,
    239 * s, 240 * s, 480 * s, 481 * s, 600 * s, 3600 * s, 7777777,
  ];
  final cases = <Case>[];
  for (final d in durations) {
    final positions = <int>{
      -1, 0, 1, d ~/ 2 - 1, d ~/ 2, d ~/ 2 + 1, (d + 1) ~/ 2, d - 1, d, d + 1,
      15 * s, 240 * s - 1, 240 * s, 240 * s + 1,
    };
    for (final p in positions) {
      cases.add(run({'positionUs': p, 'durationUs': d}, () => shouldScrobble(
          position: Duration(microseconds: p), duration: Duration(microseconds: d))));
    }
  }
  writeFixture(
    'scrobble_rule',
    'shouldScrobble(position, duration) (lib/application/playback/scrobble_rule.dart). '
        'input {positionUs, durationUs} (microseconds) → output bool.',
    cases,
  );
}

// ── misc ────────────────────────────────────────────────────────────────────

Future<void> misc(Directory tmp) async {
  final cases = <Case>[];

  // estimateTotalBytes
  final songs = [
    const Song(id: 'a', title: 'a', size: 12345678, duration: 240),
    const Song(id: 'b', title: 'b', duration: 240),
    const Song(id: 'c', title: 'c', size: 999),
    const Song(id: 'd', title: 'd'),
    const Song(id: 'e', title: 'e', size: 5, duration: 0),
    const Song(id: 'f', title: 'f', size: 5, duration: -10),
    const Song(id: 'g', title: 'g', size: 1, duration: 7),
    const Song(id: 'h', title: 'h', size: 1, duration: 86400 * 365),
  ];
  for (final song in songs) {
    for (final tc in ['original', 'mp3', 'opus', 'aac']) {
      for (final cap in <int?>[null, 0, -128, 1, 3, 128, 320, 9999]) {
        final settings = Settings(
            devicePath: '/Volumes/SD', transcodeFormat: tc, transcodeMaxBitRate: cap);
        cases.add(run({'fn': 'estimateTotalBytes', 'song': songToJson(song), 'settings': settings.toJson()},
            () => estimateTotalBytes(song, settings.posix())));
      }
    }
  }

  // parseDfOutput
  const macDf =
      'Filesystem   1024-blocks      Used Available Capacity iused ifree %iused  Mounted on\n'
      '/dev/disk4s1    62498784  12345678  50153106    20%      0     0  100%   /Volumes/NO NAME\n';
  const linuxDf =
      'Filesystem     1K-blocks     Used Available Use% Mounted on\n'
      '/dev/sdb1       30608320 10000000  20608320  33% /media/user/SD\n';
  final dfs = <String>[
    macDf,
    linuxDf,
    'Filesystem Size Used Avail Use% Mounted on\n/dev/sda1 100 50 50 50% /\n',
    'Filesystem Size Used AVAIL\n/dev/x 1 2 3\n',
    'Filesystem Size Used Avail\n',
    'Filesystem Size Used Avail',
    '',
    '   \n  ',
    'Filesystem Size Used Free\n/dev/x 1 2 3\n',
    'Filesystem Size Used Avail\n/dev/x 1 2\n',
    'Filesystem Size Used Avail\n/dev/x 1 2 abc\n',
    'Filesystem Size Used Avail\n/dev/x 1 2 -4\n',
    'Filesystem Size Used Avail\n/dev/x 1 2 0x10\n',
    'Filesystem Size Used Avail\n/dev/x 1 2 9223372036854775807\n',
    'Filesystem Size Used Avail\n/dev/x 1 2 99999999999999999999\n',
    'Filesystem\tSize\tUsed\tAvail\n/dev/x\t1\t2\t3\n',
    '  Filesystem Size Used Avail\n  /dev/x 1 2 3\n',
    'Filesystem Size Used Avail\r\n/dev/x 1 2 3\r\n',
    'Filesystem Size Used Avail\n/dev/a 1 2 3\n/dev/b 4 5 6\n',
    'Filesystem Size Used Available Avail\n/dev/x 1 2 3 4\n',
    'Filesystem     1024-blocks Used Available Capacity Mounted on\n/dev/very-long-device-name-that-wraps\n'
        '                 100 50 50 50% /mnt\n',
    'Filesystem Size Used Avail\n/dev/x   1   2   +3\n',
  ];
  for (final d in dfs) {
    cases.add(run({'fn': 'parseDfOutput', 'stdout': d}, () => parseDfOutput(d)));
  }

  // formatBytes — includes exact binary ties (x.x5) where Dart's
  // toStringAsFixed rounds half up but naive round-half-even would not.
  const k = 1024, m = 1024 * 1024, g = 1024 * 1024 * 1024;
  final sizes = <int>{
    -5000, -1, 0, 1, 1023, 1024, 1025, 1075, 1076, 1126, 1127, 1280, 1536, 1792,
    10 * k - 1, 1048575, m - 52, m - 51, m, m + 1, (1.25 * m).round(), (1.75 * m).round(),
    (2.05 * m).round(), 1023 * m, g - 1, g, g + 1, (1.125 * g).round(), (1.375 * g).round(),
    (1.005 * g).round(), (2.675 * g).round(), 1024 * g, 4 * 1024 * g + 12345,
    9223372036854775807,
  };
  final rnd = seeded(10);
  for (var i = 0; i < 60; i++) {
    sizes.add(rnd.nextInt(1 << 32) * (1 << rnd.nextInt(10)));
  }
  for (final b in sizes) {
    cases.add(run({'fn': 'formatBytes', 'bytes': b}, () => formatBytes(b)));
  }

  // writePlaylistM3u — runs against a temp device; paths reported relative.
  final base = Directory('${tmp.path}/m3u')..createSync(recursive: true);
  final albumSongs = [
    const Song(id: '1', title: 'One', artist: 'Artist', album: 'Album', albumArtist: 'Artist', track: 1, duration: 200, suffix: 'flac'),
    const Song(id: '2', title: 'Two/Half', artist: 'Other', album: 'Album', albumArtist: 'Artist', track: 2, discNumber: 2, suffix: 'mp3'),
    const Song(id: '3', title: 'No Artist', album: 'Comp', track: 3, duration: 0, suffix: 'flac'),
    const Song(id: '4', title: 'Empty Artist', artist: '', album: 'Comp', duration: 61, suffix: 'opus'),
    const Song(id: '5', title: 'Ünïcödé 🎵, comma', artist: 'Café, Inc', album: '坂本', year: 1999, track: 5, duration: 333, suffix: 'flac'),
    const Song(id: '6', title: 'Line\nBreak', artist: 'A\tB', album: 'X', track: 6, duration: 1, suffix: 'flac'),
    Song(id: '7', title: 'L' * 300, artist: 'Artist', album: 'Album', track: 7, duration: 10, suffix: 'flac'),
  ];
  final m3uSettings = <Settings>[
    const Settings(devicePath: '<device>'),
    const Settings(devicePath: '<device>', musicRootFolder: 'Music', playlistFolder: 'Playlists'),
    const Settings(devicePath: '<device>', musicRootFolder: 'Music/Lossless', playlistFolder: ''),
    const Settings(devicePath: '<device>', musicRootFolder: 'Music', playlistFolder: 'Music/Playlists'),
    const Settings(devicePath: '<device>', playlistFolder: 'A/B/C', folderStructure: 'flat', filenameFormat: 'none'),
    const Settings(devicePath: '<device>', playlistFolder: '../Outside', transcodeFormat: 'mp3'),
    const Settings(
        devicePath: '<device>',
        musicRootFolder: 'Music',
        folderStructure: 'custom',
        filenameFormat: 'custom',
        customFolderTemplate: '{albumArtist}/{year} - {album}',
        customFilenameTemplate: '{track:3} {title}'),
  ];
  final playlists = <(String, List<int>)>[
    ('Road Trip', [0, 1, 2, 3, 4, 5, 6]),
    ('Partial: Mix?', [0, 2, 4]),
    ('Nothing Present', []),
    ('', [1]),
    ('con', [6]),
  ];
  var idx = 0;
  for (final settings in m3uSettings) {
    for (final (name, present) in playlists) {
      idx++;
      final dev = Directory('${base.path}/case$idx/root/device')..createSync(recursive: true);
      final real = settings.copyWith(devicePath: dev.path).posix();
      for (final i in present) {
        final f = File(buildSongPath(albumSongs[i], real));
        f.parent.createSync(recursive: true);
        f.writeAsStringSync('audio');
      }
      final playlist = Playlist(id: 'pl$idx', name: name, songs: albumSongs);
      final playlistPath = buildPlaylistPath(playlist, real);
      cases.add(await runAsync({
        'fn': 'writePlaylistM3u',
        'playlist': {'name': name, 'songs': [for (final s in albumSongs) songToJson(s)]},
        'settings': settings.toJson(),
        'presentSongIds': [for (final i in present) albumSongs[i].id],
      }, () async {
        await writePlaylistM3u(playlist, real);
        final f = File(playlistPath);
        return {
          'path': playlistPath.replaceFirst(dev.path, '<device>'),
          'content': f.existsSync() ? f.readAsStringSync() : null,
        };
      }));
    }
  }

  writeFixture(
    'misc',
    'Small helpers. {fn: "estimateTotalBytes", song, settings} → int (transfer_queue_notifier.dart). '
        '{fn: "parseDfOutput", stdout} → int bytes|null (platform/disk_space.dart). '
        '{fn: "formatBytes", bytes} → string (core/format/byte_format.dart; toStringAsFixed rounds exact '
        'binary ties half-up). {fn: "writePlaylistM3u", playlist: {name, songs: [Song]}, settings (devicePath '
        '"<device>" stands for a temp device root), presentSongIds: ids whose buildSongPath file exists} → '
        '{path: playlist path with "<device>" prefix, content: exact .m3u text or null when nothing was written}. '
        'm3u cases are posix only.',
    cases,
  );
}
