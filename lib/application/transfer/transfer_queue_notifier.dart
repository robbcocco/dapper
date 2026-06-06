import 'dart:async';
import 'dart:developer' as dev;
import 'dart:io';

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
import '../device/device_settings_notifier.dart';
import '../providers/providers.dart';
import 'playlist_sync_writer.dart';
import 'device_manifest.dart';
import 'queue_persistence.dart';
import 'transfer_path_resolver.dart';

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

  void cancel(String taskId) {
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
    state = [
      for (final t in state)
        if (t.id == taskId)
          t.copyWith(
              status: TransferStatus.queued,
              errorMessage: null,
              bytesReceived: 0,
              totalBytes: 0)
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
      final hasQueued = state.any((t) =>
          t.devicePath == devicePath && t.status == TransferStatus.queued);
      final paused = _pausedDevices.contains(devicePath);

      if (!hasQueued && runningCount == 0 && !paused) break;

      // Paused with no in-flight: sleep on a fresh waker until resume() fires.
      if (paused && runningCount == 0) {
        final waker = Completer<void>();
        _pauseWakers[devicePath] = waker;
        await waker.future;
        continue;
      }

      final concurrency = ref.read(appSettingsProvider).transferConcurrency;
      if (hasQueued && runningCount < concurrency && !paused) {
        final next = state
            .where((t) =>
                t.devicePath == devicePath &&
                t.status == TransferStatus.queued)
            .first;
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
    });
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
