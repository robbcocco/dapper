import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers/providers.dart';
import '../../domain/models/transfer_task.dart';
import 'confirm_dialog.dart';

/// Asks the active [DriveDetector] to unmount [devicePath]. If transfers are
/// queued or in flight for this device the user is prompted to cancel them
/// first; result is reported via a SnackBar.
Future<void> ejectConnectedDevice(
    BuildContext context, WidgetRef ref, String devicePath) async {
  final queue = ref.read(transferQueueProvider);
  final hasActive = queue.any((t) =>
      t.devicePath == devicePath &&
      (t.status == TransferStatus.queued ||
          t.status == TransferStatus.inProgress));
  if (hasActive) {
    final ok = await showConfirmDialog(
      context,
      title: 'Eject anyway?',
      message:
          'Transfers are still queued or in progress for this device. '
          'Ejecting now will cancel them.',
      confirmLabel: 'Cancel & eject',
      destructive: true,
    );
    if (!ok) return;
    ref.read(transferQueueProvider.notifier).cancelAll(devicePath: devicePath);
  }
  final detector = ref.read(driveDetectorProvider);
  final result = await detector.eject(devicePath);
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(result.success
          ? 'Ejected $devicePath'
          : 'Eject failed: ${result.error ?? 'unknown error'}'),
      duration: const Duration(seconds: 3),
    ),
  );
}
