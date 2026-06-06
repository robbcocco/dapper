import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:dapper/application/transfer/device_manifest.dart';
import 'package:dapper/application/transfer/transfer_path_resolver.dart';
import 'package:dapper/domain/models/device_settings.dart';
import 'package:dapper/domain/models/song.dart';

// Reusable Song factory: every field optional with sensible defaults so each
// test only sets what it cares about.
Song _song({
  String id = 's1',
  String title = 'My Song',
  String? album = 'My Album',
  String? artist = 'My Artist',
  String? albumArtist,
  String? suffix = 'mp3',
  int? track = 1,
  int? discNumber = 1,
  int? year,
}) =>
    Song(
      id: id,
      title: title,
      album: album,
      artist: artist,
      albumArtist: albumArtist,
      suffix: suffix,
      track: track,
      discNumber: discNumber,
      year: year,
    );

DeviceSettings _settings({
  String devicePath = '/dev',
  FolderStructure folderStructure = FolderStructure.artistAlbum,
  FilenameFormat filenameFormat = FilenameFormat.discTrack,
  bool includeYear = false,
  TranscodeFormat transcodeFormat = TranscodeFormat.original,
}) =>
    DeviceSettings(
      devicePath: devicePath,
      folderStructure: folderStructure,
      filenameFormat: filenameFormat,
      includeYear: includeYear,
      transcodeFormat: transcodeFormat,
    );

