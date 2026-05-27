import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../../domain/models/playlist.dart';
import '../../domain/models/song.dart';
import '../../domain/models/transfer_task.dart';
import '../device/device_settings_notifier.dart';
import '../providers/providers.dart';
import 'playlist_sync_writer.dart';
import 'transfer_path_resolver.dart';

class TransferQueueNotifier extends Notifier<List<TransferTask>> {
  static const _uuid = Uuid();

  final _cancelTokens = <String, CancelToken>{};
  bool _engineRunning = false;

  @override
  List<TransferTask> build() => [];

  // ── Public API ────────────────────────────────────────────────────────────

  void enqueue(List<Song> songs, String devicePath, Uri Function(String) downloadUri) {
    final newTasks = songs.map((s) => TransferTask(
          id: _uuid.v4(),
          song: s,
          devicePath: devicePath,
        )).toList();

    state = [...state, ...newTasks];
    _startEngineIfIdle(downloadUri);
  }

  Future<void> enqueuePlaylist(
    Playlist playlist,
    String devicePath,
    Uri Function(String) downloadUri,
  ) async {
    // Write the M3U immediately so it's ready when songs arrive.
    final settings = ref.read(deviceSettingsProvider(devicePath));
    enqueue(playlist.songs, devicePath, downloadUri);
    await writePlaylistM3u(playlist, settings);
  }

  void cancel(String taskId) {
    _cancelTokens[taskId]?.cancel('User cancelled');
    state = state.map((t) => t.id == taskId
        ? t.copyWith(status: TransferStatus.cancelled)
        : t).toList();
  }

  void retry(String taskId) {
    final repo = ref.read(libraryRepositoryProvider);
    if (repo == null) return;
    state = [
      for (final t in state)
        if (t.id == taskId && t.status == TransferStatus.failed)
          t.copyWith(
              status: TransferStatus.queued,
              errorMessage: null,
              bytesReceived: 0,
              totalBytes: 0)
        else
          t,
    ];
    _startEngineIfIdle(repo.downloadUri);
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

  void _startEngineIfIdle(Uri Function(String) downloadUri) {
    if (_engineRunning) return;
    _runEngine(downloadUri);
  }

  Future<void> _runEngine(Uri Function(String) downloadUri) async {
    _engineRunning = true;
    while (true) {
      final next = state.where((t) => t.status == TransferStatus.queued).firstOrNull;
      if (next == null) break;
      await _executeTask(next, downloadUri);
    }
    _engineRunning = false;
  }

  Future<void> _executeTask(TransferTask task, Uri Function(String) downloadUri) async {
    _updateTask(task.id, (t) => t.copyWith(status: TransferStatus.inProgress));

    final cancelToken = CancelToken();
    _cancelTokens[task.id] = cancelToken;

    try {
      final settings = ref.read(deviceSettingsProvider(task.devicePath));
      final targetPath = buildSongPath(task.song, settings);

      if (!settings.overwriteExisting && File(targetPath).existsSync()) {
        _updateTask(task.id, (t) => t.copyWith(status: TransferStatus.completed));
        return;
      }

      await Directory(p.dirname(targetPath)).create(recursive: true);

      final dio = Dio();
      final url = downloadUri(task.song.id).toString();

      await dio.download(
        url,
        targetPath,
        cancelToken: cancelToken,
        onReceiveProgress: (received, total) {
          if (total <= 0) return;
          _updateTask(task.id, (t) => t.copyWith(
                bytesReceived: received,
                totalBytes: total,
              ));
        },
      );

      _updateTask(task.id, (t) => t.copyWith(
            status: TransferStatus.completed,
            bytesReceived: t.totalBytes,
          ));
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
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  void _updateTask(String id, TransferTask Function(TransferTask) update) {
    state = state.map((t) => t.id == id ? update(t) : t).toList();
  }
}

// ── Computed selectors ────────────────────────────────────────────────────────

extension TransferQueueSelectors on List<TransferTask> {
  int get activeCount =>
      where((t) => t.status == TransferStatus.inProgress || t.status == TransferStatus.queued).length;

  int get completedCount => where((t) => t.status == TransferStatus.completed).length;

  double get aggregateProgress {
    final active = where((t) =>
        t.status == TransferStatus.inProgress || t.status == TransferStatus.queued);
    if (active.isEmpty) return 0;
    final totalBytes = active.fold<int>(0, (s, t) => s + t.totalBytes);
    final receivedBytes = active.fold<int>(0, (s, t) => s + t.bytesReceived);
    if (totalBytes <= 0) return 0;
    return receivedBytes / totalBytes;
  }
}
