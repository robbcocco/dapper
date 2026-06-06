/// One line of lyrics. [start] is the absolute timestamp in milliseconds
/// (only meaningful for synced lyrics — null for plain text).
class LyricsLine {
  const LyricsLine({required this.text, this.start});

  final String text;
  final Duration? start;
}

/// Lyrics for a single track. Subsonic's `getLyricsBySongId` returns one
/// [Lyrics] per available language; we surface the first match (the server
/// typically orders them by user preference). [synced] indicates whether
/// per-line timestamps are present.
class Lyrics {
  const Lyrics({
    required this.lines,
    required this.synced,
    this.lang,
  });

  final List<LyricsLine> lines;
  final bool synced;
  final String? lang;

  bool get isEmpty => lines.isEmpty;
  bool get isNotEmpty => lines.isNotEmpty;
}
