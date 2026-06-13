import 'dart:async';
import 'dart:developer' as dev;
import 'dart:io';
import 'dart:isolate';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../../domain/models/connected_device.dart';
import '../../domain/models/device_settings.dart';
import '../../domain/models/playlist.dart';
import '../../domain/models/song.dart';
import '../../domain/models/transfer_task.dart';
import '../../platform/disk_space.dart';
import '../device/device_settings_notifier.dart';
import '../providers/providers.dart';
import 'playlist_sync_writer.dart';
import 'device_manifest.dart';
import 'flac_tag_sanitizer.dart';
import 'queue_persistence.dart';
import 'transfer_path_resolver.dart';
import 'zip_extractor.dart';

class TransferQueueNotifier extends Notifier<List<TransferTask>> {
  static const _uuid = Uuid();

  final _cancelTokens = <String, CancelToken>{};
  final _runningEngines = <String>{}; // keyed by devicePath
  final _expectedSongCounts = <String, int>{};
  // Single Dio instance — reuses connections, avoids repeated TLS handshakes.
  final _dio = Dio();
  // Tracks last progress-update timestamp per task to throttle state rebuilds.
  final _lastProgressMs = <String, int>{};
  // Per-folder write chains: serializes concurrent manifest updates for the
  // same album folder without blocking the main thread.
  final _manifestFutures = <String, Future<void>>{};
  // Playlist M3U write: written after all songs in the group complete so the
  // file is only created once every song path actually exists on device.
  // taskId → groupId, groupId → (playlist, devicePath, remaining count)
  final _taskPlaylistGroup = <String, String>{};
  final _pendingPlaylistWrites =
      <String, ({Playlist playlist, String devicePath, int remaining})>{};
  // Devices whose engines are paused: in-flight downloads run to completion
  // but the engine won't pick up new tasks. Kept in memory only — restart =
  // unpaused, which matches the principle of least surprise.
  final _pausedDevices = <String>{};
  // Completer the engine awaits while paused-and-idle. Resume completes it
  // so the loop checks the queue again. One per device.
  final _pauseWakers = <String, Completer<void>>{};

  @override
  List<TransferTask> build() {
    final supportDir = ref.watch(appSupportDirProvider);
    // Best-effort cleanup of stale zip temps left by a crash / forced quit.
    _cleanZipTmp(supportDir);
    final raw = loadQueue(supportDir);
    final restored = raw
        .map((t) => t.status == TransferStatus.inProgress
            ? t.copyWith(
                status: TransferStatus.queued, bytesReceived: 0, totalBytes: 0)
            : t)
        .toList();

    ref.onDispose(() {
      for (final token in _cancelTokens.values) {
        if (!token.isCancelled) token.cancel('TransferQueueNotifier disposed');
      }
      _cancelTokens.clear();
      // Drain any sleeping pause-wakers so engine futures don't dangle.
      for (final waker in _pauseWakers.values) {
        if (!waker.isCompleted) waker.complete();
      }
      _pauseWakers.clear();
      _pausedDevices.clear();
      _dio.close(force: true);
    });

    // Only persist when task statuses change, not on every progress-byte tick.
    listenSelf((prev, next) {
      if (prev != null && prev.length == next.length) {
        var statusChanged = false;
        for (var i = 0; i < next.length; i++) {
          if (next[i].id != prev[i].id || next[i].status != prev[i].status) {
            statusChanged = true;
            break;
          }
        }
        if (!statusChanged) return;
      }
      saveQueue(supportDir, next);
    });

    // Resume pending tasks as soon as the library becomes available.
    ref.listen(libraryRepositoryProvider, (_, repo) {
      if (repo == null) return;
      final devices = state
          .where((t) => t.status == TransferStatus.queued)
          .map((t) => t.devicePath)
          .toSet();
      for (final d in devices) {
        _startEngineForDevice(d);
      }
    });

    // Drop the manifest / folder-exists caches whenever the active device
    // changes — a different mount could coincidentally reuse the same root
    // and a stale "exists" entry would mislead the UI.
    ref.listen<ConnectedDevice?>(selectedDeviceProvider, (prev, next) {
      if (prev?.path != next?.path) clearDeviceCaches();
    });

    return restored;
  }

  // ── Public API ────────────────────────────────────────────────────────────

