import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../application/device/device_settings_notifier.dart';
import '../../../application/providers/providers.dart';
import '../../../application/transfer/transfer_queue_notifier.dart';
import '../../../core/theme/color_tokens.dart';
import '../../../domain/models/transfer_task.dart';
import 'device_file_browser.dart';
import 'device_settings_dialog.dart';

class DevicePage extends ConsumerWidget {
  const DevicePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final devicesAsync = ref.watch(connectedDevicesProvider);

    return devicesAsync.when(
      data: (devices) =>
          devices.isEmpty ? const _NoDevice() : const _DeviceView(),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Text('$e',
            style: const TextStyle(color: ColorTokens.textSecondary)),
      ),
    );
  }
}

class _NoDevice extends StatelessWidget {
  const _NoDevice();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.usb, size: 48, color: ColorTokens.textSecondary),
          SizedBox(height: 16),
          Text('No device connected',
              style:
                  TextStyle(fontSize: 16, color: ColorTokens.textSecondary)),
          SizedBox(height: 8),
          Text('Connect a USB drive or SD card to get started',
              style:
                  TextStyle(fontSize: 12, color: ColorTokens.textSecondary)),
        ],
      ),
    );
  }
}

class _DeviceView extends ConsumerStatefulWidget {
  const _DeviceView();

  @override
  ConsumerState<_DeviceView> createState() => _DeviceViewState();
}

class _DeviceViewState extends ConsumerState<_DeviceView>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selected = ref.watch(selectedDeviceProvider);
    final queue = ref.watch(transferQueueProvider);
    final settings = selected != null
        ? ref.watch(deviceSettingsProvider(selected.path))
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Header ──────────────────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.fromLTRB(20, 10, 12, 10),
          decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: ColorTokens.glassBorder))),
          child: Row(
            children: [
              Icon(
                Icons.usb,
                size: 15,
                color: selected != null
                    ? ColorTokens.accent
                    : ColorTokens.textSecondary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  selected?.label ?? 'Select a device from the sidebar',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: selected != null
                        ? FontWeight.w600
                        : FontWeight.normal,
                    color: selected != null
                        ? ColorTokens.textPrimary
                        : ColorTokens.textSecondary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (selected != null)
                IconButton(
                  icon: const Icon(Icons.settings_outlined,
                      size: 16, color: ColorTokens.textSecondary),
                  tooltip: 'Device settings',
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 32, minHeight: 32),
                  onPressed: () =>
                      DeviceSettingsDialog.show(context, selected.path),
                ),
            ],
          ),
        ),

        // ── Capacity bar ─────────────────────────────────────────────────────
        if (selected != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 10, 24, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: selected.usedFraction,
                    backgroundColor: ColorTokens.surfaceVariant,
                    valueColor:
                        const AlwaysStoppedAnimation(ColorTokens.accent),
                    minHeight: 6,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(
                      '${selected.availableFormatted} available of ${selected.totalFormatted}',
                      style: const TextStyle(
                          fontSize: 11, color: ColorTokens.textSecondary),
                    ),
                    if (settings != null &&
                        settings.musicRootFolder.isNotEmpty) ...[
                      const Spacer(),
                      Text(
                        'Root: ${settings.musicRootFolder}',
                        style: const TextStyle(
                            fontSize: 10, color: ColorTokens.textSecondary),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),

        // ── Tabs ─────────────────────────────────────────────────────────────
        Container(
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: ColorTokens.glassBorder)),
          ),
          child: TabBar(
          controller: _tabController,
          labelColor: ColorTokens.accent,
          unselectedLabelColor: ColorTokens.textSecondary,
          indicatorColor: ColorTokens.accent,
          indicatorSize: TabBarIndicatorSize.label,
          labelStyle: const TextStyle(fontSize: 12),
          tabs: [
            const Tab(text: 'On Device'),
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Transfer Queue'),
                  if (queue.activeCount > 0) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: ColorTokens.accent,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${queue.activeCount}',
                        style: const TextStyle(
                            fontSize: 9, color: Colors.white),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        ),

        // ── Tab content ───────────────────────────────────────────────────────
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              // On Device
              selected == null
                  ? const Center(
                      child: Text('Select a device above',
                          style: TextStyle(color: ColorTokens.textSecondary)))
                  : DeviceFileBrowser(
                      rootPath: settings?.resolvedMusicRoot ?? selected.path,
                    ),

              // Transfer Queue
              queue.isEmpty
                  ? const _EmptyQueue()
                  : _QueueList(queue: queue),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Empty queue ───────────────────────────────────────────────────────────────

class _EmptyQueue extends StatelessWidget {
  const _EmptyQueue();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.queue_music, size: 40, color: ColorTokens.textSecondary),
          SizedBox(height: 12),
          Text('No transfers queued',
              style:
                  TextStyle(fontSize: 14, color: ColorTokens.textSecondary)),
          SizedBox(height: 6),
          Text('Right-click songs or albums in the library to add them',
              style:
                  TextStyle(fontSize: 11, color: ColorTokens.textSecondary)),
        ],
      ),
    );
  }
}

