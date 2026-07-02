import 'dart:async';
import 'dart:developer' as dev;
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../data/datasources/local/scrobbler_log.dart';
import '../../domain/models/connected_device.dart';
import '../../domain/models/device_settings.dart';
import '../../domain/repositories/library_repository.dart';
import '../device/device_settings_notifier.dart';
import '../providers/providers.dart';
import '../transfer/device_manifest.dart';

/// Result returned when an import attempt finishes. Stored under the
/// [scrobbleImportResultProvider] so the device page can surface it as a
/// transient banner without coupling the UI to the importer's internals.
class ScrobbleImportResult {
  const ScrobbleImportResult({
    required this.devicePath,
    required this.parsed,
    required this.matched,
    required this.submitted,
    required this.unmatched,
    required this.errors,
  });

  /// Mount path the log was found under.
  final String devicePath;

  /// Rows successfully parsed out of the log.
  final int parsed;

  /// Parsed rows that resolved to a known library song.
  final int matched;

  /// Rows that finished an HTTP scrobble round-trip without error.
  final int submitted;

  /// Rows that parsed but did not match any known library song.
  final int unmatched;

  /// Rows that matched but failed to submit (network error, server error).
  final int errors;

  bool get hasWork => parsed > 0;
}

/// In-memory tracker so a single mount → unmount → re-mount session for the
/// same device doesn't re-run the importer (the log truncation happens after
/// submission, but on a forced-eject the truncate write may not flush). Keyed
/// by device path; cleared on app restart.
final _importedDevicePaths = <String>{};

/// Last-attempted import outcome — the device-page banner watches this.
final scrobbleImportResultProvider =
    StateProvider<ScrobbleImportResult?>((_) => null);

/// Orchestrates a single import pass for [devicePath].
///
/// Steps:
///   1. Locate a scrobbler log on the device (one shallow walk).
///   2. Parse out fully-listened entries.
///   3. Build an index of (artist, album, title) → songId from every
///      `.dapper.json` manifest under the configured music root, since the
///      transfer engine already records the canonical Subsonic ID and the
///      filename it wrote. Manifests are the ground truth — anything not in
///      them was never transferred by this app, so we can't honour it.
///   4. Submit each match via `repo.scrobble(songId, time: …)`.
///   5. Truncate the log on success.
Future<ScrobbleImportResult> importScrobblesFor({
  required String devicePath,
  required DeviceSettings settings,
  required LibraryRepository repo,
}) async {
  final logFile = await findScrobblerLog(devicePath);
  if (logFile == null) {
    return ScrobbleImportResult(
      devicePath: devicePath,
      parsed: 0,
      matched: 0,
      submitted: 0,
      unmatched: 0,
      errors: 0,
    );
  }

  final String contents;
  try {
    contents = await logFile.readAsString();
  } catch (e) {
    dev.log('importScrobblesFor: could not read ${logFile.path} — $e');
    return ScrobbleImportResult(
      devicePath: devicePath,
      parsed: 0,
      matched: 0,
      submitted: 0,
      unmatched: 0,
      errors: 0,
    );
  }

  final entries = parseScrobblerLog(contents);
  if (entries.isEmpty) {
    // Rewrite (keeping only the header) — header-only or all-skipped logs
    // would otherwise be re-scanned on every replug.
    await rewriteScrobblerLog(logFile, contents, const []);
    return ScrobbleImportResult(
      devicePath: devicePath,
      parsed: 0,
      matched: 0,
      submitted: 0,
      unmatched: 0,
      errors: 0,
    );
  }

  final index = await _buildLibraryIndex(settings);

  // Resolve every entry up-front, then submit matches in bounded-parallel.
  // Serial await-per-entry stalled the whole import behind one round-trip
  // each; a flooded fire-all-at-once would hammer the server. Cap at
  // [_submitConcurrency].
  final matchedEntries =
      <({ScrobblerLogEntry entry, String songId})>[];
  // Raw lines we must keep for a future retry: unmatched plays (might match
  // after the album is transferred later) and failed submissions.
  final keepRaws = <String>[];
  for (final entry in entries) {
    final songId = _resolveSongId(entry, index);
    if (songId == null) {
      keepRaws.add(entry.raw);
      continue;
    }
    matchedEntries.add((entry: entry, songId: songId));
  }

  var submitted = 0;
  var errors = 0;
  var cursor = 0;
  Future<void> worker() async {
    while (true) {
      final i = cursor++;
      if (i >= matchedEntries.length) break;
      final m = matchedEntries[i];
      try {
        await repo.scrobble(m.songId, submission: true, time: m.entry.timestamp);
        submitted++;
      } catch (e) {
        errors++;
        keepRaws.add(m.entry.raw);
        dev.log(
            'importScrobblesFor: scrobble("${m.songId}") failed at '
            '${m.entry.timestamp.toIso8601String()} — $e');
      }
    }
  }

  await Future.wait([
    for (var w = 0; w < _submitConcurrency; w++) worker(),
  ]);

  // Rewrite the log keeping only what we couldn't submit. Submitted rows are
  // dropped; unmatched + errored rows survive for the next mount's retry.
  await rewriteScrobblerLog(logFile, contents, keepRaws);

  return ScrobbleImportResult(
    devicePath: devicePath,
    parsed: entries.length,
    matched: matchedEntries.length,
    submitted: submitted,
    unmatched: entries.length - matchedEntries.length,
    errors: errors,
  );
}

