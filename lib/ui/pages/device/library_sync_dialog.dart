import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../application/device/device_settings_notifier.dart';
import '../../../application/providers/providers.dart';
import '../../../application/transfer/library_sync.dart';
import '../../../application/transfer/transfer_path_resolver.dart';
import '../../../core/theme/color_tokens.dart';
import '../../../domain/models/device_settings.dart';

/// Sync-library dialog. Scans the Subsonic library, diffs against the device
/// manifests, and offers to enqueue every missing album. Honours the device's
/// [DeviceSettings.useZipDownload] toggle when enqueuing.
class LibrarySyncDialog extends ConsumerStatefulWidget {
  const LibrarySyncDialog({super.key, required this.devicePath});

  final String devicePath;

  static Future<void> show(BuildContext context, String devicePath) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => LibrarySyncDialog(devicePath: devicePath),
    );
  }

  @override
  ConsumerState<LibrarySyncDialog> createState() => _LibrarySyncDialogState();
}

class _LibrarySyncDialogState extends ConsumerState<LibrarySyncDialog> {
  bool _scanning = true;
  int _scanned = 0;
  String _status = 'Scanning library…';
  LibrarySyncPlan? _plan;
  String? _error;

  bool _enqueueing = false;
  int _enqueued = 0;
  bool _cancelRequested = false;

  @override
  void initState() {
    super.initState();
    _scan();
  }

  Future<void> _scan() async {
    final repo = ref.read(libraryRepositoryProvider);
    if (repo == null) {
      setState(() {
        _scanning = false;
        _error = 'No active server';
      });
      return;
    }
    final settings = ref.read(deviceSettingsProvider(widget.devicePath));
    try {
      final plan = await buildLibrarySyncPlan(
        repo,
        settings,
        onProgress: (scanned, _) {
          if (mounted) {
            setState(() {
              _scanned = scanned;
              _status = 'Scanning library… $scanned albums';
            });
          }
        },
      );
      if (mounted) {
        setState(() {
          _plan = plan;
          _scanning = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _scanning = false;
        });
      }
    }
  }

  Future<void> _enqueueAll() async {
    final plan = _plan;
    if (plan == null) return;
    final repo = ref.read(libraryRepositoryProvider);
    if (repo == null) return;
    final settings = ref.read(deviceSettingsProvider(widget.devicePath));

    setState(() {
      _enqueueing = true;
      _enqueued = 0;
      _status = 'Queueing transfers…';
    });

    final queue = ref.read(transferQueueProvider.notifier);
    final useZip = settings.useZipDownload && !settings.isTranscoding;

    for (final entry in plan.unsynced) {
      if (!mounted) return;
      if (_cancelRequested) break;
      try {
        final full = await repo.getAlbum(entry.album.id);
        if (full.songs.isEmpty) continue;
        if (useZip) {
          queue.enqueueZipGroup(full.id, full.songs, widget.devicePath);
        } else {
          final folder = buildAlbumFolder(
              full.artist, full.name, full.year, settings);
          final expectedCounts =
              folder != null ? {folder: full.songCount} : null;
          queue.enqueue(
            full.songs,
            widget.devicePath,
            expectedAlbumSongCounts: expectedCounts,
          );
        }
        if (mounted) {
          setState(() {
            _enqueued++;
            _status = 'Queueing transfers… '
                '$_enqueued/${plan.unsynced.length} albums';
          });
        }
      } catch (_) {
        // Skip albums that fail to load — partial progress is better than
        // aborting the whole sync. User can re-run.
      }
    }

    if (mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(deviceSettingsProvider(widget.devicePath));
    final isFolderUnsupported =
        settings.folderStructure == FolderStructure.flat ||
            settings.folderStructure == FolderStructure.artistOnly ||
            (settings.folderStructure == FolderStructure.custom &&
                !settings.customFolderTemplate.contains('{album}'));
    final plan = _plan;
    final useZip = settings.useZipDownload && !settings.isTranscoding;

    return AlertDialog(
      backgroundColor: ColorTokens.surface,
      title: const Text('Sync library to device',
          style: TextStyle(color: ColorTokens.textPrimary, fontSize: 16)),
      content: SizedBox(
        width: 420,
        child: _buildBody(plan, isFolderUnsupported, useZip),
      ),
      actions: _buildActions(plan, isFolderUnsupported),
    );
  }

  Widget _buildBody(
      LibrarySyncPlan? plan, bool isFolderUnsupported, bool useZip) {
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(_error!,
            style:
                const TextStyle(fontSize: 12, color: Colors.redAccent)),
      );
    }
    if (isFolderUnsupported && !_scanning) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Text(
          'Sync requires an Artist/Album folder structure. Per-album sync '
          'state cannot be determined for flat or artist-only layouts.',
          style: TextStyle(fontSize: 12, color: ColorTokens.textSecondary),
        ),
      );
    }
    if (_scanning) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 12),
          Text(_status,
              style: const TextStyle(
                  fontSize: 12, color: ColorTokens.textSecondary)),
          if (_scanned > 0)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('$_scanned',
                  style: const TextStyle(
                      fontSize: 11, color: ColorTokens.textSecondary)),
            ),
        ],
      );
    }
    if (plan == null) return const SizedBox.shrink();
    if (_enqueueing) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 12),
          Text(_status,
              style: const TextStyle(
                  fontSize: 12, color: ColorTokens.textSecondary)),
        ],
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Stat(label: 'Albums scanned', value: '${plan.albumsScanned}'),
        _Stat(
          label: 'Albums missing or partial',
          value: '${plan.missingAlbums}',
        ),
        _Stat(
          label: 'Songs to transfer',
          value: '~${plan.missingSongs}',
        ),
        const SizedBox(height: 10),
        Text(
          plan.missingAlbums == 0
              ? 'Everything is already synced.'
              : useZip
                  ? 'Transfers will use bulk-zip downloads (one request per album).'
                  : 'Transfers will use per-song downloads. Enable bulk zip in '
                      'device settings for fewer round-trips.',
          style: const TextStyle(
              fontSize: 11, color: ColorTokens.textSecondary),
        ),
      ],
    );
  }

  List<Widget> _buildActions(LibrarySyncPlan? plan, bool isFolderUnsupported) {
    if (_scanning || _enqueueing) {
      return [
        TextButton(
          onPressed: () {
            // During enqueue: flag the loop to stop after the current album,
            // then close. During scan: close directly (paginated fetch will
            // wrap up on its own and setState will be a no-op).
            if (_enqueueing) setState(() => _cancelRequested = true);
            Navigator.of(context).pop();
          },
          child: const Text('Cancel',
              style: TextStyle(color: ColorTokens.textSecondary)),
        ),
      ];
    }
    if (_error != null || isFolderUnsupported || plan == null) {
      return [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close',
              style: TextStyle(color: ColorTokens.accent)),
        ),
      ];
    }
    return [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel',
            style: TextStyle(color: ColorTokens.textSecondary)),
      ),
      FilledButton(
        onPressed: plan.missingAlbums == 0 ? null : _enqueueAll,
        style: FilledButton.styleFrom(backgroundColor: ColorTokens.accent),
        child: Text(plan.missingAlbums == 0
            ? 'Up to date'
            : 'Sync ${plan.missingAlbums} albums'),
      ),
    ];
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});
  final String label;
  final String value;

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
          Text(value,
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: ColorTokens.textPrimary)),
        ],
      ),
    );
  }
}
