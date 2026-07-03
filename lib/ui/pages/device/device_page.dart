import 'dart:io';

import 'package:path/path.dart' as p;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../application/device/device_prune.dart';
import '../../../application/device/device_scan.dart';
import '../../../application/device/device_settings_notifier.dart';
import '../../../application/device/device_tag_sanitize.dart';
import '../../../application/playback/scrobble_importer.dart';
import '../../../application/providers/providers.dart';
import '../../../application/transfer/transfer_queue_notifier.dart';
import '../../../core/format/byte_format.dart';
import '../../../core/theme/color_tokens.dart';
import '../../../domain/models/device_settings.dart';
import '../../../domain/models/transfer_task.dart';
import '../../../domain/repositories/library_repository.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/device_eject.dart';
import '../../widgets/transfer_queue_grouping.dart';
import 'device_file_browser.dart';
import 'device_settings_dialog.dart';
import 'library_sync_dialog.dart';

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
    // NOTE: deliberately NOT watching transferQueueProvider here. Doing so
    // rebuilt the entire device page (header, tabs, file browser, scan UI) on
    // every transfer status tick. The two queue-dependent spots — the badge
    // and the Transfer Queue tab — are scoped to their own Consumers below so
    // a burst of completions only repaints those, not the file browser.
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
              if (selected != null) ...[
                IconButton(
                  icon: const Icon(Icons.sync,
                      size: 16, color: ColorTokens.textSecondary),
                  tooltip: 'Sync library to device',
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 32, minHeight: 32),
                  onPressed: () =>
                      LibrarySyncDialog.show(context, selected.path),
                ),
                IconButton(
                  icon: const Icon(Icons.manage_search,
                      size: 16, color: ColorTokens.textSecondary),
                  tooltip: 'Scan device library',
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 32, minHeight: 32),
                  onPressed: () => _showScanDialog(context, ref, selected.path),
                ),
                IconButton(
                  icon: const Icon(Icons.eject_outlined,
                      size: 16, color: ColorTokens.textSecondary),
                  tooltip: 'Eject device',
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 32, minHeight: 32),
                  onPressed: () =>
                      ejectConnectedDevice(context, ref, selected.path),
                ),
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

        // ── Scrobble import banner ──────────────────────────────────────────
        if (selected != null) _ScrobbleImportBanner(devicePath: selected.path),

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
                  Consumer(
                    builder: (context, ref, _) {
                      final active = ref.watch(
                          transferQueueProvider.select((q) => q.activeCount));
                      if (active == 0) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: ColorTokens.accent,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '$active',
                            style: const TextStyle(
                                fontSize: 9, color: Colors.white),
                          ),
                        ),
                      );
                    },
                  ),
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

              // Transfer Queue — own Consumer so queue ticks repaint only this
              // tab, not the sibling file browser.
              Consumer(
                builder: (context, ref, _) {
                  final queue = ref.watch(transferQueueProvider);
                  return queue.isEmpty
                      ? const _EmptyQueue()
                      : _QueueList(queue: queue);
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Device scan ───────────────────────────────────────────────────────────────

Future<void> _showScanDialog(
    BuildContext context, WidgetRef ref, String devicePath) async {
  final settings = ref.read(deviceSettingsProvider(devicePath));
  final repo = ref.read(libraryRepositoryProvider);
  if (repo == null) return;

  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _ScanDialog(settings: settings, repo: repo),
  );
}

class _ScanDialog extends StatefulWidget {
  const _ScanDialog({required this.settings, required this.repo});
  final DeviceSettings settings;
  final LibraryRepository repo;

  @override
  State<_ScanDialog> createState() => _ScanDialogState();
}

class _ScanDialogState extends State<_ScanDialog> {
  String _status = 'Starting scan…';
  DeviceScanResult? _result;

  bool _pruning = false;
  String _pruneStatus = '';
  PruneResult? _pruneResult;

  bool _sanitizing = false;
  String _sanitizeStatus = '';
  TagSanitizeResult? _sanitizeResult;

  @override
  void initState() {
    super.initState();
    _runScan();
  }

  Future<void> _runScan() async {
    try {
      final result = await scanDevice(
        widget.settings,
        widget.repo,
        onProgress: (msg) {
          if (mounted) setState(() => _status = msg);
        },
      );
      if (mounted) setState(() => _result = result);
    } catch (e) {
      if (mounted) setState(() => _status = 'Error: $e');
    }
  }

  Future<void> _runSanitize() async {
    setState(() {
      _sanitizing = true;
      _sanitizeStatus = 'Starting…';
    });
    try {
      final result = await sanitizeDeviceTags(
        widget.settings,
        onProgress: (msg) {
          if (mounted) setState(() => _sanitizeStatus = msg);
        },
      );
      if (mounted) {
        setState(() {
          _sanitizeResult = result;
          _sanitizing = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _sanitizeStatus = 'Error: $e';
          _sanitizing = false;
        });
      }
    }
  }

  Future<void> _runPrune() async {
    setState(() {
      _pruning = true;
      _pruneStatus = 'Starting prune…';
    });
    try {
      final result = await pruneDevice(
        widget.settings,
        widget.repo,
        onProgress: (msg) {
          if (mounted) setState(() => _pruneStatus = msg);
        },
      );
      if (mounted) {
        setState(() {
          _pruneResult = result;
          _pruning = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _pruneStatus = 'Error: $e';
          _pruning = false;
        });
      }
    }
  }

  Future<void> _resolveFileDuplicate(FileDuplicate dup) async {
    for (final filename in dup.deletable) {
      final file = File(p.join(dup.folderPath, filename));
      if (file.existsSync()) await file.delete();
    }
    if (mounted) {
      setState(() => _result = _result!.withoutFileDuplicate(dup));
    }
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    return AlertDialog(
      backgroundColor: ColorTokens.surface,
      title: const Text('Scan Device Library',
          style: TextStyle(color: ColorTokens.textPrimary, fontSize: 16)),
      content: SizedBox(
        width: 440,
        child: result == null
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(_status,
                      style: const TextStyle(
                          fontSize: 12, color: ColorTokens.textSecondary)),
                ],
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _ScanStat('Albums scanned', result.albumsScanned),
                  _ScanStat('Albums with audio files', result.albumsMatched),
                  _ScanStat('Songs on device', result.songsTotal),
                  _ScanStat('Songs matched & added to manifests',
                      result.songsMatched),
                  if (result.hasDuplicates) ...[
                    const SizedBox(height: 12),
                    const Divider(color: ColorTokens.divider),
                    // ── File duplicates (same track number, different names) ──
                    if (result.fileDuplicates.isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.only(top: 4, bottom: 6),
                        child: Text(
                          '${result.fileDuplicates.length} folder${result.fileDuplicates.length == 1 ? '' : 's'} with same-track duplicates',
                          style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Colors.orange),
                        ),
                      ),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 260),
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: result.fileDuplicates.length,
                          separatorBuilder: (_, __) => const Divider(
                              color: ColorTokens.divider, height: 1),
                          itemBuilder: (_, i) => _FileDuplicateRow(
                            dup: result.fileDuplicates[i],
                            onResolve: () => _resolveFileDuplicate(
                                result.fileDuplicates[i]),
                          ),
                        ),
                      ),
                    ],
                    // ── Manifest duplicates (same song ID in multiple folders) ──
                    if (result.manifestDuplicates.isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.only(top: 8, bottom: 6),
                        child: Text(
                          '${result.manifestDuplicates.length} song${result.manifestDuplicates.length == 1 ? '' : 's'} in multiple folders',
                          style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Colors.orange),
                        ),
                      ),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 160),
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: result.manifestDuplicates.length,
                          separatorBuilder: (_, __) => const Divider(
                              color: ColorTokens.divider, height: 1),
                          itemBuilder: (_, i) {
                            final dup = result.manifestDuplicates[i];
                            return Padding(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 5),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(dup.title,
                                      style: const TextStyle(
                                          fontSize: 12,
                                          color: ColorTokens.textPrimary)),
                                  for (final path in dup.folderPaths)
                                    Text('  $path',
                                        style: const TextStyle(
                                            fontSize: 10,
                                            color: ColorTokens.textSecondary),
                                        overflow: TextOverflow.ellipsis),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ] else ...[
                    const SizedBox(height: 8),
                    const Text('No duplicates found.',
                        style: TextStyle(
                            fontSize: 12, color: ColorTokens.textSecondary)),
                  ],
                  if (result.albumsScanned == 0 &&
                      result.fileDuplicates.isEmpty) ...[
                    const SizedBox(height: 8),
                    const Text(
                      'Scan is only supported for Artist/Album folder structures.',
                      style: TextStyle(
                          fontSize: 12, color: ColorTokens.textSecondary),
                    ),
                  ],
                  // ── Prune section ─────────────────────────────────────────
                  const SizedBox(height: 8),
                  const Divider(color: ColorTokens.divider),
                  const SizedBox(height: 4),
                  if (_pruneResult != null) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        children: [
                          const Expanded(
                            child: Text('Orphan songs removed',
                                style: TextStyle(
                                    fontSize: 12,
                                    color: ColorTokens.textSecondary)),
                          ),
                          Text('${_pruneResult!.songsRemoved}',
                              style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: ColorTokens.textPrimary)),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        children: [
                          const Expanded(
                            child: Text('Space freed',
                                style: TextStyle(
                                    fontSize: 12,
                                    color: ColorTokens.textSecondary)),
                          ),
                          Text(formatBytes(_pruneResult!.bytesFreed),
                              style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: ColorTokens.textPrimary)),
                        ],
                      ),
                    ),
                    if (_pruneResult!.errors.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          '${_pruneResult!.errors.length} file(s) could not be deleted',
                          style: const TextStyle(
                              fontSize: 11, color: Colors.orange),
                        ),
                      ),
                  ] else if (_pruning) ...[
                    Row(
                      children: [
                        const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation(
                                  ColorTokens.textSecondary)),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(_pruneStatus,
                              style: const TextStyle(
                                  fontSize: 11,
                                  color: ColorTokens.textSecondary)),
                        ),
                      ],
                    ),
                  ] else ...[
                    Row(
                      children: [
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Prune orphan files',
                                  style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: ColorTokens.textPrimary)),
                              Text(
                                  'Remove songs no longer in the library',
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: ColorTokens.textSecondary)),
                            ],
                          ),
                        ),
                        TextButton(
                          onPressed: _runPrune,
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: const Text('Prune',
                              style:
                                  TextStyle(color: Colors.orange, fontSize: 12)),
                        ),
                      ],
                    ),
                  ],
                  // ── Tag sanitize section ──────────────────────────────────
                  const SizedBox(height: 8),
                  const Divider(color: ColorTokens.divider),
                  const SizedBox(height: 4),
                  if (_sanitizeResult != null) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        children: [
                          const Expanded(
                            child: Text('FLAC files scanned',
                                style: TextStyle(
                                    fontSize: 12,
                                    color: ColorTokens.textSecondary)),
                          ),
                          Text('${_sanitizeResult!.filesScanned}',
                              style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: ColorTokens.textPrimary)),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        children: [
                          const Expanded(
                            child: Text('Already clean (skipped)',
                                style: TextStyle(
                                    fontSize: 12,
                                    color: ColorTokens.textSecondary)),
                          ),
                          Text('${_sanitizeResult!.filesSkipped}',
                              style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: ColorTokens.textPrimary)),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        children: [
                          const Expanded(
                            child: Text('Files cleaned',
                                style: TextStyle(
                                    fontSize: 12,
                                    color: ColorTokens.textSecondary)),
                          ),
                          Text('${_sanitizeResult!.filesModified}',
                              style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: ColorTokens.textPrimary)),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        children: [
                          const Expanded(
                            child: Text('Album covers shrunk',
                                style: TextStyle(
                                    fontSize: 12,
                                    color: ColorTokens.textSecondary)),
                          ),
                          Text('${_sanitizeResult!.coversShrunk}',
                              style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: ColorTokens.textPrimary)),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        children: [
                          const Expanded(
                            child: Text('Space freed',
                                style: TextStyle(
                                    fontSize: 12,
                                    color: ColorTokens.textSecondary)),
                          ),
                          Text(formatBytes(_sanitizeResult!.bytesFreed),
                              style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: ColorTokens.textPrimary)),
                        ],
                      ),
                    ),
                    if (_sanitizeResult!.errors.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          '${_sanitizeResult!.errors.length} file(s) failed',
                          style: const TextStyle(
                              fontSize: 11, color: Colors.orange),
                        ),
                      ),
                  ] else if (_sanitizing) ...[
                    Row(
                      children: [
                        const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation(
                                  ColorTokens.textSecondary)),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(_sanitizeStatus,
                              style: const TextStyle(
                                  fontSize: 11,
                                  color: ColorTokens.textSecondary)),
                        ),
                      ],
                    ),
                  ] else ...[
                    Row(
                      children: [
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Clean FLAC tags & shrink covers',
                                  style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: ColorTokens.textPrimary)),
                              Text(
                                  'Strip bad tags + shrink embedded cover art to 320 px',
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: ColorTokens.textSecondary)),
                            ],
                          ),
                        ),
                        TextButton(
                          onPressed: _runSanitize,
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: const Text('Clean',
                              style: TextStyle(
                                  color: ColorTokens.accent, fontSize: 12)),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
      ),
      actions: [
        if (result != null)
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Done',
                style: TextStyle(color: ColorTokens.accent)),
          ),
      ],
    );
  }
}

