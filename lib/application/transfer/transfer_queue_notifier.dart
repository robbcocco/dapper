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
import '../../core/format/byte_format.dart';
import '../../platform/disk_space.dart';
import '../device/device_settings_notifier.dart';
import '../providers/providers.dart';
import 'playlist_sync_writer.dart';
import 'device_manifest.dart';
import 'flac_tag_sanitizer.dart';
import 'queue_persistence.dart';
import 'transfer_path_resolver.dart';
import 'zip_extractor.dart';

/// Counting semaphore for bounding the post-process pool. Permits acquired by
/// detached post-process futures so they can run concurrently with downloads
/// without unbounded parallel FLAC-shrink isolates.
class _Semaphore {
  _Semaphore(this._permits);
  int _permits;
  final _waiters = <Completer<void>>[];

  Future<void> acquire() {
    if (_permits > 0) {
      _permits--;
      return Future.value();
    }
    final c = Completer<void>();
    _waiters.add(c);
    return c.future;
  }

  void release() {
    if (_waiters.isNotEmpty) {
      _waiters.removeAt(0).complete();
    } else {
      _permits++;
    }
  }
}

/// Max files post-processing (sidecar strip / tag clean / cover shrink) at once,
/// independent of download concurrency so post-processing never steals a
/// download slot. Cap bounds simultaneous shrink isolates.
const _kPostProcessConcurrency = 3;

/// Two-stage pipeline backpressure: how many downloaded-but-not-yet-written
/// units may sit staged on the internal disk before the downloader stops
/// pulling new work. Bounds staging disk use (a fast network + slow device
/// could otherwise stage the whole library). The writer draining a unit frees
/// a slot and wakes the downloader.
const _kMaxStagedAhead = 3;

/// One unit of work queued for the sequential device-writer: either a single
/// downloaded+post-processed song sitting in staging, or a downloaded album
/// zip awaiting sequential extraction onto the device.
class _StagedUnit {
  _StagedUnit.song({
    required this.task,
    required this.stagingPath,
    required this.targetPath,
    required this.albumFolder,
  })  : isZip = false,
        groupId = null,
        zipStagingPath = null,
        groupTasks = null;

  _StagedUnit.zip({
    required this.groupId,
    required this.zipStagingPath,
    required this.groupTasks,
  })  : isZip = true,
        task = null,
        stagingPath = null,
        targetPath = null,
        albumFolder = null;

  final bool isZip;
  // Per-song fields.
  final TransferTask? task;
  final String? stagingPath;
  final String? targetPath;
  final String? albumFolder;
  // Zip fields.
  final String? groupId;
  final String? zipStagingPath;
  final List<TransferTask>? groupTasks;
}

class TransferQueueNotifier extends Notifier<List<TransferTask>> {
  static const _uuid = Uuid();

  final _cancelTokens = <String, CancelToken>{};
  final _runningEngines = <String>{}; // keyed by devicePath
  final _expectedSongCounts = <String, int>{};
  // Post-process runs detached from the download slot (see _stageSong) so the
  // engine keeps the network saturated instead of idling a slot during tag
  // clean / cover shrink. Bounded by this shared semaphore.
  final _postProcessSem = _Semaphore(_kPostProcessConcurrency);
  // Completed-status flips are coalesced into one state rebuild per ~120 ms.
  // A burst of small files finishing post-process at once would otherwise fire
  // one O(N) list rebuild each. Group accounting (M3U / manifest) does NOT wait
  // on this — only the visual flip is throttled.
  final _pendingCompleted = <String>{};
  Timer? _completedFlushTimer;
  // Coalesces manifest-revision bumps so a bulk transfer doesn't rebuild every
  // visible browse-page row once per completed song.
  Timer? _manifestBumpTimer;
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

