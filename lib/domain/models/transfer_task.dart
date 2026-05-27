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
  }) = _TransferTask;

  const TransferTask._();

  double get progress =>
      totalBytes > 0 ? bytesReceived / totalBytes : 0;
}
