import 'package:flutter_test/flutter_test.dart';

import 'package:dapper/application/transfer/transfer_path_resolver.dart';
import 'package:dapper/domain/models/device_settings.dart';
import 'package:dapper/domain/models/song.dart';

Song _song({
  String title = 'Astronomy Domine',
  String? album = 'The Piper at the Gates of Dawn',
  String? artist = 'Pink Floyd',
  String? albumArtist = 'Pink Floyd',
  int? track = 1,
  int? discNumber = 1,
  int? year = 1967,
  String? suffix = 'flac',
}) =>
    Song(
      id: 's',
      title: title,
      album: album,
      artist: artist,
      albumArtist: albumArtist,
      track: track,
      discNumber: discNumber,
      year: year,
      suffix: suffix,
    );

void main() {
  group('renderFilenameTemplate', () {
    test('substitutes all standard tokens', () {
      const tpl = '{albumArtist} - {album} ({year}) - {disc}.{track:02} - {title}';
      final out = renderFilenameTemplate(tpl, _song());
      expect(out,
          'Pink Floyd - The Piper at the Gates of Dawn (1967) - 1.01 - Astronomy Domine');
    });

    test('zero-pads numeric tokens with width spec', () {
      expect(renderFilenameTemplate('{track:02}', _song(track: 3)), '03');
      expect(renderFilenameTemplate('{track:03}', _song(track: 12)), '012');
      expect(renderFilenameTemplate('{disc:02}', _song(discNumber: 1)), '01');
      expect(renderFilenameTemplate('{year:04}', _song(year: 999)), '0999');
    });

    test('leaves unknown tokens verbatim', () {
      expect(renderFilenameTemplate('{bogus} - {title}', _song()),
          '{bogus} - Astronomy Domine');
    });

    test('falls back to album artist when artist is null', () {
      final s = _song(artist: null);
      expect(renderFilenameTemplate('{artist}', s), 'Pink Floyd');
    });

    test('falls back to track artist when album artist is null', () {
      final s = _song(albumArtist: null);
      expect(renderFilenameTemplate('{albumArtist}', s), 'Pink Floyd');
    });

    test('keeps tokens verbatim when value is null (no album)', () {
      final s = _song(album: null);
      expect(renderFilenameTemplate('{album} - {title}', s),
          '{album} - Astronomy Domine');
    });

    test('empty template falls back to title', () {
      expect(renderFilenameTemplate('', _song()), 'Astronomy Domine');
    });

    test('width spec on non-numeric token is ignored', () {
      // {title:02} doesn't pad — title is not an int.
      expect(renderFilenameTemplate('{title:02}', _song(title: 'X')), 'X');
    });
  });

  group('validateFilenameTemplate', () {
    test('rejects empty', () {
      expect(validateFilenameTemplate(''), isNotNull);
      expect(validateFilenameTemplate('   '), isNotNull);
    });

    test('requires {title} or {track}', () {
      expect(validateFilenameTemplate('{album}'), isNotNull);
      expect(validateFilenameTemplate('{artist} - {album}'), isNotNull);
    });

    test('accepts templates containing {title}', () {
      expect(validateFilenameTemplate('{title}'), isNull);
      expect(validateFilenameTemplate('{album} - {title}'), isNull);
    });

    test('accepts templates containing {track} or {track:N}', () {
      expect(validateFilenameTemplate('{track}'), isNull);
      expect(validateFilenameTemplate('{track:02}'), isNull);
    });

    test('rejects path separators', () {
      expect(validateFilenameTemplate('{title}/{track}'), isNotNull);
      expect(validateFilenameTemplate(r'{title}\{track}'), isNotNull);
    });
  });

  group('validateFolderTemplate', () {
    test('rejects empty', () {
      expect(validateFolderTemplate(''), isNotNull);
      expect(validateFolderTemplate('  '), isNotNull);
    });

    test('rejects templates without {album} or {artist}', () {
      expect(validateFolderTemplate('{year}'), isNotNull);
    });

    test('rejects templates containing {title}', () {
      expect(validateFolderTemplate('{album}/{title}'), isNotNull);
    });

    test('accepts {album} and {artist}', () {
      expect(validateFolderTemplate('{albumArtist}/{album}'), isNull);
      expect(validateFolderTemplate('{artist}'), isNull);
    });
  });

  group('buildSongPath custom folder', () {
    test('renders folder template with multiple components', () {
      const settings = DeviceSettings(
        devicePath: '/Volumes/USB',
        folderStructure: FolderStructure.custom,
        customFolderTemplate: '{albumArtist}/{year} - {album}',
        filenameFormat: FilenameFormat.discTrack,
      );
      final path = buildSongPath(_song(), settings);
      expect(path,
          '/Volumes/USB/Pink Floyd/1967 - The Piper at the Gates of Dawn/1-01 - Astronomy Domine.flac');
    });

    test('drops empty components in folder template', () {
      // {year} for a song with year=null renders as the literal token, which
      // is still non-empty. Test with a custom token-free segment.
      const settings = DeviceSettings(
        devicePath: '/Volumes/USB',
        folderStructure: FolderStructure.custom,
        customFolderTemplate: '{albumArtist}//{album}',
        filenameFormat: FilenameFormat.none,
      );
      final path = buildSongPath(_song(), settings);
      expect(path,
          '/Volumes/USB/Pink Floyd/The Piper at the Gates of Dawn/Astronomy Domine.flac');
    });
  });

  group('buildSongPath custom format', () {
    test('uses template for filename when format == custom', () {
      const settings = DeviceSettings(
        devicePath: '/Volumes/USB',
        filenameFormat: FilenameFormat.custom,
        customFilenameTemplate: '{track:02} - {title}',
      );
      final path = buildSongPath(_song(), settings);
      expect(path,
          '/Volumes/USB/Pink Floyd/The Piper at the Gates of Dawn/01 - Astronomy Domine.flac');
    });

    test('sanitizes template output', () {
      const settings = DeviceSettings(
        devicePath: '/Volumes/USB',
        filenameFormat: FilenameFormat.custom,
        customFilenameTemplate: '{title}',
      );
      // Title with a path separator should be sanitised, not split.
      final s = _song(title: 'Side A / Side B');
      final path = buildSongPath(s, settings);
      // toSafeFilename converts '/' to '-' (per CLAUDE.md guidance).
      expect(path.endsWith('Side A - Side B.flac'), isTrue,
          reason: 'got: $path');
    });
  });
}
