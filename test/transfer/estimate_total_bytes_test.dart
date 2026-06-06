import 'package:flutter_test/flutter_test.dart';

import 'package:dapper/application/transfer/transfer_queue_notifier.dart';
import 'package:dapper/domain/models/device_settings.dart';
import 'package:dapper/domain/models/song.dart';

Song _song({int? size = 5_000_000, int? duration = 240}) =>
    Song(id: 's', title: 'T', size: size, duration: duration);

DeviceSettings _settings({
  TranscodeFormat format = TranscodeFormat.original,
  int? maxBitRate,
}) =>
    DeviceSettings(
      devicePath: '/dev',
      transcodeFormat: format,
      transcodeMaxBitRate: maxBitRate,
    );

void main() {
  group('estimateTotalBytes — original (no transcoding)', () {
    test('uses song.size when present', () {
      expect(
          estimateTotalBytes(_song(size: 8_000_000), _settings()), 8_000_000);
    });

    test('returns 0 when song.size is missing', () {
      // Caller treats 0 as "skip the progress update"; we never return a
      // negative or null sentinel.
      expect(estimateTotalBytes(_song(size: null), _settings()), 0);
    });
  });

  group('estimateTotalBytes — transcoding with bitrate cap', () {
    test('estimates kbps × duration when both are known', () {
      // 128 kbps × 240 s × 1000 / 8 = 3_840_000 bytes
      final estimate = estimateTotalBytes(
        _song(duration: 240),
        _settings(format: TranscodeFormat.mp3, maxBitRate: 128),
      );
      expect(estimate, 3_840_000);
    });

    test('reflects different bitrate caps proportionally', () {
      // 320 kbps × 240 s × 1000 / 8 = 9_600_000 bytes
      final estimate = estimateTotalBytes(
        _song(duration: 240),
        _settings(format: TranscodeFormat.opus, maxBitRate: 320),
      );
      expect(estimate, 9_600_000);
    });

    test('falls back to song.size when duration is missing', () {
      expect(
        estimateTotalBytes(
          _song(duration: null, size: 4_000_000),
          _settings(format: TranscodeFormat.mp3, maxBitRate: 128),
        ),
        4_000_000,
      );
    });

    test('falls back to song.size when bitrate cap is 0 or negative', () {
      expect(
        estimateTotalBytes(
          _song(duration: 240, size: 4_000_000),
          _settings(format: TranscodeFormat.mp3, maxBitRate: 0),
        ),
        4_000_000,
      );
    });
  });

  group('estimateTotalBytes — transcoding without bitrate cap', () {
    test('falls back to song.size', () {
      // No cap = server picks default; we have no way to estimate so reuse
      // the source size. The transcoded file will usually be smaller, so
      // the progress bar may finish before 100% — better than no progress.
      expect(
        estimateTotalBytes(
          _song(size: 6_000_000),
          _settings(format: TranscodeFormat.mp3),
        ),
        6_000_000,
      );
    });

    test('returns 0 when both size and bitrate are missing', () {
      expect(
        estimateTotalBytes(
          _song(size: null, duration: 240),
          _settings(format: TranscodeFormat.mp3),
        ),
        0,
      );
    });
  });
}
