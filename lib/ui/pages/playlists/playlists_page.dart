import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../../application/device/device_settings_notifier.dart';
import '../../../application/library/library_notifier.dart';
import '../../../application/library/playlist_actions_notifier.dart';
import '../../../application/library/sidebar_state.dart';
import '../../../application/library/song_selection_notifier.dart';
import '../../../application/playback/playback_notifier.dart';
import '../../../application/providers/providers.dart';
import '../../../application/transfer/playlist_sync_writer.dart';
import '../../../application/transfer/transfer_path_resolver.dart';
import '../../../core/theme/color_tokens.dart';
import '../../../domain/models/connected_device.dart';
import '../../../domain/models/device_settings.dart';
import '../../../domain/models/playlist.dart';
import '../../../domain/models/song.dart';
import '../../../domain/models/transfer_task.dart';
import '../../widgets/add_to_playlist_dialog.dart';
import '../../widgets/cover_art_image.dart';
import '../../widgets/error_retry.dart';
import '../../widgets/select_all_shortcut.dart';
import '../../widgets/selection_action_bar.dart';
import '../../widgets/song_metadata_dialog.dart';
import '../../widgets/song_row.dart';
import '../../widgets/sync_dot.dart';

class PlaylistsPage extends ConsumerWidget {
  const PlaylistsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedId = ref.watch(selectedPlaylistIdProvider);
    if (selectedId != null) {
      return _PlaylistDetail(playlistId: selectedId);
    }
    final playlists = ref.watch(playlistsProvider);
    return playlists.when(
      data: (list) => _PlaylistList(playlists: list),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => ErrorRetry(
        error: e,
        onRetry: () => ref.invalidate(playlistsProvider),
      ),
    );
  }
}

// ── Playlist list ─────────────────────────────────────────────────────────────

class _PlaylistList extends ConsumerWidget {
  const _PlaylistList({required this.playlists});