class _FileDuplicateRow extends StatelessWidget {
  const _FileDuplicateRow({required this.dup, required this.onResolve});
  final FileDuplicate dup;
  final VoidCallback onResolve;

  @override
  Widget build(BuildContext context) {
    // Show correct file first, then deletable ones.
    final ordered = [
      if (dup.correctFilename != null) dup.correctFilename!,
      ...dup.filenames.where((f) => f != dup.correctFilename),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            dup.folderPath,
            style: const TextStyle(
                fontSize: 10, color: ColorTokens.textSecondary),
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          for (final name in ordered) _FileEntry(name: name, dup: dup),
          const SizedBox(height: 6),
          if (dup.canResolve)
            TextButton.icon(
              onPressed: onResolve,
              style: TextButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              icon: const Icon(Icons.delete_outline,
                  size: 13, color: Colors.redAccent),
              label: Text(
                'Delete ${dup.deletable.length} duplicate${dup.deletable.length == 1 ? '' : 's'}',
                style:
                    const TextStyle(fontSize: 11, color: Colors.redAccent),
              ),
            )
          else
            const Text(
              'Cannot determine which file to keep — delete manually.',
              style: TextStyle(fontSize: 10, color: ColorTokens.textSecondary),
            ),
        ],
      ),
    );
  }
}