/// Max concurrent scrobble submissions during an offline-log import.
const _submitConcurrency = 5;

/// Builds a (artist, album, title) → songId map from every `.dapper.json`
/// under the device's music root. Walks `<root>/<artist>/<album>/.dapper.json`
/// for the standard structures; custom structures with arbitrary depth fall
/// through to a one-extra-level descent so albumArtist/album-year layouts
/// still work without a recursive walk of the whole device.
Future<Map<String, String>> _buildLibraryIndex(DeviceSettings settings) async {
  final index = <String, String>{};
  final root = Directory(settings.resolvedMusicRoot);
  if (!await root.exists()) return index;

  Future<void> consumeFolder(Directory folder) async {
    final manifest = readManifest(folder.path);
    if (manifest == null) return;
    for (final song in manifest.songs) {
      final artist = song.artist ?? '';
      final album = song.album ?? '';
      index[_indexKey(artist, album, song.title)] = song.id;
      // Title-only fallback so log entries with a missing/empty album column
      // (some firmwares blank it out for singles) still resolve. putIfAbsent
      // means the first-indexed song wins on a title collision — two distinct
      // songs sharing a title could scrobble the wrong id. It's a last-resort
      // match (tried only after artist+album and artist+title both miss), so
      // an occasional misattribution beats dropping the play entirely.
      index.putIfAbsent(_indexKey('', '', song.title), () => song.id);
    }
  }

  try {
    await for (final lvl1 in root.list(followLinks: false)) {
      if (lvl1 is! Directory) continue;
      await consumeFolder(lvl1);
      try {
        await for (final lvl2 in lvl1.list(followLinks: false)) {
          if (lvl2 is! Directory) continue;
          await consumeFolder(lvl2);
          // One more level for year-nested or disc-nested custom templates.
          try {
            await for (final lvl3 in lvl2.list(followLinks: false)) {
              if (lvl3 is Directory) await consumeFolder(lvl3);
            }
          } catch (_) {}
        }
      } catch (_) {}
    }
  } catch (e) {
    dev.log('_buildLibraryIndex: walk of ${root.path} failed — $e');
  }
  return index;
}

String _indexKey(String artist, String album, String title) =>
    '${_n(artist)}|${_n(album)}|${_n(title)}';

String _n(String s) {
  // Strip non-alphanumerics and lowercase so cosmetic differences (extra
  // whitespace, smart quotes, "feat." vs "ft.") still find a match.
  final lower = s.toLowerCase();
  final buf = StringBuffer();
  for (final r in lower.runes) {
    if ((r >= 0x30 && r <= 0x39) ||
        (r >= 0x61 && r <= 0x7a) ||
        r > 0x7f) {
      buf.writeCharCode(r);
    }
  }
  return buf.toString();
}

String? _resolveSongId(ScrobblerLogEntry entry, Map<String, String> index) {
  // Try (artist, album, title), then (artist, '', title), then ('', '', title).
  final exact = index[_indexKey(entry.artist, entry.album, entry.title)];
  if (exact != null) return exact;
  final noAlbum = index[_indexKey(entry.artist, '', entry.title)];
  if (noAlbum != null) return noAlbum;
  return index[_indexKey('', '', entry.title)];
}

/// Wires the importer to the device-plug event. Fires `importScrobblesFor`
/// once per new device path, throttled so a flapping mount can't trigger an
/// import storm. Watch this from `AppShell` so the lifecycle matches the UI.
class ScrobbleImportListener {
  ScrobbleImportListener(this._ref);
  final Ref _ref;

  Future<void> handle(List<ConnectedDevice> devices) async {
    final repo = _ref.read(libraryRepositoryProvider);
    if (repo == null) return; // no server, nothing to submit against
    for (final d in devices) {
      if (_importedDevicePaths.contains(d.path)) continue;
      _importedDevicePaths.add(d.path);
      // Resolve persisted settings synchronously via the Notifier so the
      // user's configured music-root subfolder is honoured.
      final settings = _ref.read(deviceSettingsProvider(d.path));
      try {
        final result = await importScrobblesFor(
          devicePath: d.path,
          settings: settings,
          repo: repo,
        );
        if (result.hasWork) {
          _ref.read(scrobbleImportResultProvider.notifier).state = result;
        }
      } catch (e, st) {
        dev.log('ScrobbleImportListener: import failed for ${d.path} — $e',
            stackTrace: st);
      }
    }
    // Drop tracking for devices that disappeared so a future replug retries.
    _importedDevicePaths.removeWhere(
        (path) => !devices.any((d) => d.path == path));
  }
}

final scrobbleImportListenerProvider = Provider<ScrobbleImportListener>(
  ScrobbleImportListener.new,
);
