import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../../application/device/device_settings_notifier.dart';
import '../../../application/library/library_notifier.dart';
import '../../../application/library/song_selection_notifier.dart';
import '../../../application/library/starred_notifier.dart';
import '../../../application/playback/playback_notifier.dart';
import '../../../application/providers/providers.dart';
import '../../../application/transfer/transfer_path_resolver.dart';
import '../../../core/theme/color_tokens.dart';
import '../../../domain/models/song.dart';
import '../../../domain/models/transfer_task.dart';
import '../../widgets/add_to_playlist_dialog.dart';
import '../../widgets/error_retry.dart';
import '../../widgets/select_all_shortcut.dart';
import '../../widgets/selection_action_bar.dart';
import '../../widgets/song_metadata_dialog.dart';
import '../../widgets/sync_dot.dart';

class SongsPage extends ConsumerStatefulWidget {
  const SongsPage({super.key});

  @override
  ConsumerState<SongsPage> createState() => _SongsPageState();
}

class _SongsPageState extends ConsumerState<SongsPage> {
  final _scrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _onScroll() {
    final pos = _scrollCtrl.position;
    if (pos.pixels >= pos.maxScrollExtent - 400) {
      ref.read(allSongsProvider.notifier).loadMore();
    }
  }

  static const _scopeKey = 'songs:all';

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(allSongsProvider);

    if (s.isLoading && s.songs.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (s.error != null && s.songs.isEmpty) {
      return ErrorRetry(
        error: s.error!,
        onRetry: () => ref.read(allSongsProvider.notifier).refresh(),
      );
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(songSelectionProvider.notifier).setScope(_scopeKey);
    });

    return SelectAllShortcut(
      scopeKey: _scopeKey,
      allSongs: s.songs,
      child: Stack(
      children: [
        Column(
          children: [
            // Column headers
            Container(
              height: 34,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: const BoxDecoration(
                border:
                    Border(bottom: BorderSide(color: ColorTokens.divider)),
              ),
              child: const Row(
                children: [
                  SizedBox(width: 40), // track #
                  Expanded(flex: 3, child: _ColHeader('Title')),
                  Expanded(flex: 2, child: _ColHeader('Artist')),
                  Expanded(flex: 2, child: _ColHeader('Album')),
                  SizedBox(
                      width: 55,
                      child: _ColHeader('Time', align: TextAlign.right)),
                  SizedBox(width: 20), // sync indicator
                  SizedBox(width: 36), // star + padding
                ],
              ),
            ),
            // Song list
            Expanded(
              child: ListView.builder(
                controller: _scrollCtrl,
                padding: const EdgeInsets.only(
                    bottom: AppConstants.scrollBottomInset),
                itemCount: s.songs.length + (s.isLoading ? 1 : 0),
                itemExtent: 36,
                itemBuilder: (context, i) {
                  if (i >= s.songs.length) {
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.all(8),
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    );
                  }
                  final song = s.songs[i];
                  return _SongTableRow(
                    song: song,
                    index: i,
                    allSongs: s.songs,
                    scopeKey: _scopeKey,
                  );
                },
              ),
            ),
          ],
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: SelectionActionBar(
            scopeKey: _scopeKey,
            allSongs: s.songs,
          ),
        ),
      ],
    ),
    );
  }
}

class _ColHeader extends StatelessWidget {
  const _ColHeader(this.label, {this.align = TextAlign.left});
  final String label;
  final TextAlign align;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      textAlign: align,
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w500,
        color: ColorTokens.textSecondary,
        letterSpacing: 0.3,
      ),
    );
  }
}

// ── Table song row ────────────────────────────────────────────────────────────

class _SongTableRow extends ConsumerWidget {
  const _SongTableRow({
    required this.song,
    required this.index,
    required this.allSongs,
    required this.scopeKey,
  });