class _FileEntry extends StatelessWidget {
  const _FileEntry({required this.name, required this.dup});
  final String name;
  final FileDuplicate dup;

  @override
  Widget build(BuildContext context) {
    final isCorrect = name == dup.correctFilename;
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        children: [
          Icon(
            isCorrect ? Icons.check_circle_outline : Icons.remove_circle_outline,
            size: 12,
            color: isCorrect ? Colors.green : Colors.redAccent,
          ),
          const SizedBox(width: 5),
          Expanded(
            child: Text(
              name,
              style: TextStyle(
                fontSize: 11,
                color: isCorrect
                    ? ColorTokens.textPrimary
                    : ColorTokens.textSecondary,
                decoration:
                    isCorrect ? null : TextDecoration.lineThrough,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _ScanStat extends StatelessWidget {
  const _ScanStat(this.label, this.value);
  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(label,
                style: const TextStyle(
                    fontSize: 12, color: ColorTokens.textSecondary)),
          ),
          Text('$value',
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: ColorTokens.textPrimary)),
        ],
      ),
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
                Expanded(
                  child: Text(
                    Platform.isMacOS
                        ? 'macOS blocked write access to the device.\nGrant Full Disk Access to Dapper in System Settings.'
                        : 'Write access to the device was denied.\nCheck file permissions.',
                    style: const TextStyle(
                        fontSize: 11, color: Colors.redAccent),
                  ),
                ),
                if (Platform.isMacOS) ...[
                  const SizedBox(width: 10),
                  TextButton(
                    onPressed: _openPrivacySettings,
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      minimumSize: Size.zero,
                    ),
                    child: const Text('Open Settings',
                        style: TextStyle(
                            fontSize: 11, color: Colors.redAccent)),
                  ),
                ],
              ],
            ),
          ),

        // ── Bulk actions row ──────────────────────────────────────────────────
        Builder(builder: (_) {
          final notifier = ref.read(transferQueueProvider.notifier);
          final hasActive = queue.any((t) =>
              t.status == TransferStatus.queued ||
              t.status == TransferStatus.inProgress);
          final hasFailed = queue.any((t) => t.status == TransferStatus.failed);
          final hasFinished = queue.any((t) =>
              t.status == TransferStatus.completed ||
              t.status == TransferStatus.cancelled ||
              t.status == TransferStatus.failed);
          final isPaused = notifier.isAnyDevicePaused;
          if (!hasActive && !hasFailed && !hasFinished && !isPaused) {
            return const SizedBox.shrink();
          }
          return Padding(
            padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (hasActive || isPaused)
                  TextButton.icon(
                    icon: Icon(isPaused ? Icons.play_arrow : Icons.pause,
                        size: 14),
                    label: Text(isPaused ? 'Resume all' : 'Pause all',
                        style: const TextStyle(fontSize: 11)),
                    onPressed: isPaused ? notifier.resume : notifier.pause,
                    style: TextButton.styleFrom(
                      foregroundColor: ColorTokens.textSecondary,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: Size.zero,
                    ),
                  ),
                if (hasFailed)
                  TextButton.icon(
                    icon: const Icon(Icons.refresh, size: 14),
                    label: const Text('Retry all',
                        style: TextStyle(fontSize: 11)),
                    onPressed: notifier.retryAllFailed,
                    style: TextButton.styleFrom(
                      foregroundColor: ColorTokens.textSecondary,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: Size.zero,
                    ),
                  ),
                if (hasActive)
                  TextButton.icon(
                    icon: const Icon(Icons.cancel_outlined, size: 14),
                    label: const Text('Cancel all',
                        style: TextStyle(fontSize: 11)),
                    onPressed: () async {
                      final ok = await showConfirmDialog(
                        context,
                        title: 'Cancel all transfers?',
                        message:
                            'In-progress downloads will be aborted and queued '
                            'transfers will be removed.',
                        confirmLabel: 'Cancel all',
                        destructive: true,
                      );
                      if (ok) notifier.cancelAll();
                    },
                    style: TextButton.styleFrom(
                      foregroundColor: ColorTokens.textSecondary,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: Size.zero,
                    ),
                  ),
                if (hasFinished)
                  TextButton(
                    onPressed: notifier.clearCompleted,
                    style: TextButton.styleFrom(
                      foregroundColor: ColorTokens.textSecondary,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: Size.zero,
                    ),
                    child: const Text('Clear finished',
                        style: TextStyle(fontSize: 11)),
                  ),
              ],
            ),
          );
        }),
        Expanded(
          child: Builder(builder: (_) {
            final rows = buildQueueRows(queue);
            return ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: rows.length,
              itemBuilder: (context, i) {
                final row = rows[i];
                if (row.group != null) {
                  return _AlbumGroupRow(group: row.group!);
                }
                return _TaskRow(task: row.single!);
              },
            );
          }),
        ),
      ],
    );
  }

  void _openPrivacySettings() {
    if (!Platform.isMacOS) return;
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
    // Progress is owned by transferProgressProvider (throttled to ~5Hz). The
    // TransferTask itself never has bytesReceived/totalBytes updated mid-
    // download, so reading task.progress used to leave every row stuck at 0.
    // .select(...) so this row only rebuilds when its own entry changes.
    final progress = ref.watch(
      transferProgressProvider.select((m) => m[task.id]),
    );
    final progressValue = progress != null && progress.$2 > 0
        ? progress.$1 / progress.$2
        : null; // null = indeterminate bar (works for the brief pre-bytes window)

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
                      value: progressValue,
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

}