// ── Queue list ────────────────────────────────────────────────────────────────

class _QueueList extends ConsumerWidget {
  const _QueueList({required this.queue});
  final List<TransferTask> queue;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasPermissionError =
        queue.any((t) => t.errorMessage == 'permission_denied');

    return Column(
      children: [
        // ── Permission error banner ───────────────────────────────────────────
        if (hasPermissionError)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.redAccent.withValues(alpha: 0.12),
              border: Border.all(color: Colors.redAccent.withValues(alpha: 0.4)),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                const Icon(Icons.lock_outline,
                    size: 16, color: Colors.redAccent),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'macOS blocked write access to the device.\n'
                    'Grant Full Disk Access to Dapper in System Settings.',
                    style: TextStyle(fontSize: 11, color: Colors.redAccent),
                  ),
                ),
                const SizedBox(width: 10),
                TextButton(
                  onPressed: _openPrivacySettings,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    minimumSize: Size.zero,
                  ),
                  child: const Text('Open Settings',
                      style:
                          TextStyle(fontSize: 11, color: Colors.redAccent)),
                ),
              ],
            ),
          ),

        // ── Clear finished button ─────────────────────────────────────────────
        if (queue.any((t) =>
            t.status == TransferStatus.completed ||
            t.status == TransferStatus.cancelled ||
            t.status == TransferStatus.failed))
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 6, 24, 0),
            child: Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () =>
                    ref.read(transferQueueProvider.notifier).clearCompleted(),
                child: const Text('Clear finished',
                    style: TextStyle(
                        fontSize: 11, color: ColorTokens.textSecondary)),
              ),
            ),
          ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: queue.length,
            itemBuilder: (context, i) => _TaskRow(task: queue[i]),
          ),
        ),
      ],
    );
  }

  void _openPrivacySettings() {
    Process.run('open', [
      'x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles',
    ]);
  }
}

class _TaskRow extends ConsumerWidget {
  const _TaskRow({required this.task});
  final TransferTask task;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 6),
      decoration: const BoxDecoration(
        border: Border(
            bottom: BorderSide(color: ColorTokens.divider, width: 0.5)),
      ),
      child: Row(
        children: [
          _StatusIcon(status: task.status),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(task.song.title,
                    style: const TextStyle(
                        fontSize: 12, color: ColorTokens.textPrimary),
                    overflow: TextOverflow.ellipsis),
                if (task.status == TransferStatus.inProgress)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: LinearProgressIndicator(
                      value: task.progress,
                      backgroundColor: ColorTokens.surfaceVariant,
                      valueColor:
                          const AlwaysStoppedAnimation(ColorTokens.accent),
                      minHeight: 3,
                    ),
                  )
                else
                  Text(
                    _statusLabel(task.status, task.errorMessage),
                    style: TextStyle(
                        fontSize: 10, color: _statusColor(task.status)),
                  ),
              ],
            ),
          ),
          if (task.status == TransferStatus.queued ||
              task.status == TransferStatus.inProgress)
            IconButton(
              icon: const Icon(Icons.close,
                  size: 14, color: ColorTokens.textSecondary),
              onPressed: () =>
                  ref.read(transferQueueProvider.notifier).cancel(task.id),
              padding: EdgeInsets.zero,
              constraints:
                  const BoxConstraints(minWidth: 24, minHeight: 24),
            )
          else if (task.status == TransferStatus.failed)
            IconButton(
              icon: const Icon(Icons.refresh,
                  size: 14, color: ColorTokens.textSecondary),
              tooltip: 'Retry',
              onPressed: () =>
                  ref.read(transferQueueProvider.notifier).retry(task.id),
              padding: EdgeInsets.zero,
              constraints:
                  const BoxConstraints(minWidth: 24, minHeight: 24),
            ),
        ],
      ),
    );
  }

  String _statusLabel(TransferStatus s, String? error) => switch (s) {
        TransferStatus.queued => 'Waiting…',
        TransferStatus.inProgress => '',
        TransferStatus.completed => 'Done',
        TransferStatus.failed =>
          error == 'permission_denied' ? 'Permission denied' : (error ?? 'Failed'),
        TransferStatus.cancelled => 'Cancelled',
      };

  Color _statusColor(TransferStatus s) => switch (s) {
        TransferStatus.completed => Colors.green,
        TransferStatus.failed => Colors.redAccent,
        _ => ColorTokens.textSecondary,
      };
}

class _StatusIcon extends StatelessWidget {
  const _StatusIcon({required this.status});
  final TransferStatus status;

  @override
  Widget build(BuildContext context) => switch (status) {
        TransferStatus.queued => const Icon(Icons.schedule,
            size: 16, color: ColorTokens.textSecondary),
        TransferStatus.inProgress => const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation(ColorTokens.accent)),
          ),
        TransferStatus.completed =>
          const Icon(Icons.check_circle, size: 16, color: Colors.green),
        TransferStatus.failed =>
          const Icon(Icons.error_outline, size: 16, color: Colors.redAccent),
        TransferStatus.cancelled => const Icon(Icons.cancel_outlined,
            size: 16, color: ColorTokens.textSecondary),
      };
}
