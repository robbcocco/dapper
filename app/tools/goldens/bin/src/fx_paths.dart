import '../../../../../lib/application/transfer/playlist_sync_writer.dart'
    as pp;
import '../../../../../lib/application/transfer/transfer_path_resolver.dart'
    as px;
import '../../../../../lib/core/extensions/string_extensions.dart';
import '../../../../../lib/domain/models/playlist.dart';
import '../../../../../lib/domain/models/song.dart';
import '../copies/windows/playlist_sync_writer.dart' as wp;
import '../copies/windows/transfer_path_resolver.dart' as wx;
import 'common.dart';
import 'corpus.dart';

const _platformNote =
    '`platform` selects the package:path context: "posix" (macOS/Linux, `/`) '
    'or "windows" (`\\`, drive letters). ';
const _lossyNote =
    'Components are truncated to 255 UTF-16 code units; when that splits a '
    'surrogate pair the Dart string holds a lone surrogate, which this '
    'fixture renders as U+FFFD (case has `note`). Rust: truncate the UTF-16 '
    'units, then String::from_utf16_lossy. ';

const folderStructures = [
  'artistAlbum',
  'artistAlbumYear',
  'artistOnly',
  'flat',
  'custom'
];
const filenameFormats = ['none', 'track', 'discTrack', 'custom'];
const transcodeFormats = ['original', 'mp3', 'opus', 'aac'];

const folderTemplates = [
  '{albumArtist}/{album}',
  '{artist}/{year} - {album}',
  '{albumArtist}/{year:4} - {album} [{disc:2}]',
  '',
  '   ',
  '/{album}/',
  '//{artist}///{album}//',
  '\\{artist}\\\\{album}',
  '{genre}/{album}',
  '{album}/{title}',
  'Music/{artist}',
  '{artist}/../{album}',
  '{artist}/./{album}',
  '{ album }',
  '{ALBUM}',
  '{year:0}/{album}',
  '{track:3}/{album}',
  '{album}{album}',
  ' {album} ',
  '{artist}/ /{album}',
  '...{album}...',
  'con/{album}',
  '{albumArtist}:{album}?',
  '{year:3} {album}',
  '{year:12}/{album}',
];

const filenameTemplates = [
  '{track:3} {title}',
  '{disc:2}-{track:2} {title}',
  '{disc}-{track:02} - {title}',
  '{title}',
  '',
  '   ',
  '{unknown} {title}',
  '{artist} - {title}',
  '{albumArtist} - {album} - {track} - {title}',
  '{track}',
  '{track:10}',
  '{track:0}',
  '{track:300}',
  'a/b {title}',
  'a\\b {title}',
  '{year:4} {title}',
  '{year} {title}',
  '{title}.{title}',
  '...',
  '{track:02}',
  '{Track} {Title}',
  '{track:-2} {title}',
  '{track:2x} {title}',
  '{{title}}',
  '{title:3}',
  'con',
  '{disc:3}',
  '{track:99999999999999999999}',
  '\$1 {title} \\0',
];

final _base = <Song>[
  const Song(
      id: 'full',
      title: 'Song Title',
      album: 'Album',
      artist: 'Artist',
      albumArtist: 'Album Artist',
      year: 1999,
      track: 7,
      discNumber: 2,
      suffix: 'flac'),
  const Song(id: 'minimal', title: 'Minimal'),
  const Song(
      id: 'zeros',
      title: 'Zeros',
      album: 'Z',
      artist: 'Z Artist',
      year: 0,
      track: 0,
      discNumber: 0,
      suffix: 'mp3'),
  const Song(
      id: 'big',
      title: 'Big Numbers',
      album: 'Big',
      artist: 'Only Artist',
      year: 20250,
      track: 123,
      discNumber: 12,
      suffix: 'opus'),
  const Song(
      id: 'neg',
      title: 'Negative',
      album: 'Neg',
      albumArtist: 'Only AlbumArtist',
      year: -5,
      track: -3,
      discNumber: -1,
      suffix: 'm4a'),
];

const _defaultSettings = Settings(
  devicePath: '/Volumes/SD',
  customFilenameTemplate: '{disc}-{track:2} {title}',
  customFolderTemplate: '{albumArtist}/{year} - {album}',
);