String _statusLabel(TransferStatus s, String? error) => switch (s) {
      TransferStatus.queued => 'Waiting…',
      TransferStatus.inProgress => '',
      TransferStatus.completed => 'Done',
      TransferStatus.failed => error == 'permission_denied'
          ? 'Permission denied'
          : (error ?? 'Failed'),
      TransferStatus.cancelled => 'Cancelled',
    };

Color _statusColor(TransferStatus s) => switch (s) {
      TransferStatus.completed => Colors.green,
      TransferStatus.failed => Colors.redAccent,
      _ => ColorTokens.textSecondary,
    };

class _AlbumGroupRow extends ConsumerWidget {
  const _AlbumGroupRow({required this.group});
  final List<TransferTask> group;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final leader = group.firstWhere(
      (t) => t.zipSourceId != null,
      orElse: () => group.first,
    );
    final song = leader.song;
    final artist = song.albumArtist ?? song.artist ?? 'Unknown artist';
    final album = song.album ?? 'Unknown album';
    final total = group.length;
    final completed =
        group.where((t) => t.status == TransferStatus.completed).length;
    final status = aggregateStatus(group);

    // While the zip is downloading, the engine mirrors byte progress onto
    // every member task. Pick any in-progress member to read the leader's
    // bytes. Combine with completed-count so the bar moves smoothly through
    // the post-extract phase too.
    final inProgTask =
        group.where((t) => t.status == TransferStatus.inProgress).firstOrNull;
    final bytes = inProgTask == null
        ? null
        : ref.watch(
            transferProgressProvider.select((m) => m[inProgTask.id]),
          );
    double? progressValue;
    if (status == TransferStatus.inProgress) {
      if (bytes != null && bytes.$2 > 0) {
        final frac = (bytes.$1 / bytes.$2).clamp(0.0, 1.0);
        progressValue = ((completed + frac) / total).clamp(0.0, 1.0);
      } else {
        progressValue = total == 0 ? null : completed / total;
      }
    } else if (status == TransferStatus.completed) {
      progressValue = 1.0;
    }

