import 'dart:async';
import 'dart:developer' as dev;
import 'dart:io';

import 'package:path/path.dart' as p;

/// Parser + locator for AudioScrobbler 1.1 logs written by DAPs that support
/// offline scrobbling (Rockbox, some HiBy / FiiO / Cowon firmwares).
///
/// Format spec (informal):
///
/// ```text
/// #AUDIOSCROBBLER/1.1
/// #TZ/UTC
/// #CLIENT/<name>
/// artist\talbum\ttitle\ttrackNumber\tlengthSeconds\trating\ttimestamp\tmusicBrainzId
/// ```
///
/// * Rating column is `L` for a full listen, `S` for skipped — only `L` rows
///   should be scrobbled upstream.
/// * Timestamp is unix seconds. `TZ/UTC` is the only timezone the de-facto
///   spec acknowledges, but some firmwares emit local-time-as-UTC; treating
///   the value as UTC is the only sane default since the log carries no
///   offset information.

/// Filenames the importer will recognise. Devices in the wild are
/// inconsistent — Rockbox uses `.scrobbler.log`, some firmwares drop the
/// leading dot or use a `lastfm` prefix. Case-insensitive match.
const _kCandidateNames = <String>{
  '.scrobbler.log',
  'scrobbler.log',
  'lastfm.log',
  'lastfm-scrobbler.log',
};

/// A single playback entry parsed out of an AudioScrobbler log.
class ScrobblerLogEntry {
  const ScrobblerLogEntry({
    required this.artist,
    required this.album,
    required this.title,
    this.trackNumber,
    this.lengthSeconds,
    required this.timestamp,
    this.musicBrainzId,
    required this.raw,
  });

  final String artist;
  final String album;
  final String title;
  final int? trackNumber;
  final int? lengthSeconds;
  final DateTime timestamp;
  final String? musicBrainzId;

  /// The original log line (CR-stripped) this entry was parsed from. Retained
  /// so the importer can rewrite the log keeping only the rows it couldn't
  /// submit, instead of blanket-truncating and losing unmatched plays.
  final String raw;
}

/// Walks [deviceRoot] (one shallow + one nested level) looking for any of
/// [_kCandidateNames]. Stops at the first hit. Walking the whole device tree
/// would be wasteful — every known firmware drops the log at the root or one
/// folder deep (e.g. `Music/.scrobbler.log`).
Future<File?> findScrobblerLog(String deviceRoot) async {
  final root = Directory(deviceRoot);
  if (!await root.exists()) return null;
  try {
    await for (final entity
        in root.list(followLinks: false, recursive: false)) {
      if (entity is File && _matchesCandidate(entity.path)) return entity;
      if (entity is Directory) {
        // One shallow descent; avoid recursion to keep cost predictable on
        // devices with deep music trees.
        try {
          await for (final inner
              in entity.list(followLinks: false, recursive: false)) {
            if (inner is File && _matchesCandidate(inner.path)) return inner;
          }
        } catch (_) {/* permission denied on inner dir → keep scanning */}
      }
    }
  } catch (e) {
    dev.log('findScrobblerLog: scan of $deviceRoot failed — $e');
  }
  return null;
}

bool _matchesCandidate(String filePath) {
  final name = p.basename(filePath).toLowerCase();
  return _kCandidateNames.contains(name);
}

/// Parses [contents] into a flat list of playback entries. Header lines
/// (`#AUDIOSCROBBLER/...`, `#TZ/...`, `#CLIENT/...`) are skipped. Malformed
/// rows are dropped silently rather than aborting the import — DAPs are
/// notorious for emitting half-line corruption when the battery dies
/// mid-write.
List<ScrobblerLogEntry> parseScrobblerLog(String contents) {
  final out = <ScrobblerLogEntry>[];
  for (final raw in contents.split('\n')) {
    final line = raw.replaceAll('\r', '');
    if (line.isEmpty || line.startsWith('#')) continue;
    final parts = line.split('\t');
    // The spec lists 8 fields; a few firmwares omit the MusicBrainz column,
    // so accept >=7. Anything shorter is corrupt.
    if (parts.length < 7) continue;
    final rating = parts[5].trim().toUpperCase();
    // Only fully-listened tracks scrobble upstream. `S` = skipped.
    if (rating != 'L') continue;
    final ts = int.tryParse(parts[6].trim());
    if (ts == null || ts <= 0) continue;
    final artist = parts[0].trim();
    final title = parts[2].trim();
    if (artist.isEmpty || title.isEmpty) continue;
    out.add(ScrobblerLogEntry(
      artist: artist,
      album: parts[1].trim(),
      title: title,
      trackNumber: int.tryParse(parts[3].trim()),
      lengthSeconds: int.tryParse(parts[4].trim()),
      timestamp: DateTime.fromMillisecondsSinceEpoch(ts * 1000, isUtc: true),
      musicBrainzId:
          parts.length >= 8 && parts[7].trim().isNotEmpty
              ? parts[7].trim()
              : null,
      raw: line,
    ));
  }
  return out;
}

/// Truncates [file] in place after a successful import. Devices append new
/// rows to the same file, so truncate-rather-than-delete is more robust —
/// some firmwares re-create the file with a header on next play, but others
/// fail to append if the file vanishes mid-session.
Future<void> truncateScrobblerLog(File file) async {
  try {
    await file.writeAsString('', flush: true);
  } catch (e) {
    dev.log('truncateScrobblerLog: failed for ${file.path} — $e');
  }
}

/// Rewrites [file] keeping its leading header lines plus [keepRaws] (the raw
/// lines of entries the importer could not submit — unmatched plays and
/// failed submissions). Everything else (submitted rows, skipped `S` rows,
/// malformed lines) is dropped. Preserving the header matters because some
/// firmwares only append if the `#AUDIOSCROBBLER` header is present.
///
/// When both the header and [keepRaws] are empty this writes an empty file,
/// i.e. behaves like [truncateScrobblerLog].
Future<void> rewriteScrobblerLog(
    File file, String originalContents, List<String> keepRaws) async {
  final buf = StringBuffer();
  // Headers only ever lead the file; stop at the first non-`#` line.
  for (final raw in originalContents.split('\n')) {
    final line = raw.replaceAll('\r', '');
    if (!line.startsWith('#')) break;
    buf.writeln(line);
  }
  for (final r in keepRaws) {
    buf.writeln(r);
  }
  try {
    await file.writeAsString(buf.toString(), flush: true);
  } catch (e) {
    dev.log('rewriteScrobblerLog: failed for ${file.path} — $e');
  }
}