Case _songPathCase(Song song, Settings s, String platform) {
  final input = {
    'platform': platform,
    'song': songToJson(song),
    'settings': s.toJson(),
  };
  return run(
      input,
      () => platform == 'posix'
          ? px.buildSongPath(song, s.posix())
          : wx.buildSongPath(song, s.windows()));
}

void safeFilename() {
  final inputs = <String>{...adversarial, ...fuzzStrings(250, salt: 1)};
  writeFixture(
    'safe_filename',
    'String.toSafeFilename() (lib/core/extensions/string_extensions.dart). '
        'input: string; output: sanitised string. No truncation happens here.',
    [for (final s in inputs) run(s, () => s.toSafeFilename())],
  );
}

void songPath() {
  final cases = <Case>[];
  const platforms = ['posix', 'windows'];

  // Full matrix over every enum combination.
  for (final song in _base.take(3)) {
    for (final fs in folderStructures) {
      for (final ff in filenameFormats) {
        for (final y in [false, true]) {
          for (final tc in transcodeFormats) {
            for (final plat in platforms) {
              cases.add(_songPathCase(
                  song,
                  _defaultSettings.copyWith(
                      folderStructure: fs,
                      filenameFormat: ff,
                      includeYear: y,
                      transcodeFormat: tc,
                      devicePath: plat == 'posix' ? '/Volumes/SD' : 'E:\\'),
                  plat));
            }
          }
        }
      }
    }
  }

  // Template sweeps.
  for (final song in _base) {
    for (final t in folderTemplates) {
      for (final plat in platforms) {
        cases.add(_songPathCase(
            song,
            _defaultSettings.copyWith(
                folderStructure: 'custom',
                customFolderTemplate: t,
                devicePath: plat == 'posix' ? '/Volumes/SD' : 'E:\\'),
            plat));
      }
    }
    for (final t in filenameTemplates) {
      cases.add(_songPathCase(
          song,
          _defaultSettings.copyWith(
              filenameFormat: 'custom', customFilenameTemplate: t),
          'posix'));
    }
  }

  // Music root × device path.
  const roots = [
    '',
    'Music',
    '/Music/',
    'a\\b',
    './x',
    '  Music  ',
    'Music/FLAC/Library',
    'Music\\FLAC\\Library',
    '.',
    '..',
    '../escape',
    ' / ',
    'Mus ic',
    'Music//Sub',
    'C:\\Music',
    'Müsik',
  ];
  const devices = [
    '/Volumes/SD',
    '/Volumes/NO NAME/',
    '/',
    'E:\\',
    'E:',
    'C:\\Users\\x\\Music',
    '\\\\server\\share',
    '',
  ];
  for (final root in roots) {
    for (final dev in devices) {
      for (final plat in platforms) {
        for (final fs in ['artistAlbum', 'flat', 'custom']) {
          cases.add(_songPathCase(
              _base.first,
              _defaultSettings.copyWith(
                  musicRootFolder: root, devicePath: dev, folderStructure: fs),
              plat));
        }
      }
    }
  }

  // Suffix handling.
  for (final suffix in ['flac', 'FLAC', '', 'tar.gz', ' mp3', 'm4a', null]) {
    for (final tc in transcodeFormats) {
      final song = Song(
          id: 'sfx', title: 'Suffix', album: 'A', artist: 'B', track: 1, suffix: suffix);
      cases.add(_songPathCase(
          song, _defaultSettings.copyWith(transcodeFormat: tc), 'posix'));
    }
  }

  // Adversarial strings in each role.
  var i = 0;
  for (final s in adversarial) {
    i++;
    final roles = <(Song, Settings)>[
      (
        Song(id: 'adv$i-t', title: s, album: 'Album', artist: 'Artist', track: 3, discNumber: 1, suffix: 'flac'),
        _defaultSettings,
      ),
      (
        Song(id: 'adv$i-tc', title: s, album: 'Album', artist: 'Artist', track: 3, suffix: 'flac'),
        _defaultSettings.copyWith(
            filenameFormat: 'custom', customFilenameTemplate: '{track:3} {title}'),
      ),
      (
        Song(id: 'adv$i-tn', title: s, album: 'Album', artist: 'Artist', suffix: 'flac'),
        _defaultSettings.copyWith(filenameFormat: 'none', transcodeFormat: 'aac'),
      ),
      (
        Song(id: 'adv$i-al', title: 'T', album: s, artist: 'Artist', year: 2001, track: 1, suffix: 'mp3'),
        _defaultSettings.copyWith(folderStructure: 'artistAlbumYear', filenameFormat: 'track'),
      ),
      (
        Song(id: 'adv$i-ar', title: 'T', album: 'A', artist: s, track: 1, suffix: 'mp3'),
        _defaultSettings.copyWith(folderStructure: 'artistOnly'),
      ),
      (
        Song(id: 'adv$i-aa', title: 'T', album: s, artist: 'Ignored', albumArtist: s, year: 1987, track: 12, discNumber: 3, suffix: 'flac'),
        _defaultSettings.copyWith(
            folderStructure: 'custom',
            customFolderTemplate: '{albumArtist}/{year} - {album}',
            includeYear: true),
      ),
    ];
    for (final (song, settings) in roles) {
      cases.add(_songPathCase(song, settings, 'posix'));
    }
  }

  writeFixture(
    'song_path',
    'buildSongPath(song, settings) (lib/application/transfer/transfer_path_resolver.dart). '
        'input: {platform, song: Song, settings: DeviceSettings}; output: absolute path string. '
        '$_platformNote$_lossyNote'
        'Song/DeviceSettings: every field, camelCase, explicit nulls, enums as Dart `.name`. '
        'A case with `error` (output null) means the Dart code threw that exception type.',
    cases,
  );
}

