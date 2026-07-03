import 'package:flutter_test/flutter_test.dart';

import 'package:dapper/core/format/byte_format.dart';

void main() {
  group('formatBytes', () {
    test('bytes under 1 KB', () {
      expect(formatBytes(0), '0 B');
      expect(formatBytes(512), '512 B');
      expect(formatBytes(1023), '1023 B');
    });

    test('KB with one decimal', () {
      expect(formatBytes(1024), '1.0 KB');
      expect(formatBytes(1536), '1.5 KB');
    });

    test('MB with one decimal', () {
      expect(formatBytes(1024 * 1024), '1.0 MB');
      expect(formatBytes(5 * 1024 * 1024 + 512 * 1024), '5.5 MB');
    });

    test('GB with two decimals', () {
      expect(formatBytes(1024 * 1024 * 1024), '1.00 GB');
      expect(formatBytes(3 * 1024 * 1024 * 1024), '3.00 GB');
    });

    test('boundaries pick the higher unit', () {
      expect(formatBytes(1024 * 1024 - 1).endsWith('KB'), isTrue);
      expect(formatBytes(1024 * 1024).endsWith('MB'), isTrue);
    });
  });
}
