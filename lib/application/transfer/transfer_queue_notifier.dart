import 'dart:async';
import 'dart:developer' as dev;
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../../domain/models/connected_device.dart';
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
        _startEngineForDevice(d, repo.downloadUri);
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
    String devicePath,
    Uri Function(String) downloadUri, {
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
    _startEngineForDevice(devicePath, downloadUri);
  }

  void enqueuePlaylist(
    Playlist playlist,
    String devicePath,
    Uri Function(String) downloadUri,
  ) {
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
    _startEngineForDevice(devicePath, downloadUri);
  }

  void cancel(String taskId) {
    _cancelTokens[taskId]?.cancel('User cancelled');
    state = state
        .map((t) =>
            t.id == taskId ? t.copyWith(status: TransferStatus.cancelled) : t)
        .toList();
  }

  void retry(String taskId) {
    final repo = ref.read(libraryRepositoryProvider);
    if (repo == null) return;
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
    _startEngineForDevice(task.devicePath, repo.downloadUri);
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

  void _startEngineForDevice(
      String devicePath, Uri Function(String) downloadUri) {
    if (_runningEngines.contains(devicePath)) return;
    _runEngine(devicePath, downloadUri);
  }

  // Runs up to [_concurrency] downloads in parallel for a single device.
  Future<void> _runEngine(
      String devicePath, Uri Function(String) downloadUri) async {
    _runningEngines.add(devicePath);
    var runningCount = 0;
    Completer<void>? slot; // completed whenever a task finishes

    while (true) {
      final hasQueued = state.any((t) =>
          t.devicePath == devicePath && t.status == TransferStatus.queued);

      if (!hasQueued && runningCount == 0) break;

      final concurrency = ref.read(appSettingsProvider).transferConcurrency;
      if (hasQueued && runningCount < concurrency) {
        final next = state
            .where((t) =>
                t.devicePath == devicePath &&
                t.status == TransferStatus.queued)
            .first;
        runningCount++;
        // _executeTask marks next as inProgress synchronously before its first
        // await, so the next loop iteration won't pick the same task again.
        unawaited(_executeTask(next, downloadUri).whenComplete(() {
          runningCount--;
          final c = slot;
          slot = null;
          c?.complete();
        }));
        continue; // immediately try to fill another slot
      }

      // At capacity or waiting for remaining tasks to finish.
      slot = Completer();
      await slot!.future;
    }

    _runningEngines.remove(devicePath);
  }

  Future<void> _executeTask(
      TransferTask task, Uri Function(String) downloadUri) async {
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

      final url = downloadUri(task.song.id).toString();
      await _dio.download(
        url,
        targetPath,
        cancelToken: cancelToken,
        onReceiveProgress: (received, total) {
          if (total <= 0) return;
          // Throttle to ~200 ms. Only updates the lightweight progress
          // provider — the main task state is untouched until completion.
          final now = DateTime.now().millisecondsSinceEpoch;
          if ((now - (_lastProgressMs[task.id] ?? 0)) < 200) return;
          _lastProgressMs[task.id] = now;
          ref.read(transferProgressProvider.notifier).update(
              (m) => {...m, task.id: (received, total)});
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

// ── Computed selectors ────────────────────────────────────────────────────────

extension TransferQueueSelectors on List<TransferTask> {
  int get activeCount => where((t) =>
      t.status == TransferStatus.inProgress ||
      t.status == TransferStatus.queued).length;

  int get completedCount =>
      where((t) => t.status == TransferStatus.completed).length;

}