void filenameTemplate() {
  final cases = <Case>[];
  final songs = [
    ..._base,
    const Song(
        id: 'u',
        title: 'Ünïcödé — “Title”',
        album: 'Album/With:Seps',
        artist: 'İstanbul',
        year: 2024,
        track: 4,
        discNumber: 1),
    const Song(id: 'tok', title: '{track}', album: '{title}', artist: '{album}', track: 9),
  ];
  final templates = <String>{
    ...folderTemplates,
    ...filenameTemplates,
    ...fuzzStrings(60, salt: 3, maxLen: 8),
  };
  for (final song in songs) {
    for (final t in templates) {
      cases.add(run({'fn': 'renderFilenameTemplate', 'template': t, 'song': songToJson(song)},
          () => px.renderFilenameTemplate(t, song)));
    }
  }
  final validate = <String>{
    ...templates,
    '{track',
    '{trac}',
    '{titl}',
    ' {title} ',
    '{title}/',
    '\t',
    '{album}',
    '{artist}',
    '{albumArtist}',
    '{Album}',
    '{album}/{title}',
    '{artist}\\{album}',
  };
  for (final t in validate) {
    cases.add(run({'fn': 'validateFilenameTemplate', 'template': t},
        () => px.validateFilenameTemplate(t)));
    cases.add(run({'fn': 'validateFolderTemplate', 'template': t},
        () => px.validateFolderTemplate(t)));
  }
  writeFixture(
    'filename_template',
    'renderFilenameTemplate / validateFilenameTemplate / validateFolderTemplate '
        '(transfer_path_resolver.dart). input: {fn: "renderFilenameTemplate", template, song: Song} '
        '→ output: rendered string (unsanitised); input: {fn: "validateFilenameTemplate"|"validateFolderTemplate", template} '
        '→ output: error message string or null when valid. `error` = Dart threw (e.g. FormatException '
        'for a width that overflows int.parse).',
    cases,
  );
}

