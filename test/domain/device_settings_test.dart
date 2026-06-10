import 'package:flutter_test/flutter_test.dart';

import 'package:dapper/domain/models/device_settings.dart';

void main() {
  group('TranscodeFormat.apiName', () {
    test('returns null for original (no transcoding)', () {
      // Null is the signal to the API layer that we want /rest/download
      // rather than /rest/stream — keep this contract stable.
      expect(TranscodeFormat.original.apiName, isNull);
    });

    test('returns the Subsonic spec format string for each codec', () {
      expect(TranscodeFormat.mp3.apiName, 'mp3');
      expect(TranscodeFormat.opus.apiName, 'opus');
      expect(TranscodeFormat.aac.apiName, 'aac');
    });
  });

  group('TranscodeFormat.fileExtension', () {
    test('returns null for original so the source suffix is kept', () {
      expect(TranscodeFormat.original.fileExtension, isNull);
    });

    test('returns the correct file extension for each codec', () {
      expect(TranscodeFormat.mp3.fileExtension, 'mp3');
      expect(TranscodeFormat.opus.fileExtension, 'opus');
      // AAC over Subsonic is delivered as an m4a container.
      expect(TranscodeFormat.aac.fileExtension, 'm4a');
    });
  });

  group('DeviceSettings.isTranscoding', () {
    test('false when format is original', () {
      const s = DeviceSettings(devicePath: '/dev');
      expect(s.isTranscoding, isFalse);
      expect(s.transcodeFormat, TranscodeFormat.original);
    });

    test('true for any non-original format', () {
      const s = DeviceSettings(
        devicePath: '/dev',
        transcodeFormat: TranscodeFormat.mp3,
      );
      expect(s.isTranscoding, isTrue);
    });
  });

  group('DeviceSettings.resolvedMusicRoot', () {
    test('falls back to devicePath when musicRootFolder is empty', () {
      const s = DeviceSettings(devicePath: '/Volumes/USB');
      expect(s.resolvedMusicRoot, '/Volumes/USB');
    });

    test('joins devicePath + musicRootFolder otherwise', () {
      const s = DeviceSettings(
        devicePath: '/Volumes/USB',
        musicRootFolder: 'Music',
      );
      expect(s.resolvedMusicRoot, '/Volumes/USB/Music');
    });

    test('joins a nested forward-slash path', () {
      const s = DeviceSettings(
        devicePath: '/Volumes/USB',
        musicRootFolder: 'Music/FLAC/Library',
      );
      expect(s.resolvedMusicRoot, '/Volumes/USB/Music/FLAC/Library');
    });

    test('normalises a back-slash path so callers can paste Windows paths', () {
      const s = DeviceSettings(
        devicePath: '/Volumes/USB',
        musicRootFolder: r'Music\FLAC',
      );
      expect(s.resolvedMusicRoot, '/Volumes/USB/Music/FLAC');
    });

    test('drops whitespace and empty segments', () {
      const s = DeviceSettings(
        devicePath: '/Volumes/USB',
        musicRootFolder: '  Music//FLAC  ',
      );
      expect(s.resolvedMusicRoot, '/Volumes/USB/Music/FLAC');
    });
  });

  group('validateMusicRootPath', () {
    test('null for empty input', () {
      expect(validateMusicRootPath(''), isNull);
      expect(validateMusicRootPath('   '), isNull);
    });

    test('null for valid relative paths', () {
      expect(validateMusicRootPath('Music'), isNull);
      expect(validateMusicRootPath('Music/FLAC'), isNull);
      expect(validateMusicRootPath(r'Music\FLAC'), isNull);
    });

    test('rejects leading slash', () {
      expect(validateMusicRootPath('/Music'), isNotNull);
      expect(validateMusicRootPath(r'\Music'), isNotNull);
    });

    test('rejects Windows drive prefix', () {
      expect(validateMusicRootPath('C:/Music'), isNotNull);
      expect(validateMusicRootPath(r'C:\Music'), isNotNull);
    });

    test(r"rejects '..' segments", () {
      expect(validateMusicRootPath('Music/../Other'), isNotNull);
      expect(validateMusicRootPath('..'), isNotNull);
    });
  });
}