  final List<Playlist> playlists;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: AppConstants.scrollBottomInset),
      itemCount: playlists.length,
      itemExtent: 56,
      itemBuilder: (context, i) {
        final p = playlists[i];
        return GestureDetector(
          onTap: () =>
              ref.read(selectedPlaylistIdProvider.notifier).state = p.id,
          onSecondaryTapUp: (d) =>
              _showListContextMenu(context, ref, p, d.globalPosition),
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            child: Row(
              children: [
                SizedBox(
                  width: 40,
                  height: 40,
                  child: CoverArtImage(
                      coverArtId: p.coverArtId, size: 80, borderRadius: 4),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(p.name,
                          style: const TextStyle(
                              fontSize: 13, color: ColorTokens.textPrimary)),
                      Text('${p.songCount} songs',
                          style: const TextStyle(
                              fontSize: 11,
                              color: ColorTokens.textSecondary)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showListContextMenu(
    BuildContext context,
    WidgetRef ref,
    Playlist playlist,
    Offset pos,
  ) async {
    final result = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(pos.dx, pos.dy, pos.dx, pos.dy),
      color: ColorTokens.surface,
      items: [
        const PopupMenuItem(
          value: 'rename',
          child: _MenuItem(icon: Icons.edit, label: 'Rename'),
        ),
        const PopupMenuItem(
          value: 'delete',
          child: _MenuItem(icon: Icons.delete_outline, label: 'Delete'),
        ),
      ],
    );
    if (!context.mounted) return;
    if (result == 'rename') _rename(context, ref, playlist);
    if (result == 'delete') _delete(context, ref, playlist);
  }

  void _rename(
      BuildContext context, WidgetRef ref, Playlist playlist) async {
    final ctrl = TextEditingController(text: playlist.name);
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _RenameDialog(controller: ctrl),
    );
    if (name != null && name.trim().isNotEmpty) {
      unawaited(ref
          .read(playlistActionsProvider.notifier)
          .rename(playlist.id, name.trim()));
    }
  }

  void _delete(
      BuildContext context, WidgetRef ref, Playlist playlist) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: ColorTokens.surface,
        title: const Text('Delete Playlist',
            style: TextStyle(color: ColorTokens.textPrimary)),
        content: Text('Delete "${playlist.name}"? This cannot be undone.',
            style: const TextStyle(color: ColorTokens.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete',
                style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      unawaited(ref.read(playlistActionsProvider.notifier).delete(playlist.id));
    }
  }
}

// ── Playlist detail ───────────────────────────────────────────────────────────

class _PlaylistDetail extends ConsumerWidget {
  const _PlaylistDetail({required this.playlistId});
  final String playlistId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(playlistProvider(playlistId));
    return async.when(
      data: (p) {
        if (p == null) return const SizedBox.shrink();
        return _PlaylistContent(playlist: p);
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => ErrorRetry(
        error: e,
        onRetry: () => ref.invalidate(playlistProvider(playlistId)),
      ),
    );
  }
}

class _PlaylistContent extends ConsumerWidget {
  const _PlaylistContent({required this.playlist});
  final Playlist playlist;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final device = ref.watch(selectedDeviceProvider);
    final devices = ref.watch(connectedDevicesProvider).valueOrNull ?? [];
    final settings =
        device != null ? ref.watch(deviceSettingsProvider(device.path)) : null;
    ref.watch(manifestRevisionProvider);
    final isOnDevice =
        settings != null && playlistExistsOnDevice(playlist, settings);
    final scopeKey = 'playlist:${playlist.id}';

    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(songSelectionProvider.notifier).setScope(scopeKey);
    });

    return SelectAllShortcut(
      scopeKey: scopeKey,
      allSongs: playlist.songs,
      child: Stack(
        children: [
          CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: _PlaylistHeader(
                  playlist: playlist,
                  device: device,
                  devices: devices,
                  settings: settings,
                  isOnDevice: isOnDevice,
                ),
              ),
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, i) => _PlaylistSongRow(
                    song: playlist.songs[i],
                    allSongs: playlist.songs,
                    index: i,
                    playlistId: playlist.id,
                    settings: settings,
                    scopeKey: scopeKey,
                  ),
                  childCount: playlist.songs.length,
                ),
              ),
              const SliverToBoxAdapter(
                  child: SizedBox(height: AppConstants.scrollBottomInset)),
            ],
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SelectionActionBar(
              scopeKey: scopeKey,
              allSongs: playlist.songs,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Header ────────────────────────────────────────────────────────────────────

class _PlaylistHeader extends ConsumerWidget {
  const _PlaylistHeader({
    required this.playlist,
    required this.device,
    required this.devices,
    required this.settings,
    required this.isOnDevice,
  });

  final Playlist playlist;
  final ConnectedDevice? device;
  final List<ConnectedDevice> devices;
  final DeviceSettings? settings;
  final bool isOnDevice;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios, size: 16),
            onPressed: () =>
                ref.read(selectedPlaylistIdProvider.notifier).state = null,
            color: ColorTokens.textSecondary,
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 120,
            height: 120,
            child: CoverArtImage(
                coverArtId: playlist.coverArtId, size: 240, borderRadius: 8),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  playlist.name,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: ColorTokens.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${playlist.songCount} songs · ${_fmtDuration(playlist.duration)}',
                  style: const TextStyle(
                      fontSize: 12, color: ColorTokens.textSecondary),
                ),
                if (isOnDevice) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      SyncDot(color: Colors.green.withValues(alpha: 0.85)),
                      const SizedBox(width: 4),
                      const Text('Playlist on device',
                          style:
                              TextStyle(fontSize: 11, color: Colors.green)),
                    ],
                  ),
                ],
                const SizedBox(height: 12),
                Row(
                  children: [
                    // Play button
                    if (playlist.songs.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: FilledButton.icon(
                          onPressed: () => ref
                              .read(playbackProvider.notifier)
                              .playSong(playlist.songs.first,
                                  queue: playlist.songs, index: 0),
                          icon:
                              const Icon(Icons.play_arrow, size: 16),
                          label: const Text('Play'),
                          style: FilledButton.styleFrom(
                            backgroundColor: ColorTokens.surfaceVariant,
                            foregroundColor: ColorTokens.textPrimary,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 8),
                            textStyle: const TextStyle(fontSize: 12),
                          ),
                        ),
                      ),
                    // Sync button
                    FilledButton.icon(
                      onPressed: playlist.songs.isEmpty || devices.isEmpty
                          ? null
                          : () => _syncPlaylist(context, ref),
                      icon: Icon(
                          isOnDevice ? Icons.sync : Icons.download,
                          size: 16),
                      label: Text(
                        devices.isEmpty
                            ? 'No device connected'
                            : isOnDevice
                                ? 'Re-sync'
                                : 'Sync Playlist',
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: ColorTokens.accent,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 8),
                        textStyle: const TextStyle(fontSize: 12),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.playlist_add, size: 20),
                      color: ColorTokens.textSecondary,
                      tooltip: 'Add songs to playlist',
                      onPressed: () => showAddToPlaylistDialog(
                          context,
                          ref,
                          playlist.songs.map((s) => s.id).toList()),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _syncPlaylist(BuildContext context, WidgetRef ref) async {
    final devicePath = await _pickDevicePath(context, devices);
    if (devicePath == null) return;
    final repo = ref.read(libraryRepositoryProvider);
    if (repo == null) return;
    ref.read(transferQueueProvider.notifier).enqueuePlaylist(
          playlist,
          devicePath,
        );
  }

  static String _fmtDuration(int s) {
    final h = s ~/ 3600;
    final m = (s % 3600) ~/ 60;
    return h > 0 ? '${h}h ${m}m' : '${m}m';
  }
}