  void enqueue(
    List<Song> songs,
    String devicePath, {
    Map<String, int>? expectedAlbumSongCounts,
  }) {
    if (expectedAlbumSongCounts != null) {
      _expectedSongCounts.addAll(expectedAlbumSongCounts);
    }

    final newTasks = songs
        .map((s) => TransferTask(
              id: _uuid.v4(),
              song: s,
              devicePath: devicePath,
            ))
        .toList();

    state = [...state, ...newTasks];
    _startEngineForDevice(devicePath);
  }

  void enqueuePlaylist(Playlist playlist, String devicePath) {
    if (playlist.songs.isEmpty) return;

    final groupId = _uuid.v4();
    final newTasks = playlist.songs
        .map((s) => TransferTask(id: _uuid.v4(), song: s, devicePath: devicePath))
        .toList();

    for (final t in newTasks) {
      _taskPlaylistGroup[t.id] = groupId;
    }
    _pendingPlaylistWrites[groupId] = (
      playlist: playlist,
      devicePath: devicePath,
      remaining: newTasks.length,
    );

    state = [...state, ...newTasks];
    _startEngineForDevice(devicePath);
  }

  /// Enqueues a bulk-zip job for an album or artist. Creates one [TransferTask]
  /// per song so the UI shows per-song status, but tags them all with the same
  /// [zipGroupId]. The first task is marked as leader by carrying
  /// [zipSourceId] = sourceId (album or artist) — the engine routes the leader
  /// through the zip-download branch and dispatches extracted files to its
  /// siblings.
  void enqueueZipGroup(
    String sourceId,
    List<Song> songs,
    String devicePath,
  ) {
    if (songs.isEmpty) return;
    // Dedupe: silently no-op when there's already a queued/inProgress zip
    // group for this same source on this device. Stops rapid re-clicks of a
    // Transfer button from creating parallel duplicate downloads.
    final inFlight = state.any((t) =>
        t.devicePath == devicePath &&
        t.zipSourceId == sourceId &&
        (t.status == TransferStatus.queued ||
            t.status == TransferStatus.inProgress));
    if (inFlight) return;
    final groupId = _uuid.v4();
    final newTasks = <TransferTask>[];
    for (var i = 0; i < songs.length; i++) {
      newTasks.add(TransferTask(
        id: _uuid.v4(),
        song: songs[i],
        devicePath: devicePath,
        zipGroupId: groupId,
        zipSourceId: i == 0 ? sourceId : null,
      ));
    }
    state = [...state, ...newTasks];
    _startEngineForDevice(devicePath);
  }

  void cancel(String taskId) {
    final task = state.where((t) => t.id == taskId).firstOrNull;
    // Cancelling any zip-group member cancels the whole group — the bulk
    // download is a single HTTP request, so the natural unit of cancellation
    // is the album, not the individual song row.
    if (task != null && task.zipGroupId != null) {
      final groupId = task.zipGroupId!;
      for (final t in state.where((t) => t.zipGroupId == groupId)) {
        _cancelTokens[t.id]?.cancel('User cancelled');
      }
      state = state
          .map((t) => t.zipGroupId == groupId &&
                  t.status != TransferStatus.completed
              ? t.copyWith(status: TransferStatus.cancelled)
              : t)
          .toList();
      return;
    }
    _cancelTokens[taskId]?.cancel('User cancelled');
    state = state
        .map((t) =>
            t.id == taskId ? t.copyWith(status: TransferStatus.cancelled) : t)
        .toList();
  }

  /// Cancels every queued + in-progress task; pass [devicePath] to scope it
  /// to a single device. In-progress tasks are aborted via their cancel token.
  void cancelAll({String? devicePath}) {
    state = state.map((t) {
      if (devicePath != null && t.devicePath != devicePath) return t;
      if (t.status == TransferStatus.inProgress) {
        _cancelTokens[t.id]?.cancel('Bulk cancel');
        return t.copyWith(status: TransferStatus.cancelled);
      }
      if (t.status == TransferStatus.queued) {
        return t.copyWith(status: TransferStatus.cancelled);
      }
      return t;
    }).toList();
  }