    // Combine errors so the user sees the first failure reason.
    final firstError = group
        .firstWhere(
          (t) => t.status == TransferStatus.failed,
          orElse: () => leader,
        )
        .errorMessage;

    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 6),
      decoration: const BoxDecoration(
        border: Border(
            bottom: BorderSide(color: ColorTokens.divider, width: 0.5)),
      ),
      child: Row(
        children: [
          _StatusIcon(status: status),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('$artist — $album',
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: ColorTokens.textPrimary),
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 3),
                if (status == TransferStatus.inProgress ||
                    status == TransferStatus.queued) ...[
                  LinearProgressIndicator(
                    value: progressValue,
                    backgroundColor: ColorTokens.surfaceVariant,
                    valueColor:
                        const AlwaysStoppedAnimation(ColorTokens.accent),
                    minHeight: 3,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$completed / $total songs',
                    style: const TextStyle(
                        fontSize: 10, color: ColorTokens.textSecondary),
                  ),
                ] else if (status == TransferStatus.completed)
                  Text('Done — $total songs',
                      style: TextStyle(
                          fontSize: 10, color: _statusColor(status)))
                else
                  Text(
                    '${_statusLabel(status, firstError)} ($completed / $total)',
                    style: TextStyle(
                        fontSize: 10, color: _statusColor(status)),
                  ),
              ],
            ),
          ),
          if (status == TransferStatus.queued ||
              status == TransferStatus.inProgress)
            IconButton(
              icon: const Icon(Icons.close,
                  size: 14, color: ColorTokens.textSecondary),
              tooltip: 'Cancel album',
              onPressed: () =>
                  ref.read(transferQueueProvider.notifier).cancel(leader.id),
              padding: EdgeInsets.zero,
              constraints:
                  const BoxConstraints(minWidth: 24, minHeight: 24),
            )
          else if (status == TransferStatus.failed)
            IconButton(
              icon: const Icon(Icons.refresh,
                  size: 14, color: ColorTokens.textSecondary),
              tooltip: 'Retry failed songs',
              onPressed: () {
                final notifier = ref.read(transferQueueProvider.notifier);
                for (final t in group) {
                  if (t.status == TransferStatus.failed) notifier.retry(t.id);
                }
              },
              padding: EdgeInsets.zero,
              constraints:
                  const BoxConstraints(minWidth: 24, minHeight: 24),
            ),
        ],
      ),
    );
  }
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

