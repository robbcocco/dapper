import 'dart:async';
import 'dart:developer' as dev;

import 'package:path/path.dart' as p;

import '../../../platform/device_fs.dart';

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
  });

  final String artist;
  final String album;
  final String title;
  final int? trackNumber;
  final int? lengthSeconds;
  final DateTime timestamp;
  final String? musicBrainzId;
}

/// Walks [deviceRoot] (one shallow + one nested level) looking for any of
/// [_kCandidateNames]. Stops at the first hit. Walking the whole device tree
/// would be wasteful — every known firmware drops the log at the root or one
/// folder deep (e.g. `Music/.scrobbler.log`).
///
/// Returns the absolute path to the log file, or null if none was found.
Future<String?> findScrobblerLog(String deviceRoot, DeviceFs fs) async {
  if (!await fs.isDir(deviceRoot)) return null;
  try {
    final lvl0 = await fs.list(deviceRoot);
    for (final entry in lvl0) {
      if (!entry.isDir && _matchesCandidate(entry.path)) return entry.path;
    }
    for (final entry in lvl0) {
      if (!entry.isDir) continue;
      try {
        final lvl1 = await fs.list(entry.path);
        for (final inner in lvl1) {
          if (!inner.isDir && _matchesCandidate(inner.path)) return inner.path;
        }
      } catch (_) {/* permission denied on inner dir → keep scanning */}
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
    ));
  }
  return out;
}

/// Truncates the log at [path] in place after a successful import. Devices
/// append new rows to the same file, so truncate-rather-than-delete is more
/// robust — some firmwares re-create the file with a header on next play,
/// but others fail to append if the file vanishes mid-session.
Future<void> truncateScrobblerLog(String path, DeviceFs fs) async {
  try {
    await fs.truncate(path);
  } catch (e) {
    dev.log('truncateScrobblerLog: failed for $path — $e');
  }
}