void main() {
  group('buildSongPath', () {
    test('artist / album / "1-01 - title.ext" by default', () {
      final path = buildSongPath(_song(), _settings());
      expect(path, p.join('/dev', 'My Artist', 'My Album', '1-01 - My Song.mp3'));
    });

    test('prefers albumArtist over artist for the folder', () {
      final path = buildSongPath(
        _song(artist: 'Track Artist', albumArtist: 'Album Artist'),
        _settings(),
      );
      expect(p.split(path), contains('Album Artist'));
    });

    test('falls back to "Unknown Artist" / "Unknown Album"', () {
      final path = buildSongPath(
        _song(artist: null, album: null, albumArtist: null),
        _settings(),
      );
      expect(p.split(path), containsAll(['Unknown Artist', 'Unknown Album']));
    });

    test('artistAlbumYear forces the "year - album" folder', () {
      final path = buildSongPath(
        _song(year: 1973, album: 'Dark Side of the Moon'),
        _settings(folderStructure: FolderStructure.artistAlbumYear),
      );
      expect(p.split(path), contains('1973 - Dark Side of the Moon'));
    });

    test('includeYear adds year prefix in plain artistAlbum mode too', () {
      final path = buildSongPath(
        _song(year: 1973, album: 'Dark Side of the Moon'),
        _settings(includeYear: true),
      );
      expect(p.split(path), contains('1973 - Dark Side of the Moon'));
    });

    test('does not prepend year when year is null or 0', () {
      final pathNoYear = buildSongPath(
        _song(year: null),
        _settings(folderStructure: FolderStructure.artistAlbumYear),
      );
      expect(p.split(pathNoYear), contains('My Album'));

      final pathZero = buildSongPath(
        _song(year: 0),
        _settings(folderStructure: FolderStructure.artistAlbumYear),
      );
      expect(p.split(pathZero), contains('My Album'));
    });

    test('FilenameFormat.none drops the track-number prefix', () {
      final path = buildSongPath(
        _song(),
        _settings(filenameFormat: FilenameFormat.none),
      );
      expect(p.basename(path), 'My Song.mp3');
    });

    test('FilenameFormat.track uses zero-padded track only', () {
      final path = buildSongPath(
        _song(track: 7),
        _settings(filenameFormat: FilenameFormat.track),
      );
      expect(p.basename(path), '07 My Song.mp3');
    });

    test('FilenameFormat.discTrack uses disc-track with hyphen separator', () {
      final path = buildSongPath(
        _song(track: 7, discNumber: 2),
        _settings(),
      );
      expect(p.basename(path), '2-07 - My Song.mp3');
    });

    test('FilenameFormat.discTrack defaults disc to 1 when missing', () {
      final path = buildSongPath(
        _song(track: 7, discNumber: null),
        _settings(),
      );
      expect(p.basename(path), '1-07 - My Song.mp3');
    });

    test('omits the prefix entirely when track is null', () {
      final path = buildSongPath(
        _song(track: null),
        _settings(filenameFormat: FilenameFormat.track),
      );
      expect(p.basename(path), 'My Song.mp3');
    });

    test('uses song.suffix as file extension', () {
      final path = buildSongPath(_song(suffix: 'flac'), _settings());
      expect(p.extension(path), '.flac');
    });

    test('defaults extension to .mp3 when suffix is missing', () {
      final path = buildSongPath(_song(suffix: null), _settings());
      expect(p.extension(path), '.mp3');
    });

    test('uses transcoded extension when transcodeFormat overrides source',
        () {
      // FLAC source + transcode to MP3 → filename must end in .mp3.
      final mp3Path = buildSongPath(
        _song(suffix: 'flac'),
        _settings(transcodeFormat: TranscodeFormat.mp3),
      );
      expect(p.extension(mp3Path), '.mp3');

      final opusPath = buildSongPath(
        _song(suffix: 'flac'),
        _settings(transcodeFormat: TranscodeFormat.opus),
      );
      expect(p.extension(opusPath), '.opus');

      // AAC is shipped as .m4a (Subsonic returns ADTS/AAC wrapped in m4a).
      final aacPath = buildSongPath(
        _song(suffix: 'flac'),
        _settings(transcodeFormat: TranscodeFormat.aac),
      );
      expect(p.extension(aacPath), '.m4a');
    });

    test('keeps source extension when transcodeFormat is original', () {
      final path = buildSongPath(
        _song(suffix: 'flac'),
        _settings(transcodeFormat: TranscodeFormat.original),
      );
      expect(p.extension(path), '.flac');
    });

    test('artistOnly drops the album folder', () {
      final path = buildSongPath(
        _song(),
        _settings(folderStructure: FolderStructure.artistOnly),
      );
      expect(p.split(path).any((seg) => seg == 'My Album'), isFalse);
      expect(p.split(path), contains('My Artist'));
    });

    test('flat drops both artist and album folders', () {
      final path = buildSongPath(
        _song(),
        _settings(folderStructure: FolderStructure.flat),
      );
      expect(p.dirname(path), '/dev');
    });

    test('sanitises path separators in metadata (no traversal)', () {
      final settings = _settings(devicePath: '/dev');
      final path = buildSongPath(
        _song(album: '../escape', artist: 'a/b'),
        settings,
      );
      // The path must resolve as a descendant of the music root: a malicious
      // "../" in metadata cannot escape upward.
      expect(p.isWithin(settings.resolvedMusicRoot, path), isTrue,
          reason: 'path "$path" escaped device root');
      // Defence-in-depth: no path segment should be literal '..' or '.'.
      final segments = p.split(path);
      expect(segments.contains('..'), isFalse);
      expect(segments.contains('.'), isFalse);
    });

    test('truncates a very long title so the path component stays valid', () {
      final long = 'x' * 500;
      final path = buildSongPath(_song(title: long), _settings());
      final filename = p.basename(path);
      // FAT32 max path component is 255 code units.
      expect(filename.length, lessThanOrEqualTo(255));
      // The prefix and extension must still be present.
      expect(filename, startsWith('1-01 - '));
      expect(filename, endsWith('.mp3'));
    });
  });

  group('buildAlbumFolder', () {
    test('returns null for flat / artistOnly (no per-album folder)', () {
      expect(
          buildAlbumFolder('A', 'B', null,
              _settings(folderStructure: FolderStructure.flat)),
          isNull);
      expect(
          buildAlbumFolder('A', 'B', null,
              _settings(folderStructure: FolderStructure.artistOnly)),
          isNull);
    });

    test('artistAlbum joins artist and album under the music root', () {
      expect(buildAlbumFolder('A', 'B', null, _settings()),
          p.join('/dev', 'A', 'B'));
    });

    test('artistAlbumYear prepends year when present', () {
      expect(buildAlbumFolder('A', 'B', 1999,
              _settings(folderStructure: FolderStructure.artistAlbumYear)),
          p.join('/dev', 'A', '1999 - B'));
    });
  });

  group('albumSyncOnDevice (with manifest)', () {
    late Directory tmp;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('dapper_path_test_');
      clearDeviceCaches(); // tests are independent of each other.
    });

    tearDown(() async {
      if (await tmp.exists()) await tmp.delete(recursive: true);
    });

    test('absent when the album folder does not exist', () {
      final settings = _settings(devicePath: tmp.path);
      expect(
        albumSyncOnDevice('Some Artist', 'Some Album', null, 10, settings),
        AlbumSyncStatus.absent,
      );
    });

    test('full when manifest songs >= songCount', () async {
      final settings = _settings(devicePath: tmp.path);
      final folder = buildAlbumFolder('A', 'B', null, settings)!;
      await Directory(folder).create(recursive: true);
      writeManifest(
        folder,
        AlbumManifest(
          songs: [
            for (var i = 0; i < 3; i++)
              ManifestSong(id: 's$i', title: 't$i'),
          ],
          expectedSongCount: 3,
        ),
      );
      expect(
        albumSyncOnDevice('A', 'B', null, 3, settings),
        AlbumSyncStatus.full,
      );
    });

    test('partial when manifest songs < expectedSongCount', () async {
      final settings = _settings(devicePath: tmp.path);
      final folder = buildAlbumFolder('A', 'B', null, settings)!;
      await Directory(folder).create(recursive: true);
      writeManifest(
        folder,
        AlbumManifest(
          songs: [const ManifestSong(id: 's1', title: 't1')],
          expectedSongCount: 5,
        ),
      );
      expect(
        albumSyncOnDevice('A', 'B', null, 5, settings),
        AlbumSyncStatus.partial,
      );
    });

    test('falls back to audio file count when no manifest is present', () async {
      final settings = _settings(devicePath: tmp.path);
      final folder = buildAlbumFolder('A', 'B', null, settings)!;
      await Directory(folder).create(recursive: true);
      await File(p.join(folder, 'a.mp3')).writeAsString('');
      await File(p.join(folder, 'b.flac')).writeAsString('');
      // No manifest → fileCount=2 vs expected=2 → full.
      expect(
        albumSyncOnDevice('A', 'B', null, 2, settings),
        AlbumSyncStatus.full,
      );
    });

    test('ignores AppleDouble sidecar files in the fallback count', () async {
      final settings = _settings(devicePath: tmp.path);
      final folder = buildAlbumFolder('A', 'B', null, settings)!;
      await Directory(folder).create(recursive: true);
      await File(p.join(folder, 'a.mp3')).writeAsString('');
      // macOS-style sidecar that the OS sometimes drops on FAT32 — must NOT
      // count as an audio file.
      await File(p.join(folder, '._a.mp3')).writeAsString('');
      expect(
        albumSyncOnDevice('A', 'B', null, 1, settings),
        AlbumSyncStatus.full,
      );
    });
  });
}
