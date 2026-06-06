import 'package:flutter_test/flutter_test.dart';

import 'package:dapper/application/playback/scrobble_rule.dart';

void main() {
  group('shouldScrobble — missing / invalid duration', () {
    test('zero duration → false', () {
      expect(
        shouldScrobble(
          position: const Duration(seconds: 30),
          duration: Duration.zero,
        ),
        isFalse,
      );
    });

    test('negative duration → false (defensive against weird stream metadata)',
        () {
      expect(
        shouldScrobble(
          position: const Duration(seconds: 30),
          duration: const Duration(seconds: -10),
        ),
        isFalse,
      );
    });
  });

  group('shouldScrobble — short track', () {
    test('track shorter than 30s never scrobbles, even when fully played', () {
      // 20-second jingle, played fully → still not a scrobble (Last.fm rule).
      expect(
        shouldScrobble(
          position: const Duration(seconds: 20),
          duration: const Duration(seconds: 20),
        ),
        isFalse,
      );
    });

    test('exactly 30s track is eligible for scrobbling', () {
      // Past 50% of a 30-second track.
      expect(
        shouldScrobble(
          position: const Duration(seconds: 16),
          duration: const Duration(seconds: 30),
        ),
        isTrue,
      );
    });
  });

  group('shouldScrobble — 50% rule', () {
    test('below 50% → false', () {
      // 4-minute track, played 1:30. Just under half.
      expect(
        shouldScrobble(
          position: const Duration(seconds: 90),
          duration: const Duration(minutes: 4),
        ),
        isFalse,
      );
    });

    test('exactly 50% → true', () {
      // 4-minute track, played 2:00. Exactly half.
      expect(
        shouldScrobble(
          position: const Duration(minutes: 2),
          duration: const Duration(minutes: 4),
        ),
        isTrue,
      );
    });

    test('above 50% → true', () {
      expect(
        shouldScrobble(
          position: const Duration(seconds: 121),
          duration: const Duration(minutes: 4),
        ),
        isTrue,
      );
    });
  });

  group('shouldScrobble — 4-minute floor for long tracks', () {
    test('long track scrobbled at 4 minutes even though < 50%', () {
      // 12-minute prog track. 4 minutes in = 33%, still scrobbles per the
      // Last.fm rule (whichever comes first).
      expect(
        shouldScrobble(
          position: const Duration(minutes: 4),
          duration: const Duration(minutes: 12),
        ),
        isTrue,
      );
    });

    test('just under 4 minutes on a long track → false', () {
      expect(
        shouldScrobble(
          position: const Duration(seconds: 239),
          duration: const Duration(minutes: 12),
        ),
        isFalse,
      );
    });

    test('30-min epic scrobbles at 4 min not 15 min', () {
      expect(
        shouldScrobble(
          position: const Duration(minutes: 5),
          duration: const Duration(minutes: 30),
        ),
        isTrue,
      );
    });
  });

  group('shouldScrobble — boundary on odd-millisecond durations', () {
    test('50% rule uses microsecond-precision', () {
      // 3 minutes, 1 millisecond. 50% = 1:30.0005. Position 1:30.000 is
      // *just* below — would round to half if we used integer ms division.
      const duration = Duration(minutes: 3, milliseconds: 1);
      final justBelow = Duration(
        microseconds: (duration.inMicroseconds ~/ 2) - 1,
      );
      final justAtHalf = Duration(
        microseconds: duration.inMicroseconds ~/ 2,
      );
      expect(shouldScrobble(position: justBelow, duration: duration), isFalse);
      expect(
          shouldScrobble(position: justAtHalf, duration: duration), isTrue);
    });
  });
}