  // ── Two-stage pipeline ──────────────────────────────────────────────────────
  // Downloads run in parallel into an internal staging dir; a single sequential
  // writer per device drains staged units onto the (slow) device so concurrent
  // writes never thrash the flash. See _runEngine (downloader) + _runWriter.
  //
  // Per-device FIFO of units ready to write, and the set of devices with a live
  // writer loop. Writer wakers unblock an idle writer when a unit is staged or
  // on resume; engine wakers unblock the downloader when a slot frees (download
  // finished) or the writer drains a staged unit (backpressure released).
  final _writeQueues = <String, List<_StagedUnit>>{};
  final _writerRunning = <String>{};
  final _writerWakers = <String, Completer<void>>{};
  final _engineWakers = <String, Completer<void>>{};

  @override
  List<TransferTask> build() {
    final supportDir = ref.watch(appSupportDirProvider);
    // Best-effort cleanup of stale zip temps + staged files left by a crash /
    // forced quit (their tasks were reset to queued and will re-download).
    _cleanZipTmp(supportDir);
    _cleanStaging(supportDir);
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
      // Drain any sleeping pause / writer / engine wakers so the downloader
      // and writer loop futures don't dangle after dispose.
      for (final waker in _pauseWakers.values) {
        if (!waker.isCompleted) waker.complete();
      }
      _pauseWakers.clear();
      for (final waker in _writerWakers.values) {
        if (!waker.isCompleted) waker.complete();
      }
      _writerWakers.clear();
      for (final waker in _engineWakers.values) {
        if (!waker.isCompleted) waker.complete();
      }
      _engineWakers.clear();
      _writeQueues.clear();
      _pausedDevices.clear();
      _completedFlushTimer?.cancel();
      _completedFlushTimer = null;
      _manifestBumpTimer?.cancel();
      _manifestBumpTimer = null;
      _pendingCompleted.clear();
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
      _wakeDevice(task.devicePath);
      return;
    }
    _cancelTokens[taskId]?.cancel('User cancelled');
    state = state
        .map((t) =>
            t.id == taskId ? t.copyWith(status: TransferStatus.cancelled) : t)
        .toList();
    if (task != null) _wakeDevice(task.devicePath);
  }

  /// Cancels every queued + in-progress task; pass [devicePath] to scope it
  /// to a single device. In-progress tasks are aborted via their cancel token.
  void cancelAll({String? devicePath}) {
    final touched = <String>{};
    state = state.map((t) {
      if (devicePath != null && t.devicePath != devicePath) return t;
      if (t.status == TransferStatus.inProgress) {
        _cancelTokens[t.id]?.cancel('Bulk cancel');
        touched.add(t.devicePath);
        return t.copyWith(status: TransferStatus.cancelled);
      }
      if (t.status == TransferStatus.queued) {
        touched.add(t.devicePath);
        return t.copyWith(status: TransferStatus.cancelled);
      }
      return t;
    }).toList();
    for (final d in touched) {
      _wakeDevice(d);
    }
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
      _wakeWriter(d);
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
    if (!_runningEngines.contains(devicePath)) unawaited(_runEngine(devicePath));
    if (!_writerRunning.contains(devicePath)) unawaited(_runWriter(devicePath));
  }

  // Wakes the downloader loop for [devicePath] if it's sleeping (a download
  // slot freed, or the writer drained a staged unit so backpressure lifted).
  void _wakeEngine(String devicePath) {
    final w = _engineWakers.remove(devicePath);
    if (w != null && !w.isCompleted) w.complete();
  }

  // Wakes the sequential writer loop for [devicePath] if it's sleeping (a unit
  // was staged, or the device resumed).
  void _wakeWriter(String devicePath) {
    final w = _writerWakers.remove(devicePath);
    if (w != null && !w.isCompleted) w.complete();
  }

  // ── Stage 1: download (parallel) ────────────────────────────────────────────
  // Runs up to `transferConcurrency` downloads in parallel for a single device,
  // each landing in the internal staging dir. Backs off when too many units are
  // staged-but-unwritten so a fast network can't outrun the slow device.
  Future<void> _runEngine(String devicePath) async {
    _runningEngines.add(devicePath);
    var runningCount = 0;

    while (true) {
      // "Ready" tasks: per-song tasks always count; zip-group tasks only count
      // when they're the leader (followers wait for the leader to complete).
      bool isReady(TransferTask t) =>
          t.devicePath == devicePath &&
          t.status == TransferStatus.queued &&
          (!t.isZipMember || t.isZipLeader);
      final hasReady = state.any(isReady);
      final paused = _pausedDevices.contains(devicePath);
      final backlog = _writeQueues[devicePath]?.length ?? 0;

      // Exit only when nothing is queued, nothing is downloading, and nothing
      // is staged waiting (the writer owns staged units and will drain them).
      if (!hasReady && runningCount == 0 && !paused && backlog == 0) break;

      // Paused with no in-flight: sleep on a fresh waker until resume() fires.
      if (paused && runningCount == 0) {
        final waker = Completer<void>();
        _pauseWakers[devicePath] = waker;
        await waker.future;
        continue;
      }

      final concurrency = ref.read(appSettingsProvider).transferConcurrency;
      if (hasReady &&
          runningCount < concurrency &&
          backlog < _kMaxStagedAhead &&
          !paused) {
        final next = state.firstWhere(isReady);
        runningCount++;
        // _download marks next as inProgress synchronously before its first
        // await, so the next loop iteration won't pick the same task again.
        unawaited(_download(next).whenComplete(() {
          runningCount--;
          _wakeEngine(devicePath);
        }));
        continue; // immediately try to fill another slot
      }

      // At capacity, backlog full, paused with in-flights, or queue drained but
      // downloads still running. Sleep until a slot frees or the writer drains.
      final waker = Completer<void>();
      _engineWakers[devicePath] = waker;
      await waker.future;
    }

    _runningEngines.remove(devicePath);
    // A staged unit may have been enqueued just as we decided to exit; make
    // sure the writer is alive to drain it (it normally already is).
    if ((_writeQueues[devicePath]?.isNotEmpty ?? false) &&
        !_writerRunning.contains(devicePath)) {
      unawaited(_runWriter(devicePath));
    }
  }

  Future<void> _download(TransferTask task) async {
    if (task.isZipLeader) {
      return _downloadZip(task);
    }
    return _downloadSong(task);
  }

  // Appends a staged unit to the device's write FIFO and wakes the writer.
  void _enqueueWrite(String devicePath, _StagedUnit unit) {
    (_writeQueues[devicePath] ??= <_StagedUnit>[]).add(unit);
    _wakeWriter(devicePath);
  }

  // ── Stage 2: write (sequential) ─────────────────────────────────────────────
  // Single loop per device. Drains staged units one at a time so only one write
  // hits the flash at once. Freeing a unit wakes the downloader (backpressure).
  Future<void> _runWriter(String devicePath) async {
    _writerRunning.add(devicePath);

    while (true) {
      final q = _writeQueues[devicePath];

      // Paused: finish nothing new until resume. In-flight write (if any) has
      // already completed by the time we loop back here.
      if (_pausedDevices.contains(devicePath)) {
        final anyLeft = (q?.isNotEmpty ?? false) ||
            state.any((t) =>
                t.devicePath == devicePath &&
                (t.status == TransferStatus.queued ||
                    t.status == TransferStatus.inProgress));
        if (!anyLeft) break;
        final waker = Completer<void>();
        _writerWakers[devicePath] = waker;
        await waker.future;
        continue;
      }

      if (q == null || q.isEmpty) {
        // Nothing staged. Exit only if no download will ever stage more.
        final anyActive = state.any((t) =>
            t.devicePath == devicePath &&
            (t.status == TransferStatus.queued ||
                t.status == TransferStatus.inProgress));
        if (!anyActive) break;
        final waker = Completer<void>();
        _writerWakers[devicePath] = waker;
        await waker.future;
        continue;
      }

      final unit = q.removeAt(0);
      // Backlog decreased → let the downloader stage more.
      _wakeEngine(devicePath);
      try {
        if (unit.isZip) {
          await _writeZip(unit);
        } else {
          await _writeSong(unit);
        }
      } catch (e) {
        dev.log('TransferQueueNotifier: writer failed for '
            '${unit.isZip ? 'zip ${unit.groupId}' : unit.targetPath} — $e');
      }
    }

    _writerRunning.remove(devicePath);
  }

  // Stage 1 for a single song: downloads into the internal staging dir, then
  // hands off to a DETACHED [_stageSong] (post-process on the staging copy)
  // that enqueues the write unit. Returning at download-end frees the engine's
  // download slot so the network stays saturated while the sequential writer
  // copies earlier songs onto the device.
  Future<void> _downloadSong(TransferTask task) async {
    _updateTask(task.id, (t) => t.copyWith(status: TransferStatus.inProgress));

    final cancelToken = CancelToken();
    _cancelTokens[task.id] = cancelToken;

    final settings = ref.read(deviceSettingsProvider(task.devicePath));
    final targetPath = buildSongPath(task.song, settings);
    final albumFolder = p.dirname(targetPath);
    String? stagingPath;

    try {
      if (!settings.overwriteExisting && await File(targetPath).exists()) {
        _cancelTokens.remove(task.id);
        _appendManifest(albumFolder, task.song,
            expectedSongCount: _expectedSongCounts[albumFolder],
            filename: p.basename(targetPath));
        // Already on device: no download / write needed.
        _markCompleted(task.id);
        _onGroupTaskDone(task.id);
        return;
      }

      // URL is computed at execution time so transcoding-setting changes
      // applied between enqueue and run take effect on later tasks. If the
      // library repo is unavailable (server switched mid-flight, no server),
      // mark this task as failed rather than crashing.
      final repo = ref.read(libraryRepositoryProvider);
      if (repo == null) {
        _failSong(task.id, 'No active server');
        return;
      }

      final supportDir = ref.read(appSupportDirProvider);
      stagingPath =
          _stagingPathFor(supportDir, task.id, p.extension(targetPath));
      await Directory(p.dirname(stagingPath)).create(recursive: true);

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
        stagingPath,
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
      // Download done — drop cancel token + progress. Task stays inProgress
      // (so activeCount still counts it) until the writer marks it completed.
      _cancelTokens.remove(task.id);
      _lastProgressMs.remove(task.id);
      _clearProgressEntry(task.id);
      unawaited(_stageSong(task, stagingPath, targetPath, settings, albumFolder));
    } on DioException catch (e) {
      _cancelTokens.remove(task.id);
      _lastProgressMs.remove(task.id);
      _clearProgressEntry(task.id);
      if (stagingPath != null) await _deleteStagingFile(stagingPath);
      if (CancelToken.isCancel(e)) {
        _onGroupTaskDone(task.id); // already marked cancelled by cancel()
        return;
      }
      _failSong(task.id, e.message);
    } catch (e) {
      _cancelTokens.remove(task.id);
      _lastProgressMs.remove(task.id);
      _clearProgressEntry(task.id);
      if (stagingPath != null) await _deleteStagingFile(stagingPath);
      final msg = e.toString();
      final isPermission = msg.contains('errno = 1') ||
          msg.contains('Operation not permitted') ||
          msg.contains('errno = 13') ||
          msg.contains('Permission denied');
      _failSong(task.id, isPermission ? 'permission_denied' : msg);
    }
  }

  // Post-processes the staging copy (tag clean / cover shrink — content edits
  // done on the fast internal disk), bounded by [_postProcessSem], then queues
  // the unit for the sequential device-writer. If the task was cancelled /
  // failed meanwhile, the staged file is dropped instead of written.
  Future<void> _stageSong(
    TransferTask task,
    String stagingPath,
    String targetPath,
    DeviceSettings settings,
    String albumFolder,
  ) async {
    await _postProcessSem.acquire();
    try {
      if (settings.autoCleanMetadata) await sanitizeFlacTags(stagingPath);
      if (settings.autoShrinkCoverArt) {
        await shrinkFlacEmbeddedPicture(stagingPath);
      }
    } catch (e) {
      dev.log('TransferQueueNotifier: staging post-process failed for '
          '$stagingPath — $e');
    } finally {
      _postProcessSem.release();
    }

    final cur = _taskById(task.id);
    if (cur == null ||
        cur.status == TransferStatus.cancelled ||
        cur.status == TransferStatus.failed) {
      await _deleteStagingFile(stagingPath);
      _onGroupTaskDone(task.id);
      return;
    }
    _enqueueWrite(
      task.devicePath,
      _StagedUnit.song(
        task: task,
        stagingPath: stagingPath,
        targetPath: targetPath,
        albumFolder: albumFolder,
      ),
    );
  }

  // Stage 2 for a single song: copies the staged file onto the device (the one
  // slow write allowed at a time), strips the macOS sidecar, appends the
  // manifest, and marks the task completed. Always deletes the staging copy.
  Future<void> _writeSong(_StagedUnit unit) async {
    final task = unit.task!;
    final stagingPath = unit.stagingPath!;
    final targetPath = unit.targetPath!;

    final cur = _taskById(task.id);
    if (cur == null ||
        cur.status == TransferStatus.cancelled ||
        cur.status == TransferStatus.failed) {
      await _deleteStagingFile(stagingPath);
      _onGroupTaskDone(task.id);
      return;
    }

    try {
      await Directory(unit.albumFolder!).create(recursive: true);
      await _copyToDevice(stagingPath, targetPath, task.id);
      await removeMacOSSidecar(targetPath);
      _appendManifest(
        unit.albumFolder!,
        task.song,
        expectedSongCount: _expectedSongCounts[unit.albumFolder!],
        filename: p.basename(targetPath),
      );
      _markCompleted(task.id);
      _onGroupTaskDone(task.id);
    } catch (e) {
      // Leave no half-written file on the device.
      try {
        final f = File(targetPath);
        if (await f.exists()) await f.delete();
      } catch (_) {}
      final msg = e.toString();
      final isPermission = msg.contains('errno = 1') ||
          msg.contains('Operation not permitted') ||
          msg.contains('errno = 13') ||
          msg.contains('Permission denied');
      _failSong(task.id, isPermission ? 'permission_denied' : msg);
    } finally {
      await _deleteStagingFile(stagingPath);
      _clearProgressEntry(task.id);
    }
  }

  // Streams staging → device in chunks so the (slow) device write shows a live
  // progress bar and the whole file isn't buffered in memory. openWrite
  // truncates any existing file, which is what overwrite mode wants; the
  // skip-if-exists case never reaches the writer.
  Future<void> _copyToDevice(
      String src, String dst, String taskId) async {
    final total = await File(src).length();
    final sink = File(dst).openWrite();
    var written = 0;
    try {
      await for (final chunk in File(src).openRead()) {
        sink.add(chunk);
        written += chunk.length;
        final now = DateTime.now().millisecondsSinceEpoch;
        if (total > 0 && (now - (_lastProgressMs[taskId] ?? 0)) >= 200) {
          _lastProgressMs[taskId] = now;
          final clamped = written > total ? total : written;
          ref.read(transferProgressProvider.notifier).update(
              (m) => {...m, taskId: (clamped, total)});
        }
      }
      await sink.flush();
    } finally {
      await sink.close();
      _lastProgressMs.remove(taskId);
    }
  }

  TransferTask? _taskById(String id) =>
      state.where((t) => t.id == id).firstOrNull;

  // ── Staging helpers ─────────────────────────────────────────────────────────

  String _stagingDir(String supportDir) => p.join(supportDir, 'staging');

  String _stagingPathFor(String supportDir, String taskId, String ext) =>
      p.join(_stagingDir(supportDir), '$taskId$ext');

  Future<void> _deleteStagingFile(String path) async {
    try {
      final f = File(path);
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }

  /// Deletes leftover staged download files from a previous run that didn't
  /// finish writing — typically a crash or forced quit. Their tasks were reset
  /// to `queued` on load, so they'll re-download cleanly.
  void _cleanStaging(String supportDir) {
    try {
      final dir = Directory(_stagingDir(supportDir));
      if (!dir.existsSync()) return;
      for (final e in dir.listSync()) {
        if (e is File) {
          try {
            e.deleteSync();
          } catch (_) {}
        }
      }
    } catch (_) {}
  }

  // ── Zip album path ─────────────────────────────────────────────────────────
  // Split across the two stages: [_downloadZip] fetches `/rest/download?id=
  // {albumId}` once into staging (parallel with other downloads), then queues a
  // zip unit; [_writeZip] extracts it onto the device through the sequential
  // writer so album writes never overlap another device write.

  /// Stage 1 for a zip album: transcoding fallback, on-device short-circuit,
  /// disk precheck, then downloads the album zip into the app-support tmp dir
  /// and queues it for the sequential writer. Mirror progress entries for every
  /// sibling advance with the leader's download and stay in place (at 100%)
  /// until the writer drops them as each file lands.
  Future<void> _downloadZip(TransferTask leader) async {
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
    final memberIds = groupTasks.map((t) => t.id).toList(growable: false);

    var downloaded = false;
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
          _cancelGroupInFlight(groupId);
          return;
        }
        final required = (estimatedTotal * 11) ~/ 10;
        if (tmpFree != null && tmpFree < required) {
          _failGroup(groupId,
              'Not enough free space in app data for ${formatBytes(required)} '
              'zip (${formatBytes(tmpFree)} available)');
          return;
        }
        if (deviceFree != null && deviceFree < required) {
          _failGroup(groupId,
              'Not enough free space on device for ${formatBytes(required)} '
              '(${formatBytes(deviceFree)} available)');
          return;
        }
      }

      final url = repo.zipUri(albumId).toString();
      // memberIds drives the mirrored progress writes so every sibling's bar
      // advances in step with the leader. Without mirroring, only the leader's
      // row had a moving bar.
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
      downloaded = true;
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) {
        _cancelGroupInFlight(groupId);
      } else {
        _failGroup(groupId, e.message ?? 'Download failed');
      }
    } catch (e) {
      _failGroup(groupId, e.toString());
    } finally {
      _cancelTokens.remove(leader.id);
      _lastProgressMs.remove(leader.id);
      if (!downloaded) {
        // Failed / cancelled before staging: scrub mirrored progress + tmp zip.
        _scrubProgress(memberIds);
        if (await tmpZip.exists()) {
          try {
            await tmpZip.delete();
          } catch (_) {}
        }
      }
    }

    if (downloaded) {
      _enqueueWrite(
        devicePath,
        _StagedUnit.zip(
          groupId: groupId,
          zipStagingPath: tmpZip.path,
          groupTasks: groupTasks,
        ),
      );
    }
  }

  /// Stage 2 for a zip album: extracts the staged zip onto the device in a
  /// background isolate at concurrency 1, so album writes are sequential and
  /// never overlap another device write. Siblings flip queued → completed as
  /// their files land; unmatched siblings fail. Always scrubs mirror progress
  /// and deletes the staged zip.
  Future<void> _writeZip(_StagedUnit unit) async {
    final groupId = unit.groupId!;
    final groupTasks = unit.groupTasks!;
    final tmpZip = File(unit.zipStagingPath!);
    final devicePath = groupTasks.first.devicePath;
    final settings = ref.read(deviceSettingsProvider(devicePath));
    final expectedSongs = groupTasks.map((t) => t.song).toList();
    final memberIds = groupTasks.map((t) => t.id).toList(growable: false);

    // Cancelled while staged-waiting? Skip extraction entirely.
    final anyLive = groupTasks.any((t) {
      final c = _taskById(t.id);
      return c != null && c.status == TransferStatus.inProgress;
    });
    if (!anyLive) {
      _scrubProgress(memberIds);
      if (await tmpZip.exists()) {
        try {
          await tmpZip.delete();
        } catch (_) {}
      }
      return;
    }

    try {
      final args = <String, dynamic>{
        'zipPath': tmpZip.path,
        'songs': [for (final s in expectedSongs) songToMap(s)],
        'settings': settingsToMap(settings),
        'removeMacosSidecars': Platform.isMacOS,
        // Sequential: one write to the device at a time (the writer already
        // serialises whole units; this keeps a single album sequential too).
        'concurrency': 1,
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

      // Sibling completions are accumulated and flushed in batches rather than
      // one `state.map().toList()` per extracted file. A large artist zip emits
      // hundreds of 'extracted' messages; flipping each one individually is
      // O(N) per message → O(N²) list reallocations. Coalescing to a ~150 ms
      // throttle collapses that to one pass per tick. completedIds is still
      // populated immediately so the post-loop failure detection is accurate.
      final pendingFlip = <String>{};
      final pendingProgressDrop = <String>{};
      final ppFutures = <Future<void>>[];
      var lastFlushMs = 0;
      void flushFlips({bool force = false}) {
        if (pendingFlip.isEmpty && pendingProgressDrop.isEmpty) return;
        final now = DateTime.now().millisecondsSinceEpoch;
        if (!force && now - lastFlushMs < 150) return;
        lastFlushMs = now;
        if (pendingFlip.isNotEmpty) {
          final ids = Set<String>.of(pendingFlip);
          pendingFlip.clear();
          // Only flip siblings still inProgress so a cancel that landed during
          // post-process isn't clobbered back to completed.
          state = state
              .map((t) => ids.contains(t.id) &&
                      t.status == TransferStatus.inProgress
                  ? t.copyWith(status: TransferStatus.completed)
                  : t)
              .toList();
        }
        if (pendingProgressDrop.isNotEmpty) {
          final drop = Set<String>.of(pendingProgressDrop);
          pendingProgressDrop.clear();
          ref.read(transferProgressProvider.notifier).update((m) {
            Map<String, (int, int)>? next;
            for (final id in drop) {
              if (m.containsKey(id)) {
                next ??= Map.of(m);
                next.remove(id);
              }
            }
            return next ?? m;
          });
        }
      }

      try {
        await for (final msg in receivePort) {
          if (msg is! Map) continue;
          final type = msg['type'];
          if (type == 'extracted') {
            final songId = msg['songId'] as String;
            final targetPath = msg['targetPath'] as String;
            final expectedCount = msg['expectedCount'] as int?;
            final sibling =
                groupTasks.firstWhere((t) => t.song.id == songId);

            completedIds.add(sibling.id);
            ppFutures.add(_postProcessExtracted(targetPath, settings).then((_) {
              pendingFlip.add(sibling.id);
              pendingProgressDrop.add(sibling.id);
              flushFlips();
            }));

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
      await Future.wait(ppFutures);
      flushFlips(force: true);

      // Cancelled during extraction (cancel() flips group members to cancelled)
      // → don't write manifests, leave the cancelled state as-is.
      final cancelled = groupTasks.any((t) =>
          _taskById(t.id)?.status == TransferStatus.cancelled);
      if (cancelled) {
        _cancelGroupInFlight(groupId);
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
    } catch (e) {
      _failGroup(groupId, e.toString());
    } finally {
      _scrubProgress(memberIds);
      if (await tmpZip.exists()) {
        try {
          await tmpZip.delete();
        } catch (_) {}
      }
    }
  }

  // Flips any still-queued / inProgress member of [groupId] to cancelled.
  void _cancelGroupInFlight(String groupId) {
    state = state
        .map((t) => t.zipGroupId == groupId &&
                (t.status == TransferStatus.queued ||
                    t.status == TransferStatus.inProgress)
            ? t.copyWith(status: TransferStatus.cancelled)
            : t)
        .toList();
  }

  // Drops the given task ids from the progress provider in one update.
  void _scrubProgress(List<String> ids) {
    ref.read(transferProgressProvider.notifier).update((m) {
      Map<String, (int, int)>? next;
      for (final id in ids) {
        if (m.containsKey(id)) {
          next ??= Map.of(m);
          next.remove(id);
        }
      }
      return next ?? m;
    });
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
    // Leading-suppress + trailing fire: the first bump schedules a single
    // notification ~300 ms out; further bumps in that window are folded in.
    // A bulk transfer thus rebuilds "on device" indicators at ~3 Hz instead of
    // once per song.
    if (_manifestBumpTimer != null) return;
    _manifestBumpTimer = Timer(const Duration(milliseconds: 300), () {
      _manifestBumpTimer = null;
      ref.read(manifestRevisionProvider.notifier).update((v) => v + 1);
    });
  }

  void _updateTask(String id, TransferTask Function(TransferTask) update) {
    state = state.map((t) => t.id == id ? update(t) : t).toList();
  }

  // ── Post-process + completion plumbing ──────────────────────────────────────

  /// Detached post-process for a zip-extracted file (sidecar already handled
  /// inside the extraction isolate). Shares the same bounded pool as the
  /// per-song path so extraction and post-processing overlap instead of
  /// serialising message-by-message.
  Future<void> _postProcessExtracted(
      String targetPath, DeviceSettings settings) async {
    await _postProcessSem.acquire();
    try {
      if (settings.autoCleanMetadata) await sanitizeFlacTags(targetPath);
      if (settings.autoShrinkCoverArt) {
        await shrinkFlacEmbeddedPicture(targetPath);
      }
    } catch (e) {
      dev.log('TransferQueueNotifier: zip post-process failed for '
          '$targetPath — $e');
    } finally {
      _postProcessSem.release();
    }
  }

  void _failSong(String id, String? message) {
    final devicePath = _taskById(id)?.devicePath;
    _updateTask(id, (t) => t.copyWith(
          status: TransferStatus.failed,
          errorMessage: message,
        ));
    _onGroupTaskDone(id);
    // A sleeping writer / downloader may now be able to exit (this was the
    // last active task) — nudge it to re-check.
    if (devicePath != null) _wakeDevice(devicePath);
  }

  // Wakes both loops for a device so they re-evaluate their exit conditions
  // after a terminal state change (completed / failed / cancelled).
  void _wakeDevice(String devicePath) {
    _wakeWriter(devicePath);
    _wakeEngine(devicePath);
  }

  void _clearProgressEntry(String id) {
    ref.read(transferProgressProvider.notifier).update((m) {
      if (!m.containsKey(id)) return m;
      return Map.of(m)..remove(id);
    });
  }

  /// Queues a completed-status flip, coalescing bursts into one rebuild per
  /// ~120 ms. Only flips tasks still inProgress, so a cancel/fail that landed
  /// during post-process is never clobbered back to completed.
  void _markCompleted(String id) {
    _pendingCompleted.add(id);
    _completedFlushTimer ??=
        Timer(const Duration(milliseconds: 120), _flushCompleted);
  }

  void _flushCompleted() {
    _completedFlushTimer = null;
    if (_pendingCompleted.isEmpty) return;
    final ids = Set<String>.of(_pendingCompleted);
    _pendingCompleted.clear();
    final devices = <String>{};
    state = state.map((t) {
      if (ids.contains(t.id) && t.status == TransferStatus.inProgress) {
        devices.add(t.devicePath);
        return t.copyWith(status: TransferStatus.completed);
      }
      return t;
    }).toList();
    // The throttled flip means a just-written task was still inProgress when
    // the writer looped; now it's completed, wake the loops so they can exit.
    for (final d in devices) {
      _wakeDevice(d);
    }
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