  final Song song;
  final int index;
  final List<Song> allSongs;
  final String scopeKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isPlaying = ref
        .watch(playbackProvider.select((s) => s.currentSong?.id == song.id));
    final isStarred =
        ref.watch(starredProvider.select((s) => s.contains(song.id)));
    final (isActive, isQueued) = ref.watch(
      transferQueueProvider.select((q) {
        // Single pass with early exit: inProgress wins over queued, and once
        // we've seen either we can stop scanning matching task entries.
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
    final device = ref.watch(selectedDeviceProvider);
    final settings =
        device != null ? ref.watch(deviceSettingsProvider(device.path)) : null;
    // Force rebuild when any manifest is written so the on-device dot
    // updates as soon as a transfer completes, not at next route change.
    ref.watch(manifestRevisionProvider);
    final isOnDevice = settings != null && songExistsOnDevice(song, settings);
    final isSelected = ref.watch(songSelectionProvider.select((s) =>
        s.matches(scopeKey) && s.isSelected(song.id)));

    return GestureDetector(
      onTap: () {
        final keyboard = HardwareKeyboard.instance;
        final notifier = ref.read(songSelectionProvider.notifier);
        if (keyboard.isShiftPressed) {
          notifier.selectRange(scopeKey, allSongs, index);
          return;
        }
        if (keyboard.isMetaPressed || keyboard.isControlPressed) {
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
      onSecondaryTapUp: (d) => _showMenu(context, ref, d.globalPosition),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: isSelected
              ? ColorTokens.accent.withValues(alpha: 0.18)
              : isPlaying
                  ? ColorTokens.accent.withValues(alpha: 0.08)
                  : Colors.transparent,
          border: const Border(
              bottom: BorderSide(color: Color(0xFF2A2A2A))),
        ),
        child: Row(
          children: [
            // Track number / playing indicator
            SizedBox(
              width: 40,
              child: isPlaying
                  ? const Icon(Icons.equalizer,
                      size: 13, color: ColorTokens.accent)
                  : Text(
                      '${song.track ?? index + 1}',
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                          fontSize: 12,
                          color: ColorTokens.textSecondary),
                    ),
            ),
            // Title
            Expanded(
              flex: 3,
              child: Text(
                song.title,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  color: isPlaying
                      ? ColorTokens.accent
                      : ColorTokens.textPrimary,
                ),
              ),
            ),
            // Artist
            Expanded(
              flex: 2,
              child: Text(
                song.artist ?? '',
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 12, color: ColorTokens.textSecondary),
              ),
            ),
            // Album
            Expanded(
              flex: 2,
              child: Text(
                song.album ?? '',
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 12, color: ColorTokens.textSecondary),
              ),
            ),
            // Duration
            SizedBox(
              width: 55,
              child: song.duration != null
                  ? Text(
                      _fmt(song.duration!),
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                          fontSize: 12,
                          color: ColorTokens.textSecondary),
                    )
                  : const SizedBox.shrink(),
            ),
            // Sync indicator
            SizedBox(
              width: 20,
              child: isActive || isQueued
                  ? Center(
                      child: SyncDot(
                        color: Colors.blue.withValues(alpha: 0.85),
                        pulse: isActive,
                      ),
                    )
                  : isOnDevice
                      ? Center(
                          child: SyncDot(
                            color: Colors.green.withValues(alpha: 0.85),
                          ),
                        )
                      : const SizedBox.shrink(),
            ),
            // Star
            GestureDetector(
              onTap: () =>
                  ref.read(starredProvider.notifier).toggle(song.id),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Icon(
                  isStarred ? Icons.star : Icons.star_border,
                  size: 13,
                  color: isStarred
                      ? Colors.amber
                      : ColorTokens.textSecondary
                          .withValues(alpha: 0.35),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showMenu(BuildContext ctx, WidgetRef ref, Offset pos) async {
    final devices = ref.read(connectedDevicesProvider).value ?? [];
    // Bulk-aware menu: when this row sits inside an active selection that
    // includes more than one song, the transfer / playlist actions operate
    // on the whole selection.
    final selection = ref.read(songSelectionProvider);
    final isBulk = selection.matches(scopeKey) &&
        selection.isSelected(song.id) &&
        selection.count > 1;
    final bulkSongs = isBulk
        ? allSongs.where((s) => selection.selectedIds.contains(s.id)).toList()
        : const <Song>[];
    final bulkLabel = '${bulkSongs.length} selected songs';

    final result = await showMenu<String>(
      context: ctx,
      position: RelativeRect.fromLTRB(pos.dx, pos.dy, pos.dx, pos.dy),
      color: ColorTokens.surface,
      items: [
        const PopupMenuItem(
            value: 'play',
            child: _MenuItem(icon: Icons.play_arrow, label: 'Play')),
        for (final d in devices)
          PopupMenuItem(
              value: 'transfer:${d.path}',
              child: _MenuItem(
                  icon: Icons.download,
                  label: isBulk
                      ? 'Transfer $bulkLabel to ${d.label}'
                      : 'Transfer to ${d.label}')),
        PopupMenuItem(
            value: 'playlist',
            child: _MenuItem(
                icon: Icons.playlist_add,
                label: isBulk
                    ? 'Add $bulkLabel to Playlist'
                    : 'Add to Playlist')),
        const PopupMenuItem(
            value: 'info',
            child: _MenuItem(icon: Icons.info_outline, label: 'Get Info')),
      ],
    );
    if (!ctx.mounted) return;
    if (result == 'play') {
      unawaited(ref
          .read(playbackProvider.notifier)
          .playSong(song, queue: allSongs, index: index));
    } else if (result != null && result.startsWith('transfer:')) {
      final devicePath = result.substring(9);
      final repo = ref.read(libraryRepositoryProvider);
      if (repo != null) {
        ref
            .read(transferQueueProvider.notifier)
            .enqueue(isBulk ? bulkSongs : [song], devicePath);
        if (isBulk) ref.read(songSelectionProvider.notifier).clear();
      }
    } else if (result == 'playlist') {
      final ids = isBulk ? bulkSongs.map((s) => s.id).toList() : [song.id];
      unawaited(showAddToPlaylistDialog(ctx, ref, ids));
      if (isBulk) ref.read(songSelectionProvider.notifier).clear();
    } else if (result == 'info') {
      unawaited(showSongMetadataDialog(ctx, song));
    }
  }

  static String _fmt(int s) =>
      '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
}

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
            style: const TextStyle(
                fontSize: 13, color: ColorTokens.textPrimary)),
      ],
    );
  }
}