  /// Re-queues every failed task; pass [devicePath] to scope it. Starts the
  /// engine once per affected device rather than once per task.
  ///
  /// Zip-group tagging is stripped on retry so the task runs as a plain
  /// per-song download. Without this the engine's queue scan would never
  /// pick up zip followers (which lack `zipSourceId`) and they'd sit
  /// queued forever.
  void retryAllFailed({String? devicePath}) {
    final touchedDevices = <String>{};
    state = state.map((t) {
      if (t.status != TransferStatus.failed) return t;
      if (devicePath != null && t.devicePath != devicePath) return t;
      touchedDevices.add(t.devicePath);
      return t.copyWith(
        status: TransferStatus.queued,
        errorMessage: null,
        bytesReceived: 0,
        totalBytes: 0,
        zipGroupId: null,
        zipSourceId: null,
      );
    }).toList();
    for (final d in touchedDevices) {
      _startEngineForDevice(d);
    }
  }

  /// Pauses the engine for [devicePath] (or all active devices when null).
  /// In-flight downloads finish; new ones won't start until [resume] is called.
  void pause({String? devicePath}) {
    if (devicePath != null) {
      _pausedDevices.add(devicePath);
      return;
    }
    final devices = state.map((t) => t.devicePath).toSet();
    _pausedDevices.addAll(devices);
  }

  /// Resumes the engine for [devicePath] (or all paused devices when null).
  /// Wakes the engine loop if it was sleeping on a pause waker.
  void resume({String? devicePath}) {
    final targets = devicePath != null
        ? {devicePath}
        : Set<String>.from(_pausedDevices);
    for (final d in targets) {
      _pausedDevices.remove(d);
      _pauseWakers.remove(d)?.complete();
      _startEngineForDevice(d);
    }
  }

  bool isPaused(String devicePath) => _pausedDevices.contains(devicePath);
  bool get isAnyDevicePaused => _pausedDevices.isNotEmpty;

  void retry(String taskId) {
    final task = state
        .where((t) => t.id == taskId && t.status == TransferStatus.failed)
        .firstOrNull;
    if (task == null) return;
    // Strip zip tagging on retry — see retryAllFailed for rationale.
    state = [
      for (final t in state)
        if (t.id == taskId)
          t.copyWith(
              status: TransferStatus.queued,
              errorMessage: null,
              bytesReceived: 0,
              totalBytes: 0,
              zipGroupId: null,
              zipSourceId: null)
        else
          t,
    ];
    _startEngineForDevice(task.devicePath);
  }

  void clearCompleted() {
    state = state
        .where((t) =>
            t.status != TransferStatus.completed &&
            t.status != TransferStatus.cancelled &&
            t.status != TransferStatus.failed)
        .toList();
  }

  // ── Engine ────────────────────────────────────────────────────────────────

  void _startEngineForDevice(String devicePath) {
    if (_runningEngines.contains(devicePath)) return;
    _runEngine(devicePath);
  }

  // Runs up to [_concurrency] downloads in parallel for a single device.
  Future<void> _runEngine(String devicePath) async {
    _runningEngines.add(devicePath);
    var runningCount = 0;
    Completer<void>? slot; // completed whenever a task finishes

    while (true) {
      // "Ready" tasks: per-song tasks always count; zip-group tasks only count
      // when they're the leader (followers wait for the leader to complete).
      bool isReady(TransferTask t) =>
          t.devicePath == devicePath &&
          t.status == TransferStatus.queued &&
          (!t.isZipMember || t.isZipLeader);
      final hasReady = state.any(isReady);
      final paused = _pausedDevices.contains(devicePath);

      if (!hasReady && runningCount == 0 && !paused) break;

      // Paused with no in-flight: sleep on a fresh waker until resume() fires.
      if (paused && runningCount == 0) {
        final waker = Completer<void>();
        _pauseWakers[devicePath] = waker;
        await waker.future;
        continue;
      }

      final concurrency = ref.read(appSettingsProvider).transferConcurrency;
      if (hasReady && runningCount < concurrency && !paused) {
        final next = state.firstWhere(isReady);
        runningCount++;
        // _executeTask marks next as inProgress synchronously before its first
        // await, so the next loop iteration won't pick the same task again.
        unawaited(_executeTask(next).whenComplete(() {
          runningCount--;
          final c = slot;
          slot = null;
          c?.complete();
        }));
        continue; // immediately try to fill another slot
      }

      // At capacity, paused with in-flights, or queue empty but tasks running.
      slot = Completer();
      await slot!.future;
    }

    _runningEngines.remove(devicePath);
  }