void albumFolder() {
  final cases = <Case>[];
  final triples = <(String?, String, int?)>[
    ('Artist', 'Album', 1999),
    (null, 'Album', null),
    ('Artist', 'Album', 0),
    ('Artist', 'Album', -1),
    ('Artist', '', 2000),
    ('', '', null),
    ('AC/DC', 'Back in Black', 1980),
    ('con', 'nul', 1),
    for (final s in adversarial) (s, s, 2010),
  ];
  for (var ti = 0; ti < triples.length; ti++) {
    final (artist, album, year) = triples[ti];
    for (final fs in folderStructures) {
      for (final y in [false, true]) {
        for (final plat in ['posix', 'windows']) {
          // Windows only for the plain triples; adversarial strings are
          // separator-agnostic after sanitising.
          if (plat == 'windows' && ti >= 8) {
            continue;
          }
          final s = _defaultSettings.copyWith(
              folderStructure: fs,
              includeYear: y,
              musicRootFolder: 'Music',
              devicePath: plat == 'posix' ? '/Volumes/SD' : 'E:\\');
          final input = {
            'fn': 'buildAlbumFolder',
            'platform': plat,
            'albumArtist': artist,
            'albumName': album,
            'year': year,
            'settings': s.toJson(),
          };
          cases.add(run(
              input,
              () => plat == 'posix'
                  ? px.buildAlbumFolder(artist, album, year, s.posix())
                  : wx.buildAlbumFolder(artist, album, year, s.windows())));
        }
      }
    }
  }
  for (final t in folderTemplates) {
    for (final plat in ['posix', 'windows']) {
      final s = _defaultSettings.copyWith(
          folderStructure: 'custom',
          customFolderTemplate: t,
          devicePath: plat == 'posix' ? '/Volumes/SD' : 'E:\\');
      for (final (artist, album, year) in triples.take(8)) {
        cases.add(run({
          'fn': 'buildAlbumFolder',
          'platform': plat,
          'albumArtist': artist,
          'albumName': album,
          'year': year,
          'settings': s.toJson(),
        },
            () => plat == 'posix'
                ? px.buildAlbumFolder(artist, album, year, s.posix())
                : wx.buildAlbumFolder(artist, album, year, s.windows())));
      }
    }
  }

  const playlistFolders = ['Playlists', '', 'A/B', 'A\\B', '../Lists', '/abs', ' Spaced ', '.'];
  final names = ['Road Trip', 'Mix: 2024/25', '', '..', 'con', 'Wait…', '🎵' * 130, ...adversarial.take(40)];
  for (final pf in playlistFolders) {
    for (final name in names) {
      for (final plat in ['posix', 'windows']) {
        final s = _defaultSettings.copyWith(
            playlistFolder: pf,
            devicePath: plat == 'posix' ? '/Volumes/SD' : 'E:\\');
        final playlist = Playlist(id: 'p', name: name);
        cases.add(run({
          'fn': 'buildPlaylistPath',
          'platform': plat,
          'playlistName': name,
          'settings': s.toJson(),
        },
            () => plat == 'posix'
                ? pp.buildPlaylistPath(playlist, s.posix())
                : wp.buildPlaylistPath(playlist, s.windows())));
      }
    }
  }

  writeFixture(
    'album_folder',
    'buildAlbumFolder (transfer_path_resolver.dart) and buildPlaylistPath '
        '(playlist_sync_writer.dart). input: {fn: "buildAlbumFolder", platform, albumArtist: str|null, '
        'albumName, year: int|null, settings} → output: folder path or null; input: {fn: "buildPlaylistPath", '
        'platform, playlistName, settings} → output: .m3u path (only Playlist.name is read). '
        '$_platformNote$_lossyNote',
    cases,
  );
}

// ── matchZipEntry ───────────────────────────────────────────────────────────

Song _s(String id, String title, {int? track, int? disc}) =>
    Song(id: id, title: title, track: track, discNumber: disc, album: 'Album', artist: 'Artist', suffix: 'flac');

