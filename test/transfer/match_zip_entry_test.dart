import 'package:flutter_test/flutter_test.dart';

import 'package:dapper/application/transfer/transfer_path_resolver.dart';
import 'package:dapper/domain/models/song.dart';

Song _song({
  required String id,
  required String title,
  int? track,
  int? discNumber,
}) =>
    Song(
      id: id,
      title: title,
      track: track,
      discNumber: discNumber,
      album: 'A',
      artist: 'X',
    );

void main() {
  group('matchZipEntry', () {
    final expected = [
      _song(id: '1', title: 'Astronomy Domine', track: 1, discNumber: 1),
      _song(id: '2', title: 'Lucifer Sam',     track: 2, discNumber: 1),
      _song(id: '3', title: 'Matilda Mother',  track: 3, discNumber: 1),
      _song(id: '4', title: 'Flaming',         track: 4, discNumber: 1),
      _song(id: '5', title: "Pow R. Toc H.",   track: 5, discNumber: 1),
    ];

    test('exact track + title match', () {
      final m = matchZipEntry(
          'Pink Floyd/Piper at the Gates/02 - Lucifer Sam.flac', expected);
      expect(m?.id, '2');
    });

    test('disc-track prefix', () {
      final m = matchZipEntry('1-03 Matilda Mother.flac', expected);
      expect(m?.id, '3');
    });

    test('plain track number, no separator', () {
      final m = matchZipEntry('04 Flaming.mp3', expected);
      expect(m?.id, '4');
    });

    test('title only, no track prefix', () {
      final m = matchZipEntry('Astronomy Domine.flac', expected);
      expect(m?.id, '1');
    });

    test('punctuation in title is normalised', () {
      final m = matchZipEntry('05 Pow R Toc H.flac', expected);
      expect(m?.id, '5');
    });

    test('returns null when nothing matches', () {
      final m = matchZipEntry('99 - Unknown Song.flac', expected);
      expect(m, isNull);
    });

    test('returns null on empty expected list', () {
      expect(matchZipEntry('01 - Foo.flac', const []), isNull);
    });

    test('disambiguates duplicate track numbers across discs', () {
      final multi = [
        _song(id: 'a', title: 'Side A', track: 1, discNumber: 1),
        _song(id: 'b', title: 'Side B', track: 1, discNumber: 2),
      ];
      final m1 = matchZipEntry('1-01 - Side A.flac', multi);
      final m2 = matchZipEntry('2-01 - Side B.flac', multi);
      expect(m1?.id, 'a');
      expect(m2?.id, 'b');
    });

    test('falls back to title when track is unknown', () {
      final m = matchZipEntry('Lucifer Sam.flac', expected);
      expect(m?.id, '2');
    });

    test('matches archive paths with leading directories', () {
      final m = matchZipEntry(
          'Artist/Album/03 - Matilda Mother.flac', expected);
      expect(m?.id, '3');
    });

    test('flat artist-album-track-title basename matches the right track', () {
      // Navidrome sometimes flattens the layout into the basename. There's no
      // leading track number — the digit lives in the middle of the name.
      final m = matchZipEntry(
          'alt-J - An Awesome Wave - 02 - Lucifer Sam.flac', expected);
      expect(m?.id, '2');
    });

    test('prefers the longest title overlap (Interlude II vs III)', () {
      // Regression: substring matching used to grab "Interlude II" for the
      // "Interlude III" filename because II is a prefix of III. Scoring on
      // overlap length picks III.
      final tracklist = [
        _song(id: 'two', title: 'Interlude II', track: 9, discNumber: 1),
        _song(id: 'three', title: 'Interlude III', track: 11, discNumber: 1),
      ];
      final m = matchZipEntry(
          'alt‐J - An Awesome Wave - 11 - Interlude III.flac', tracklist);
      expect(m?.id, 'three');
    });

    test('handles a parenthetical title with extra digits in basename', () {
      // Filename: "Taro (live from the Africa Centre 14.04.12)". The basename
      // carries year/date digits that must not steal the track score from the
      // actual song titled "Taro (Live...)" at track 15.
      final tracklist = [
        _song(id: 'studio', title: 'Taro', track: 12, discNumber: 1),
        _song(
            id: 'live',
            title: 'Taro (Live from the Africa Centre, 14.04.12)',
            track: 15,
            discNumber: 1),
      ];
      final m = matchZipEntry(
          'alt‐J - An Awesome Wave - 15 - Taro (live from the Africa Centre 14.04.12).flac',
          tracklist);
      expect(m?.id, 'live');
    });

    test('track number in filename trumps a closer title overlap', () {
      // Filename track 11. Song "Interlude" has track 11 but its title is a
      // strict prefix of every other interlude. Song "Interlude III" has a
      // longer title but lives at track 4 — the track number must keep the
      // routing to song id "eleven" regardless of the longer-title pull.
      final tracklist = [
        _song(id: 'eleven', title: 'Interlude', track: 11, discNumber: 1),
        _song(id: 'four', title: 'Interlude III', track: 4, discNumber: 1),
      ];
      final m = matchZipEntry(
          'Artist - Album - 11 - Interlude III.flac', tracklist);
      expect(m?.id, 'eleven');
    });

    test('unicode hyphen in artist does not block matching', () {
      // "alt‐J" uses U+2010 HYPHEN, not ASCII '-'. The normaliser keeps non-
      // ASCII, but the track-number and title scoring still wins.
      final tracklist = [
        _song(id: '7', title: 'Breezeblocks', track: 7, discNumber: 1),
      ];
      final m = matchZipEntry(
          'alt‐J - An Awesome Wave - 07 - Breezeblocks.flac', tracklist);
      expect(m?.id, '7');
    });
  });
}