// ── Song row ──────────────────────────────────────────────────────────────────

class _PlaylistSongRow extends ConsumerWidget {
  const _PlaylistSongRow({
    required this.song,
    required this.allSongs,
    required this.index,
    required this.playlistId,
    required this.settings,
    required this.scopeKey,
  });

  final Song song;
  final List<Song> allSongs;
  final int index;
  final String playlistId;
  final DeviceSettings? settings;
  final String scopeKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // .select keeps this row from rebuilding on every status change
    // anywhere in the queue — only this song's transitions matter.
    final (isActive, isQueued) = ref.watch(
      transferQueueProvider.select((q) {
        var active = false;
        var queued = false;
        for (final t in q) {
          if (t.song.id != song.id) continue;
          if (t.status == TransferStatus.inProgress) {
            active = true;
            break;
          }
          if (t.status == TransferStatus.queued) queued = true;
        }
        return (active, !active && queued);
      }),
    );
    ref.watch(manifestRevisionProvider);
    final isOnDevice = settings != null && songExistsOnDevice(song, settings!);
    final isSelected = ref.watch(songSelectionProvider.select((s) =>
        s.matches(scopeKey) && s.isSelected(song.id)));

    Widget? trailing;
    if (isActive || isQueued) {
      trailing = Padding(
        padding: const EdgeInsets.only(right: 6),
        child: SyncDot(
          color: Colors.blue.withValues(alpha: 0.85),
          pulse: isActive,
        ),
      );
    } else if (isOnDevice) {
      trailing = Padding(
        padding: const EdgeInsets.only(right: 6),
        child: SyncDot(color: Colors.green.withValues(alpha: 0.85)),
      );
    }

    return SongRow(
      song: song,
      index: index,
      showArtist: true,
      selected: isSelected,
      selectionScopeKey: scopeKey,
      selectionAllSongs: allSongs,
      trailing: trailing,
      onTap: () => ref
          .read(playbackProvider.notifier)
          .playSong(song, queue: allSongs, index: index),
      onTapWithModifiers: (mods) {
        final notifier = ref.read(songSelectionProvider.notifier);
        if (mods.hasRange) {
          notifier.selectRange(scopeKey, allSongs, index);
          return;
        }
        if (mods.hasToggle) {
          notifier.toggle(scopeKey, song.id, index);
          return;
        }
        final selection = ref.read(songSelectionProvider);
        if (selection.matches(scopeKey) && !selection.isEmpty) {
          notifier.selectOnly(scopeKey, song.id, index);
          return;
        }
        ref
            .read(playbackProvider.notifier)
            .playSong(song, queue: allSongs, index: index);
      },
      onAddToPlaylist: () =>
          showAddToPlaylistDialog(context, ref, [song.id]),
      onRemove: () => ref
          .read(playlistActionsProvider.notifier)
          .removeSong(playlistId, index),
      onGetInfo: () => showSongMetadataDialog(context, song),
    );
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

class _MenuItem extends StatelessWidget {
  const _MenuItem({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: ColorTokens.textPrimary),
        const SizedBox(width: 8),
        Text(label,
            style:
                const TextStyle(fontSize: 13, color: ColorTokens.textPrimary)),
      ],
    );
  }
}

Future<String?> _pickDevicePath(
  BuildContext context,
  List<ConnectedDevice> devices,
) async {
  if (devices.isEmpty) return null;
  if (devices.length == 1) return devices.first.path;
  final result = await showDialog<ConnectedDevice>(
    context: context,
    builder: (_) => SimpleDialog(
      backgroundColor: ColorTokens.surface,
      title: const Text('Choose device',
          style: TextStyle(color: ColorTokens.textPrimary, fontSize: 16)),
      children: devices
          .map((d) => SimpleDialogOption(
                onPressed: () => Navigator.pop(context, d),
                child: Text(d.label,
                    style: const TextStyle(
                        color: ColorTokens.textPrimary, fontSize: 13)),
              ))
          .toList(),
    ),
  );
  return result?.path;
}

class _RenameDialog extends StatelessWidget {
  const _RenameDialog({required this.controller});
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: ColorTokens.surface,
      title: const Text('Rename Playlist',
          style: TextStyle(color: ColorTokens.textPrimary)),
      content: TextField(
        controller: controller,
        autofocus: true,
        style: const TextStyle(color: ColorTokens.textPrimary),
        decoration: InputDecoration(
          filled: true,
          fillColor: ColorTokens.surfaceVariant,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide.none,
          ),
        ),
        onSubmitted: (v) => Navigator.pop(context, v),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, controller.text),
          style: FilledButton.styleFrom(backgroundColor: ColorTokens.accent),
          child: const Text('Rename'),
        ),
      ],
    );
  }
}