  Future<void> _executeTask(TransferTask task) async {
    if (task.isZipLeader) {
      return _executeZipAlbum(task);
    }
    return _executeSong(task);
  }

  Future<void> _executeSong(TransferTask task) async {
    _updateTask(task.id, (t) => t.copyWith(status: TransferStatus.inProgress));

    final cancelToken = CancelToken();
    _cancelTokens[task.id] = cancelToken;

    try {
      final settings = ref.read(deviceSettingsProvider(task.devicePath));
      final targetPath = buildSongPath(task.song, settings);

      if (!settings.overwriteExisting && await File(targetPath).exists()) {
        _updateTask(
            task.id, (t) => t.copyWith(status: TransferStatus.completed));
        final albumFolder = p.dirname(targetPath);
        _appendManifest(albumFolder, task.song,
            expectedSongCount: _expectedSongCounts[albumFolder],
            filename: p.basename(targetPath));
        return; // finally handles group tracking
      }

      await Directory(p.dirname(targetPath)).create(recursive: true);

      // URL is computed at execution time so transcoding-setting changes
      // applied between enqueue and run take effect on later tasks. If the
      // library repo is unavailable (server switched mid-flight, no server),
      // mark this task as failed rather than crashing.
      final repo = ref.read(libraryRepositoryProvider);
      if (repo == null) {
        _updateTask(task.id, (t) => t.copyWith(
              status: TransferStatus.failed,
              errorMessage: 'No active server',
            ));
        return;
      }
      final url = repo
          .transferUri(
            task.song.id,
            format: settings.transcodeFormat.apiName,
            maxBitRate: settings.transcodeMaxBitRate,
          )
          .toString();
      // Estimate total bytes when the server doesn't send Content-Length —
      // common for on-the-fly transcoded responses. Without this the UI
      // sits at 0% for the entire transfer.
      final estimatedTotal = _estimateTotalBytes(task.song, settings);
      await _dio.download(
        url,
        targetPath,
        cancelToken: cancelToken,
        onReceiveProgress: (received, total) {
          // Prefer the server-supplied total; fall back to our estimate so
          // transcoded downloads show progress too.
          final effectiveTotal = total > 0 ? total : estimatedTotal;
          if (effectiveTotal <= 0) return;
          // Throttle to ~200 ms. Only updates the lightweight progress
          // provider — the main task state is untouched until completion.
          final now = DateTime.now().millisecondsSinceEpoch;
          if ((now - (_lastProgressMs[task.id] ?? 0)) < 200) return;
          _lastProgressMs[task.id] = now;
          // Clamp received to total so the bar can't briefly read >100% if
          // the estimate is too pessimistic.
          final clamped = received > effectiveTotal ? effectiveTotal : received;
          ref.read(transferProgressProvider.notifier).update(
              (m) => {...m, task.id: (clamped, effectiveTotal)});
        },
      );
      await removeMacOSSidecar(targetPath);
      if (settings.autoCleanMetadata) await sanitizeFlacTags(targetPath);
      if (settings.autoShrinkCoverArt) {
        await shrinkFlacEmbeddedPicture(targetPath);
      }

      _updateTask(task.id,
          (t) => t.copyWith(status: TransferStatus.completed));
      final albumFolder = p.dirname(targetPath);
      _appendManifest(
        albumFolder,
        task.song,
        expectedSongCount: _expectedSongCounts[albumFolder],
        filename: p.basename(targetPath),
      );
      // finally handles group tracking
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) return; // already marked cancelled
      _updateTask(task.id, (t) => t.copyWith(
            status: TransferStatus.failed,
            errorMessage: e.message,
          ));
    } catch (e) {
      final msg = e.toString();
      final isPermission = msg.contains('errno = 1') ||
          msg.contains('Operation not permitted') ||
          msg.contains('errno = 13') ||
          msg.contains('Permission denied');
      _updateTask(task.id, (t) => t.copyWith(
            status: TransferStatus.failed,
            errorMessage: isPermission ? 'permission_denied' : msg,
          ));
    } finally {
      _cancelTokens.remove(task.id);
      _lastProgressMs.remove(task.id);
      ref.read(transferProgressProvider.notifier).update((m) {
        if (!m.containsKey(task.id)) return m;
        return Map.of(m)..remove(task.id);
      });
      _onGroupTaskDone(task.id);
    }
  }

  // ── Zip album path ─────────────────────────────────────────────────────────

  /// Runs the bulk-zip flow for a [leader] task. Downloads `/rest/download?id=
  /// {albumId}` once, streams the resulting zip onto disk, then extracts each
  /// entry to its final target by matching against the sibling tasks in the
  /// same zip group. Sibling tasks transition queued → completed as their
  /// files land; on failure they all fail.
  Future<void> _executeZipAlbum(TransferTask leader) async {
    final groupId = leader.zipGroupId!;
    final albumId = leader.zipSourceId!;
    final devicePath = leader.devicePath;
    final settings = ref.read(deviceSettingsProvider(devicePath));

    // The zip endpoint always returns originals — transcoded modes must fall
    // back to per-song. Convert siblings to plain tasks and bail out.
    if (settings.isTranscoding) {
      _convertGroupToSongTasks(groupId);
      return;
    }

    final repo = ref.read(libraryRepositoryProvider);
    if (repo == null) {
      _failGroup(groupId, 'No active server');
      return;
    }

    // Snapshot siblings (including leader) — these drive entry matching and
    // collective completion. Captured up-front so state mutations during the
    // run don't shift indices.
    final groupTasks = state.where((t) => t.zipGroupId == groupId).toList();
    final expectedSongs = groupTasks.map((t) => t.song).toList();

    // Fully-on-device short-circuit: when every song's file is present at its
    // target path and the user hasn't asked for overwrites, skip the HTTP
    // round-trip + zip extraction entirely. Mark every sibling completed.
    // Uses songFileExistsOnDevice (direct File.existsSync) so a stale
    // manifest entry can't trick this into firing for an album whose files
    // were manually deleted from the device.
    if (!settings.overwriteExisting &&
        expectedSongs.isNotEmpty &&
        expectedSongs.every((s) => songFileExistsOnDevice(s, settings))) {
      state = state
          .map((t) => t.zipGroupId == groupId &&
                  t.status != TransferStatus.completed
              ? t.copyWith(status: TransferStatus.completed)
              : t)
          .toList();
      return;
    }

    // Mark every member inProgress so the UI reflects the bulk operation.
    state = state
        .map((t) => t.zipGroupId == groupId &&
                t.status == TransferStatus.queued
            ? t.copyWith(status: TransferStatus.inProgress)
            : t)
        .toList();

    final cancelToken = CancelToken();
    _cancelTokens[leader.id] = cancelToken;

    final supportDir = ref.read(appSupportDirProvider);
    final tmpDir = Directory(p.join(supportDir, 'tmp'));
    await tmpDir.create(recursive: true);
    final tmpZip = File(p.join(tmpDir.path, 'zip_$groupId.zip'));

    // Lifted out of the try so the finally block can scrub every group
    // member's entry from transferProgressProvider on cancel / error paths.
    final memberIds = groupTasks.map((t) => t.id).toList(growable: false);

    try {
      final estimatedTotal = expectedSongs
          .map((s) => s.size ?? 0)
          .fold<int>(0, (a, b) => a + b);
      // Disk-free precheck: a multi-GB artist zip needs space for the .zip in
      // the app-support tmp dir AND space for the extracted files on the
      // device. We require ~1.1× the sum of song sizes on each volume so the
      // user sees a clean error up-front rather than mid-download. Null means
      // the platform query failed — fall back to letting Dio surface ENOSPC.
      if (estimatedTotal > 0) {
        final tmpFree = await freeBytesAt(supportDir);
        final deviceFree = await freeBytesAt(devicePath);
        // df can take ~50ms; if the user cancelled in that window the rest
        // of this function would otherwise march ahead and start a download.
        if (cancelToken.isCancelled) {
          state = state
              .map((t) => t.zipGroupId == groupId &&
                      (t.status == TransferStatus.queued ||
                          t.status == TransferStatus.inProgress)
                  ? t.copyWith(status: TransferStatus.cancelled)
                  : t)
              .toList();
          return;
        }
        final required = (estimatedTotal * 11) ~/ 10;
        if (tmpFree != null && tmpFree < required) {
          _failGroup(groupId,
              'Not enough free space in app data for ${_bytesHuman(required)} '
              'zip (${_bytesHuman(tmpFree)} available)');
          return;
        }
        if (deviceFree != null && deviceFree < required) {
          _failGroup(groupId,
              'Not enough free space on device for ${_bytesHuman(required)} '
              '(${_bytesHuman(deviceFree)} available)');
          return;
        }
      }

      final url = repo.zipUri(albumId).toString();
      // memberIds (lifted above the try) drives the mirrored progress writes
      // so every sibling's bar advances in step with the leader. Without
      // mirroring, only the leader's row had a moving bar.
      await _dio.download(
        url,
        tmpZip.path,
        cancelToken: cancelToken,
        onReceiveProgress: (received, total) {
          final effectiveTotal = total > 0 ? total : estimatedTotal;
          if (effectiveTotal <= 0) return;
          final now = DateTime.now().millisecondsSinceEpoch;
          if ((now - (_lastProgressMs[leader.id] ?? 0)) < 200) return;
          _lastProgressMs[leader.id] = now;
          final clamped =
              received > effectiveTotal ? effectiveTotal : received;
          ref.read(transferProgressProvider.notifier).update((m) {
            final next = Map<String, (int, int)>.of(m);
            final tuple = (clamped, effectiveTotal);
            for (final id in memberIds) {
              next[id] = tuple;
            }
            return next;
          });
        },
      );
      // Streaming extraction in a background isolate. Each matched entry
      // arrives as a primitive Map on the ReceivePort so the engine can
      // flip that one sibling to "completed" the moment its file lands on
      // disk — instead of waiting for the whole album to extract before any
      // row moves. Mirror progress entries stay in place until the sibling's
      // own message arrives so each row's bar stays at 100% (rather than
      // briefly going indeterminate) right up until the row marks done.
      final args = <String, dynamic>{
        'zipPath': tmpZip.path,
        'songs': [for (final s in expectedSongs) songToMap(s)],
        'settings': settingsToMap(settings),
        'removeMacosSidecars': Platform.isMacOS,
      };

      final receivePort = ReceivePort();
      final isolate = await Isolate.spawn(
        extractAlbumZipStreaming,
        <String, dynamic>{'sendPort': receivePort.sendPort, 'args': args},
        errorsAreFatal: true,
      );

      final completedIds = <String>{};
      final byFolder = <String, List<({Song song, String filename})>>{};
      final folderExpected = <String, int?>{};
      final writeFailures = <String>{};
      var hadError = false;
      String? errorMessage;

      try {
        await for (final msg in receivePort) {
          if (msg is! Map) continue;
          final type = msg['type'];
          if (type == 'extracted') {
            final songId = msg['songId'] as String;
            final targetPath = msg['targetPath'] as String;
            final expectedCount = msg['expectedCount'] as int?;
            final sibling = groupTasks
                .firstWhere((t) => t.song.id == songId);

            // Tag clean + cover-art shrink before flipping to completed so
            // the file the user sees is the final on-device version. Both
            // gated by per-device toggles. shrinkFlacEmbeddedPicture runs in
            // its own isolate so it doesn't block the main isolate.
            if (settings.autoCleanMetadata) {
              await sanitizeFlacTags(targetPath);
            }
            if (settings.autoShrinkCoverArt) {
              await shrinkFlacEmbeddedPicture(targetPath);
            }

            // Flip this one sibling — small, frequent state mutations are
            // fine here because each row's .select() lookup makes the
            // resulting rebuild cost proportional to one row, not N.
            _updateTask(sibling.id,
                (t) => t.copyWith(status: TransferStatus.completed));
            completedIds.add(sibling.id);

            // Drop just this sibling's mirror progress entry — the others
            // stay at 100% pending their own messages.
            ref.read(transferProgressProvider.notifier).update((m) {
              if (!m.containsKey(sibling.id)) return m;
              return Map.of(m)..remove(sibling.id);
            });

            final folder = p.dirname(targetPath);
            byFolder.putIfAbsent(folder, () => []).add(
                  (song: sibling.song, filename: p.basename(targetPath)),
                );
            folderExpected[folder] = expectedCount;
          } else if (type == 'skipped') {
            final reason = msg['reason'] as String;
            dev.log('zip: $reason');
            if (reason.startsWith('write failed')) {
              writeFailures.add(reason);
            }
          } else if (type == 'error') {
            hadError = true;
            errorMessage = msg['message'] as String?;
          } else if (type == 'done') {
            receivePort.close();
            break;
          }
        }
      } finally {
        receivePort.close();
        isolate.kill(priority: Isolate.immediate);
      }

      if (cancelToken.isCancelled) {
        state = state
            .map((t) => t.zipGroupId == groupId &&
                    (t.status == TransferStatus.queued ||
                        t.status == TransferStatus.inProgress)
                ? t.copyWith(status: TransferStatus.cancelled)
                : t)
            .toList();
        return;
      }

      if (hadError) {
        _failGroup(groupId, errorMessage ?? 'Extract failed');
        return;
      }

      // Per-folder manifest write — one read+write each, regardless of N.
      for (final entry in byFolder.entries) {
        _appendManifestBatch(entry.key, entry.value,
            expectedSongCount: folderExpected[entry.key]);
      }

      // Any sibling not matched by an entry → failed.
      final failedIdToMessage = <String, String>{};
      for (final t in groupTasks) {
        if (completedIds.contains(t.id)) continue;
        if (t.status == TransferStatus.completed) continue;
        final perEntryError = writeFailures.firstWhere(
          (r) => r.contains(t.song.title),
          orElse: () => '',
        );
        failedIdToMessage[t.id] =
            perEntryError.isNotEmpty ? perEntryError : 'Not found in album zip';
      }
      if (failedIdToMessage.isNotEmpty) {
        state = state.map((t) {
          final msg = failedIdToMessage[t.id];
          if (msg == null) return t;
          return t.copyWith(
              status: TransferStatus.failed, errorMessage: msg);
        }).toList();
      }
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) {
        state = state
            .map((t) => t.zipGroupId == groupId &&
                    (t.status == TransferStatus.queued ||
                        t.status == TransferStatus.inProgress)
                ? t.copyWith(status: TransferStatus.cancelled)
                : t)
            .toList();
        return;
      }
      _failGroup(groupId, e.message ?? 'Download failed');
    } catch (e) {
      _failGroup(groupId, e.toString());
    } finally {
      _cancelTokens.remove(leader.id);
      _lastProgressMs.remove(leader.id);
      // Scrub every mirrored sibling entry (not just the leader) so failed /
      // cancelled groups don't leave stale progress tuples in the provider.
      ref.read(transferProgressProvider.notifier).update((m) {
        Map<String, (int, int)>? next;
        for (final id in memberIds) {
          if (m.containsKey(id)) {
            next ??= Map.of(m);
            next.remove(id);
          }
        }
        return next ?? m;
      });
      if (await tmpZip.exists()) {
        try {
          await tmpZip.delete();
        } catch (_) {}
      }
    }
  }

  String _bytesHuman(int bytes) {
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  void _failGroup(String groupId, String message) {
    state = state
        .map((t) => t.zipGroupId == groupId &&
                t.status != TransferStatus.completed &&
                t.status != TransferStatus.cancelled
            ? t.copyWith(
                status: TransferStatus.failed,
                errorMessage: message,
              )
            : t)
        .toList();
  }

  /// Strips zip-group tagging from every task in [groupId] so the engine
  /// falls back to the per-song path. Used when the device is in transcoding
  /// mode (the zip endpoint can't honour `format` / `maxBitRate`).
  void _convertGroupToSongTasks(String groupId) {
    state = state
        .map((t) => t.zipGroupId == groupId
            ? t.copyWith(zipGroupId: null, zipSourceId: null)
            : t)
        .toList();
  }

  /// Deletes leftover `tmp/zip_*.zip` files from a previous run that didn't
  /// reach the finally block — typically a crash or forced quit.
  void _cleanZipTmp(String supportDir) {
    try {
      final tmpDir = Directory(p.join(supportDir, 'tmp'));
      if (!tmpDir.existsSync()) return;
      for (final entity in tmpDir.listSync()) {
        if (entity is! File) continue;
        final name = p.basename(entity.path);
        if (name.startsWith('zip_') && name.endsWith('.zip')) {
          try {
            entity.deleteSync();
          } catch (_) {}
        }
      }
    } catch (_) {}
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  // Decrements the playlist song counter for this task; writes the M3U once
  // every song in the group has finished (success, failure, or cancellation),
  // including only songs that actually exist on device.
  void _onGroupTaskDone(String taskId) {
    final groupId = _taskPlaylistGroup.remove(taskId);
    if (groupId == null) return;
    final entry = _pendingPlaylistWrites[groupId];
    if (entry == null) return;
    final newRemaining = entry.remaining - 1;
    if (newRemaining > 0) {
      _pendingPlaylistWrites[groupId] = (
        playlist: entry.playlist,
        devicePath: entry.devicePath,
        remaining: newRemaining,
      );
      return;
    }
    _pendingPlaylistWrites.remove(groupId);
    final settings = ref.read(deviceSettingsProvider(entry.devicePath));
    writePlaylistM3u(entry.playlist, settings).catchError((Object e) {
      dev.log(
          'TransferQueueNotifier: M3U write failed for playlist '
          '"${entry.playlist.name}" on ${entry.devicePath} — $e');
    });
  }

  // Chains async manifest writes per folder so concurrent completions for the
  // same album don't race on the same file — without blocking the main thread.
  void _appendManifest(String folderPath, Song song,
      {int? expectedSongCount, String? filename}) {
    final prev = _manifestFutures[folderPath] ?? Future.value();
    final next = prev.then((_) => addSongToManifestAsync(folderPath, song,
        expectedSongCount: expectedSongCount, filename: filename));
    _manifestFutures[folderPath] = next;
    next.whenComplete(() {
      if (_manifestFutures[folderPath] == next) _manifestFutures.remove(folderPath);
      _bumpManifestRevision();
    });
  }

  /// Batches a folder's worth of new songs into a single manifest read+write.
  /// The zip-extract path lands every album's songs together, so without this
  /// we'd serialise N read+write cycles to one folder. One write does it.
  void _appendManifestBatch(
    String folderPath,
    List<({Song song, String filename})> entries, {
    int? expectedSongCount,
  }) {
    if (entries.isEmpty) return;
    final prev = _manifestFutures[folderPath] ?? Future.value();
    final next = prev.then((_) => addSongsToManifestAsync(folderPath,
        [for (final e in entries) (song: e.song, filename: e.filename)],
        expectedSongCount: expectedSongCount));
    _manifestFutures[folderPath] = next;
    next.whenComplete(() {
      if (_manifestFutures[folderPath] == next) _manifestFutures.remove(folderPath);
      _bumpManifestRevision();
    });
  }

  void _bumpManifestRevision() {
    ref.read(manifestRevisionProvider.notifier).update((v) => v + 1);
  }

  void _updateTask(String id, TransferTask Function(TransferTask) update) {
    state = state.map((t) => t.id == id ? update(t) : t).toList();
  }
}

/// Best-effort estimate of how many bytes a transfer will receive when the
/// server doesn't send a Content-Length header. Used to keep the progress bar
/// alive during transcoded transfers.
///
/// Strategy:
///   • Not transcoding → use [Song.size] (the server returns the file as-is).
///   • Transcoding with a max-bitrate cap → estimate from `duration × bitrate`,
///     which is the worst case the server will produce.
///   • Transcoding without a cap → fall back to [Song.size] (transcoded size
///     is usually smaller; the bar may finish before reaching 100% but at
///     least it moves).
///   • Anything missing → 0, which the caller treats as "skip the update".
@visibleForTesting
int estimateTotalBytes(Song song, DeviceSettings settings) {
  if (!settings.isTranscoding) {
    return song.size ?? 0;
  }
  final cap = settings.transcodeMaxBitRate;
  final duration = song.duration;
  if (cap != null && cap > 0 && duration != null && duration > 0) {
    // kbps × seconds × 1000 / 8 → bytes
    return (cap * duration * 1000) ~/ 8;
  }
  return song.size ?? 0;
}

int _estimateTotalBytes(Song song, DeviceSettings settings) =>
    estimateTotalBytes(song, settings);

// ── Computed selectors ────────────────────────────────────────────────────────

extension TransferQueueSelectors on List<TransferTask> {
  int get activeCount => where((t) =>
      t.status == TransferStatus.inProgress ||
      t.status == TransferStatus.queued).length;

  int get completedCount =>
      where((t) => t.status == TransferStatus.completed).length;

}
