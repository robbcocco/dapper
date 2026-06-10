import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/library/song_selection_notifier.dart';
import '../../application/providers/providers.dart';
import '../../core/theme/color_tokens.dart';
import '../../domain/models/connected_device.dart';
import '../../domain/models/song.dart';
import 'add_to_playlist_dialog.dart';

/// Bottom action bar shown when the user has any songs selected in [scopeKey].
/// Pass [allSongs] in display order — selected ids are filtered against it to
/// build the action's working set.
class SelectionActionBar extends ConsumerWidget {
  const SelectionActionBar({
    super.key,
    required this.scopeKey,
    required this.allSongs,
  });

  final String scopeKey;
  final List<Song> allSongs;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selection = ref.watch(songSelectionProvider);
    if (!selection.matches(scopeKey) || selection.isEmpty) {
      return const SizedBox.shrink();
    }
    final selectedSongs = allSongs
        .where((s) => selection.selectedIds.contains(s.id))
        .toList(growable: false);
    final device = ref.watch(selectedDeviceProvider);
    final devices = ref.watch(connectedDevicesProvider).valueOrNull ?? const [];

    void enqueueTo(ConnectedDevice target) {
      if (selectedSongs.isEmpty) return;
      ref
          .read(transferQueueProvider.notifier)
          .enqueue(selectedSongs, target.path);
      ref.read(songSelectionProvider.notifier).clear();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: ColorTokens.surface.withValues(alpha: 0.96),
        border: const Border(top: BorderSide(color: ColorTokens.glassBorder)),
      ),
      child: Row(
        children: [
          Text(
            '${selection.count} selected',
            style: const TextStyle(
                fontSize: 12, color: ColorTokens.textPrimary),
          ),
          const SizedBox(width: 12),
          // Multi-device picker: when more than one device is mounted the
          // transfer button becomes a popup menu so the user can choose. With
          // one device it acts as a normal button using that device. Zero
          // devices disables it.
          if (devices.length > 1)
            PopupMenuButton<String>(
              tooltip: 'Transfer to…',
              color: ColorTokens.surface,
              onSelected: (path) {
                final picked = devices.firstWhere((d) => d.path == path);
                enqueueTo(picked);
              },
              itemBuilder: (_) => [
                for (final d in devices)
                  PopupMenuItem<String>(
                    value: d.path,
                    child: Text(d.label,
                        style: const TextStyle(
                            fontSize: 12,
                            color: ColorTokens.textPrimary)),
                  ),
              ],
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.download,
                        size: 14, color: ColorTokens.textPrimary),
                    SizedBox(width: 6),
                    Text('Transfer',
                        style: TextStyle(
                            fontSize: 12, color: ColorTokens.textPrimary)),
                    Icon(Icons.arrow_drop_down,
                        size: 16, color: ColorTokens.textSecondary),
                  ],
                ),
              ),
            )
          else
            TextButton.icon(
              onPressed: device == null ? null : () => enqueueTo(device),
              icon: const Icon(Icons.download, size: 14),
              label: const Text('Transfer'),
              style: TextButton.styleFrom(
                foregroundColor: ColorTokens.textPrimary,
                textStyle: const TextStyle(fontSize: 12),
              ),
            ),
          TextButton.icon(
            onPressed: () => showAddToPlaylistDialog(
                context, ref, selectedSongs.map((s) => s.id).toList()),
            icon: const Icon(Icons.playlist_add, size: 14),
            label: const Text('Add to playlist'),
            style: TextButton.styleFrom(
              foregroundColor: ColorTokens.textPrimary,
              textStyle: const TextStyle(fontSize: 12),
            ),
          ),
          const Spacer(),
          TextButton(
            onPressed: () => ref.read(songSelectionProvider.notifier).clear(),
            style: TextButton.styleFrom(
              foregroundColor: ColorTokens.textSecondary,
              textStyle: const TextStyle(fontSize: 12),
            ),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }
}
