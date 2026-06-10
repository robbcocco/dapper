import 'package:flutter_test/flutter_test.dart';

import 'package:dapper/core/extensions/string_extensions.dart';

void main() {
  group('toSafeFilename', () {
    test('preserves plain ASCII filenames', () {
      expect('Hello World'.toSafeFilename(), 'Hello World');
    });

    test('normalises ellipsis and dashes', () {
      expect('Foo…Bar'.toSafeFilename(), 'Foo...Bar');
      expect('Foo–Bar'.toSafeFilename(), 'Foo-Bar');
      expect('Foo—Bar'.toSafeFilename(), 'Foo-Bar');
    });

    test('replaces path separators with hyphens (blocks traversal)', () {
      // Both forward and back slashes are turned into hyphens so a
      // server-supplied "../../etc/passwd" can't escape the music root.
      expect('a/b/c'.toSafeFilename(), 'a-b-c');
      expect(r'a\b\c'.toSafeFilename(), 'a-b-c');
      expect('../etc/passwd'.toSafeFilename(), '-etc-passwd');
    });

    test('strips FAT32-illegal characters', () {
      expect('foo:bar*baz?qux"x<y>z|end'.toSafeFilename(), 'foobarbazquxxyzend');
    });

    test('strips control characters and DEL', () {
      expect('foo\x00bar\x1Fbaz\x7Fend'.toSafeFilename(), 'foobarbazend');
    });

    test('collapses repeated spaces', () {
      expect('a   b    c'.toSafeFilename(), 'a b c');
    });

    test('strips leading / trailing dots and spaces', () {
      expect('   .hidden   '.toSafeFilename(), 'hidden');
      expect('trailing... '.toSafeFilename(), 'trailing');
      expect('..dotdot'.toSafeFilename(), 'dotdot');
    });

    test('returns "_" sentinel when the result would be empty', () {
      expect('...'.toSafeFilename(), '_');
      expect('::::'.toSafeFilename(), '_');
      expect(''.toSafeFilename(), '_');
    });

    test('passes through Unicode that is filesystem-safe', () {
      expect('Sigur Rós'.toSafeFilename(), 'Sigur Rós');
      expect('Mötley Crüe'.toSafeFilename(), 'Mötley Crüe');
    });

    test('handles long input without truncation (truncation is path-level)', () {
      final long = 'a' * 500;
      expect(long.toSafeFilename().length, 500);
    });

    test('prefixes Windows reserved device names', () {
      // Windows rejects these even with an extension. Prefix with _ so the
      // file can be created on FAT32/NTFS without the OS refusing.
      expect('con'.toSafeFilename(), '_con');
      expect('CON'.toSafeFilename(), '_CON');
      expect('PRN'.toSafeFilename(), '_PRN');
      expect('aux'.toSafeFilename(), '_aux');
      expect('NUL'.toSafeFilename(), '_NUL');
      expect('com1'.toSafeFilename(), '_com1');
      expect('LPT9'.toSafeFilename(), '_LPT9');
    });

    test('leaves names that merely contain reserved tokens unchanged', () {
      // Only an exact case-insensitive match should be prefixed; "Conrad" is
      // a perfectly legal filename.
      expect('Conrad'.toSafeFilename(), 'Conrad');
      expect('COM10'.toSafeFilename(), 'COM10'); // only COM1-COM9 are reserved
      expect('AUXILIARY'.toSafeFilename(), 'AUXILIARY');
    });
  });
}