// ── Scrobble import banner ────────────────────────────────────────────────────
//
// Shown for ~10 s after the device-plug listener finishes an import pass.
// Surfaces match / submit / unmatched counts so the user has visible
// confirmation that offline plays made it back to Navidrome. Dismissible via
// the close button; auto-clears when the user navigates away or the next
// device-plug overwrites the result.
class _ScrobbleImportBanner extends ConsumerWidget {
  const _ScrobbleImportBanner({required this.devicePath});

  final String devicePath;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final result = ref.watch(scrobbleImportResultProvider);
    if (result == null || result.devicePath != devicePath) {
      return const SizedBox.shrink();
    }
    if (!result.hasWork) return const SizedBox.shrink();

    final accentColor = result.errors > 0
        ? Colors.orange
        : (result.matched == 0
            ? ColorTokens.textSecondary
            : ColorTokens.accent);

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: accentColor.withValues(alpha: 0.08),
          border: Border.all(color: accentColor.withValues(alpha: 0.35)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(Icons.cloud_upload_outlined, size: 14, color: accentColor),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _summarise(result),
                style: TextStyle(fontSize: 11, color: accentColor),
              ),
            ),
            GestureDetector(
              onTap: () => ref
                  .read(scrobbleImportResultProvider.notifier)
                  .state = null,
              child: Icon(Icons.close, size: 13, color: accentColor),
            ),
          ],
        ),
      ),
    );
  }

  String _summarise(ScrobbleImportResult r) {
    if (r.matched == 0) {
      return 'Found ${r.parsed} scrobble log entr'
          '${r.parsed == 1 ? 'y' : 'ies'} but none matched library songs.';
    }
    final base = 'Imported ${r.submitted} of ${r.parsed} offline play'
        '${r.parsed == 1 ? '' : 's'} from device.';
    if (r.unmatched > 0 && r.errors > 0) {
      return '$base ${r.unmatched} unmatched, ${r.errors} server error'
          '${r.errors == 1 ? '' : 's'}.';
    }
    if (r.unmatched > 0) {
      return '$base ${r.unmatched} unmatched.';
    }
    if (r.errors > 0) {
      return '$base ${r.errors} server error'
          '${r.errors == 1 ? '' : 's'}.';
    }
    return base;
  }
}
