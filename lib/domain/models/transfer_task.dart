import 'package:freezed_annotation/freezed_annotation.dart';
import 'song.dart';

part 'transfer_task.freezed.dart';

enum TransferStatus { queued, inProgress, completed, failed, cancelled }

@freezed
class TransferTask with _$TransferTask {
  const factory TransferTask({
    required String id,
    required Song song,
    required String devicePath,
    @Default(TransferStatus.queued) TransferStatus status,
    @Default(0) int bytesReceived,
    @Default(0) int totalBytes,
    String? errorMessage,
    /// Non-null when this task is part of a bulk-zip group. All tasks in the
    /// group share the same id; the engine processes the group as a single
    /// download + extract operation.
    String? zipGroupId,
    /// Album/artist id passed to /rest/download. Only set on the "leader"
    /// task within a [zipGroupId] — the leader's execution drives the zip
    /// fetch and dispatches each extracted entry to its sibling task.
    String? zipSourceId,
  }) = _TransferTask;

  const TransferTask._();

  double get progress =>
      totalBytes > 0 ? bytesReceived / totalBytes : 0;

  bool get isZipMember => zipGroupId != null;
  bool get isZipLeader => zipSourceId != null;
}
