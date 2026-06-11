import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:dapper/data/datasources/local/scrobbler_log.dart';

void main() {
  group('parseScrobblerLog', () {
    test('skips header lines and parses L-rated rows', () {
      const log = '#AUDIOSCROBBLER/1.1\n'
          '#TZ/UTC\n'
          '#CLIENT/Rockbox\n'
          'Pink Floyd\tDark Side of the Moon\tMoney\t6\t383\tL\t1700000000\t\n'
          'Pink Floyd\tDark Side of the Moon\tTime\t4\t421\tL\t1700000500\tmbid-1\n';
      final entries = parseScrobblerLog(log);
      expect(entries, hasLength(2));
      expect(entries[0].artist, 'Pink Floyd');
      expect(entries[0].title, 'Money');
      expect(entries[0].trackNumber, 6);
      expect(entries[0].lengthSeconds, 383);
      expect(entries[0].timestamp,
          DateTime.fromMillisecondsSinceEpoch(1700000000 * 1000, isUtc: true));
      expect(entries[0].musicBrainzId, isNull);
      expect(entries[1].musicBrainzId, 'mbid-1');
    });

    test('drops S-rated (skipped) rows so we never up-vote a skip', () {
      const log =
          'Artist\tAlbum\tListened\t1\t200\tL\t1700000000\t\n'
          'Artist\tAlbum\tSkipped\t2\t200\tS\t1700000100\t\n';
      final entries = parseScrobblerLog(log);
      expect(entries, hasLength(1));
      expect(entries.single.title, 'Listened');
    });

    test('ignores rows with too few fields', () {
      const log = 'Artist\tAlbum\tTitle\t1\t200\tL\n'; // missing timestamp
      expect(parseScrobblerLog(log), isEmpty);
    });

    test('ignores rows with non-numeric or zero timestamp', () {
      const log =
          'Artist\tAlbum\tTitle\t1\t200\tL\tnope\t\n'
          'Artist\tAlbum\tTitle\t1\t200\tL\t0\t\n';
      expect(parseScrobblerLog(log), isEmpty);
    });

    test('survives Windows CRLF line endings', () {
      const log =
          '#AUDIOSCROBBLER/1.1\r\nArtist\tAlbum\tTitle\t1\t200\tL\t1700000000\t\r\n';
      final entries = parseScrobblerLog(log);
      expect(entries, hasLength(1));
      expect(entries.single.title, 'Title');
    });

    test('accepts 7-column rows (some firmwares drop the MBID column)', () {
      const log = 'Artist\tAlbum\tTitle\t1\t200\tL\t1700000000\n';
      expect(parseScrobblerLog(log), hasLength(1));
    });
  });

  group('findScrobblerLog', () {
    late Directory tmp;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('scrobbler_test_');
    });

    tearDown(() async {
      if (tmp.existsSync()) await tmp.delete(recursive: true);
    });

    test('returns null when no candidate file exists', () async {
      expect(await findScrobblerLog(tmp.path), isNull);
    });

    test('finds .scrobbler.log at the device root', () async {
      final f = File(p.join(tmp.path, '.scrobbler.log'));
      await f.writeAsString('#AUDIOSCROBBLER/1.1\n');
      final found = await findScrobblerLog(tmp.path);
      expect(found, isNotNull);
      expect(p.basename(found!.path), '.scrobbler.log');
    });

    test('finds a candidate one folder deep', () async {
      final musicDir = Directory(p.join(tmp.path, 'Music'));
      await musicDir.create();
      final f = File(p.join(musicDir.path, 'scrobbler.log'));
      await f.writeAsString('#AUDIOSCROBBLER/1.1\n');
      final found = await findScrobblerLog(tmp.path);
      expect(found, isNotNull);
      expect(p.basename(found!.path), 'scrobbler.log');
    });

    test('matches alternate filenames case-insensitively', () async {
      final f = File(p.join(tmp.path, 'LastFM.log'));
      await f.writeAsString('#AUDIOSCROBBLER/1.1\n');
      final found = await findScrobblerLog(tmp.path);
      expect(found, isNotNull);
    });
  });

  group('truncateScrobblerLog', () {
    test('empties the file without deleting it', () async {
      final tmp = await Directory.systemTemp.createTemp('trunc_test_');
      try {
        final f = File(p.join(tmp.path, '.scrobbler.log'));
        await f.writeAsString('header\nrow\n');
        await truncateScrobblerLog(f);
        expect(await f.exists(), isTrue);
        expect(await f.readAsString(), '');
      } finally {
        await tmp.delete(recursive: true);
      }
    });
  });
}
