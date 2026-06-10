import 'package:flutter_test/flutter_test.dart';

import 'package:dapper/platform/disk_space.dart';

void main() {
  group('parseDfOutput', () {
    test('parses macOS df -k (APFS)', () {
      // 9 columns: Filesystem 1024-blocks Used Available Capacity iused ifree
      //            %iused Mounted-on
      const out = '''
Filesystem     1024-blocks      Used Available Capacity iused     ifree %iused  Mounted on
/dev/disk3s1s1   239331776  12270756  23752044    35%  458725 237520440    0%   /''';
      // Available = 23752044 KiB → bytes
      expect(parseDfOutput(out), 23752044 * 1024);
    });

    test('parses macOS df -k on FAT32 (ifree = 0)', () {
      // FAT32 has no inode concept; ifree = 0. Old "from-end" parser would
      // have picked ifree and produced bytes=0, triggering a false "full".
      const out = '''
Filesystem  1024-blocks   Used  Available Capacity iused ifree %iused Mounted on
/dev/disk6s1   61049344 189123  60860221    1%       512     0   100% /Volumes/USB''';
      expect(parseDfOutput(out), 60860221 * 1024);
    });

    test('parses GNU coreutils df -k (Linux)', () {
      // 6 columns: Filesystem 1K-blocks Used Available Use% Mounted on
      const out = '''
Filesystem     1K-blocks    Used Available Use% Mounted on
/dev/sda1       96320128 8123456  88196672   9% /''';
      expect(parseDfOutput(out), 88196672 * 1024);
    });

    test('accepts the abbreviated "Avail" header', () {
      const out = '''
Filesystem 1K-blocks Used Avail Use% Mounted on
/dev/sda1       100   40    60   40% /''';
      expect(parseDfOutput(out), 60 * 1024);
    });

    test('returns null when no Available column is present', () {
      const out = '''
Filesystem  1K-blocks  Used  Use%  Mounted on
/dev/sda1        100    40    40%  /''';
      expect(parseDfOutput(out), isNull);
    });

    test('returns null on missing data row', () {
      expect(parseDfOutput('header only'), isNull);
      expect(parseDfOutput(''), isNull);
    });

    test('returns null when the Available cell is not a number', () {
      const out = '''
Filesystem 1K-blocks Used Available Use% Mounted on
/dev/sda1       100   40       N/A  40% /''';
      expect(parseDfOutput(out), isNull);
    });
  });
}