void matchZipEntry() {
  final albums = <String, List<Song>>{
    'interludes': [
      _s('i1', 'Intro', track: 1),
      _s('i2', 'Interlude I', track: 2),
      _s('i3', 'Interlude II', track: 3),
      _s('i4', 'Interlude III', track: 4),
      _s('i5', 'Outro', track: 5),
      _s('i6', 'Intro (Reprise)', track: 6),
      _s('i11', 'Eleven', track: 11),
      _s('i12', 'Twelve', track: 12),
    ],
    'numeric': [
      _s('n1', '1979', track: 1),
      _s('n2', '22', track: 2),
      _s('n3', '7', track: 3),
      _s('n4', '2 + 2 = 5', track: 4),
      _s('n5', '99 Luftballons', track: 5),
      _s('n6', '3', track: 6),
      _s('n7', '1', track: 7),
    ],
    'multidisc': [
      for (var d = 1; d <= 3; d++)
        for (var t = 1; t <= 5; t++)
          _s('d$d-t$t', 'Disc $d Song ${String.fromCharCode(64 + t)}', track: t, disc: d),
    ],
    'multidisc_sametitles': [
      for (var d = 1; d <= 2; d++)
        for (var t = 1; t <= 3; t++)
          _s('m$d-$t', ['Prelude', 'Theme', 'Finale'][t - 1], track: t, disc: d),
    ],
    'unicode': [
      _s('u1', 'Café del Mar', track: 1),
      _s('u2', 'Cafe\u0301 Noir', track: 2),
      _s('u3', '坂本龍一 – Merry Christmas', track: 3),
      _s('u4', '🎵 Emoji Song', track: 4),
      _s('u5', 'İstanbul (Not Constantinople)', track: 5),
      _s('u6', 'STRASSE', track: 6),
      _s('u7', 'Σίσυφος', track: 7),
      _s('u8', '!!!', track: 8),
    ],
    'notrack': [
      _s('x1', 'Alpha'),
      _s('x2', 'Alphabet'),
      _s('x3', 'Beta Version'),
      _s('x4', 'Gamma', track: 0),
      _s('x5', ''),
      _s('x6', 'The Long Song Title Of Doom'),
    ],
    'duptrack': [
      _s('p1', 'Same Number A', track: 3),
      _s('p2', 'Same Number B', track: 3),
      _s('p3', 'Other', track: 4),
    ],
  };

  List<String> namesFor(Song s) {
    final t = s.track;
    final d = s.discNumber ?? 1;
    final tt = t?.toString().padLeft(2, '0') ?? '';
    return [
      'Artist - Album - $tt - ${s.title}.flac',
      'Album/$tt - ${s.title}.flac',
      '$tt. ${s.title}.flac',
      'Artist/Album/$d-$tt ${s.title}.flac',
      'Artist/Album/Disc $d/$tt ${s.title}.FLAC',
      'CD$d\\$tt - ${s.title}.mp3',
      '${s.title}.flac',
      '${s.title.toUpperCase()}.m4a',
      '$tt.flac',
      '${s.title}',
    ];
  }

  final extraEntries = [
    '',
    '/',
    'Album/',
    '.flac',
    '__MACOSX/Album/._01 - Intro.flac',
    'cover.jpg',
    'Artist - Album - 2024 - Bonus.flac',
    'Album/folder.jpg',
    '00 - Hidden Track.flac',
    '999999999999999999999 - Overflow.flac',
    '1-1.flac',
    '2-3.flac',
    'Disc 2 - 03.flac',
    '!!!.flac',
    '-.flac',
    'Interlude.flac',
    'Interlude III.flac',
    'Interlude II - 4.flac',
    'a.b.c.flac',
    'Artist - Album - 03 - Same Number.flac',
    'Artist - Album - 03 - same number b.flac',
    'Cafe\u0301 del Mar.flac',
    'café noir.flac',
    'istanbul.flac',
    'strasse.flac',
    'ΣΊΣΥΦΟΣ.flac',
    'The Long.flac',
    'Song Title Of Doom Extended Remix.flac',
    'Alph.flac',
    'Alphabet Soup.flac',
  ];

  final cases = <Case>[];
  for (final MapEntry(key: name, value: songs) in albums.entries) {
    final entries = <String>{
      for (final s in songs) ...namesFor(s),
      ...extraEntries,
    };
    for (final e in entries) {
      // Only basename splitting differs by platform, and only on `\`.
      for (final plat in e.contains('\\') ? ['posix', 'windows'] : ['posix']) {
        final input = {
          'platform': plat,
          'album': name,
          'entryPath': e,
          'expected': [for (final s in songs) songToJson(s)],
        };
        cases.add(run(input, () {
          final m = plat == 'posix'
              ? px.matchZipEntry(e, songs)
              : wx.matchZipEntry(e, songs);
          return m?.id;
        }));
      }
    }
  }
  cases.add(run({'platform': 'posix', 'album': 'empty', 'entryPath': '01 - Intro.flac', 'expected': <Object>[]},
      () => px.matchZipEntry('01 - Intro.flac', const [])?.id));

  writeFixture(
    'match_zip_entry',
    'matchZipEntry(entryPath, expected) (transfer_path_resolver.dart). input: {platform, album (label only), '
        'entryPath, expected: [Song]} → output: matched Song.id or null. $_platformNote'
        '(only basenameWithoutExtension is platform-dependent: windows also splits on `\\`).',
    cases,
  );
}
