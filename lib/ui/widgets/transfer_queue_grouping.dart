import '../../domain/models/transfer_task.dart';

/// One row in the transfer queue list. Either a stand-alone task or a bucket
/// of tasks that share a `zipGroupId` (one album transfer).
class QueueRow {
  const QueueRow.single(TransferTask task)
      : single = task,
        group = null;
  const QueueRow.group(List<TransferTask> tasks)
      : single = null,
        group = tasks;
  final TransferTask? single;
  final List<TransferTask>? group;
}

/// Buckets [queue] by `zipGroupId`. Order is preserved by first-occurrence;
/// non-zip tasks render as `QueueRow.single`.
List<QueueRow> buildQueueRows(List<TransferTask> queue) {
  final rows = <QueueRow>[];
  final seenGroups = <String>{};
  for (final t in queue) {
    final gid = t.zipGroupId;
    if (gid == null) {
      rows.add(QueueRow.single(t));
      continue;
    }
    if (seenGroups.contains(gid)) continue;
    seenGroups.add(gid);
    final members = queue.where((x) => x.zipGroupId == gid).toList();
    rows.add(QueueRow.group(members));
  }
  return rows;
}

/// Reduces a set of zip-group member statuses to one display status.
TransferStatus aggregateStatus(Iterable<TransferTask> tasks) {
  var hasFailed = false;
  var hasInProgress = false;
  var hasQueued = false;
  var hasCancelled = false;
  var allCompleted = true;
  for (final t in tasks) {
    if (t.status != TransferStatus.completed) allCompleted = false;
    switch (t.status) {
      case TransferStatus.failed:
        hasFailed = true;
      case TransferStatus.inProgress:
        hasInProgress = true;
      case TransferStatus.queued:
        hasQueued = true;
      case TransferStatus.cancelled:
        hasCancelled = true;
      case TransferStatus.completed:
        break;
    }
  }
  if (hasFailed) return TransferStatus.failed;
  if (hasInProgress) return TransferStatus.inProgress;
  if (hasQueued) return TransferStatus.queued;
  if (allCompleted) return TransferStatus.completed;
  if (hasCancelled) return TransferStatus.cancelled;
  return TransferStatus.completed;
}
