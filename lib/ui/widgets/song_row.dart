import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/library/song_selection_notifier.dart';
import '../../application/library/starred_notifier.dart';
import '../../application/playback/playback_notifier.dart';
import '../../application/providers/providers.dart';
import '../../core/theme/color_tokens.dart';
import '../../domain/models/song.dart';
import 'add_to_playlist_dialog.dart';

/// Modifier keys held when [SongRow] is tapped. Pages that want shift-click
/// range selection or cmd/ctrl-click toggle pass [SongRow.onTapWithModifiers]
/// and consult [shift] / [meta] / [control].
class TapModifiers {
  const TapModifiers({
    required this.shift,
    required this.meta,
    required this.control,
  });
  final bool shift;
  final bool meta;
  final bool control;

  bool get hasToggle => meta || control;
  bool get hasRange => shift;
  bool get hasAny => shift || meta || control;
}

/// Generic song row used across Songs, Album detail, and Playlist pages.
class SongRow extends ConsumerWidget {
  const SongRow({
    super.key,
    required this.song,
    this.index,
    this.showArtist = false,
    this.onTap,
    this.onTapWithModifiers,
    this.onAddToPlaylist,
    this.onRemove,
    this.onGetInfo,
    this.trailing,
    this.selected = false,
    this.selectionScopeKey,
    this.selectionAllSongs,
  });

  final Song song;
  final int? index;
  final bool showArtist;
  final VoidCallback? onTap;
  /// When provided, taps are routed through this callback with the current
  /// keyboard modifier state. Pages that want shift-click range selection or
  /// cmd/ctrl toggle wire this; [onTap] is ignored when this is set.
  final void Function(TapModifiers)? onTapWithModifiers;
  final VoidCallback? onAddToPlaylist;
  final VoidCallback? onRemove;
  final VoidCallback? onGetInfo;
  final Widget? trailing;
  /// Renders the row with a selection tint. Independent of "currently playing".
  final bool selected;
  /// Scope key + ordered song list used by the context menu to surface bulk
  /// "Transfer N selected" / "Add N selected to playlist" actions when this
  /// row is part of a multi-row selection. Both must be provided for bulk
  /// menu items to appear.
  final String? selectionScopeKey;
  final List<Song>? selectionAllSongs;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isStarred =
        ref.watch(starredProvider.select((s) => s.contains(song.id)));
    final isPlaying = ref.watch(
        playbackProvider.select((s) => s.currentSong?.id == song.id));

    final rowHeight = showArtist ? 48.0 : 40.0;

    final bgColor = selected
        ? ColorTokens.accent.withValues(alpha: 0.18)
        : isPlaying
            ? ColorTokens.accent.withValues(alpha: 0.08)
            : Colors.transparent;

    return GestureDetector(
      onTap: () {
        if (onTapWithModifiers != null) {
          final keyboard = HardwareKeyboard.instance;
          onTapWithModifiers!(TapModifiers(
            shift: keyboard.isShiftPressed,
            meta: keyboard.isMetaPressed,
            control: keyboard.isControlPressed,
          ));
          return;
        }
        onTap?.call();
      },
      onSecondaryTapUp: (d) => _showMenu(context, ref, d.globalPosition),
      child: Container(
        height: rowHeight,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        decoration: BoxDecoration(
          color: bgColor,
          border: const Border(
            bottom: BorderSide(
                color: Color(0xFF2A2A2A)),
          ),
        ),
        child: Row(
          children: [
            // Track / index number
            SizedBox(
              width: 28,
              child: isPlaying
                  ? const Icon(Icons.equalizer,
                      size: 14, color: ColorTokens.accent)
                  : Text(
                      '${index != null ? index! + 1 : song.track ?? '·'}',
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                          fontSize: 12, color: ColorTokens.textSecondary),
                    ),
            ),
            const SizedBox(width: 16),
            // Title (+ optional artist)
            Expanded(
              child: showArtist
                  ? Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          song.title,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            color: isPlaying
                                ? ColorTokens.accent
                                : ColorTokens.textPrimary,
                          ),
                        ),
                        if (song.artist != null)
                          Text(
                            song.artist!,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 11,
                                color: ColorTokens.textSecondary),
                          ),
                      ],
                    )
                  : Text(
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
            // Star
            GestureDetector(
              onTap: () =>
                  ref.read(starredProvider.notifier).toggle(song.id),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Icon(
                  isStarred ? Icons.star : Icons.star_border,
                  size: 14,
                  color: isStarred
                      ? Colors.amber
                      : ColorTokens.textSecondary.withValues(alpha: 0.4),
                ),
              ),
            ),
            // Optional trailing (e.g. transfer checkmark)
            ?trailing,
            // Duration
            if (song.duration != null)
              Text(
                _fmt(song.duration!),
                style: const TextStyle(
                    fontSize: 12, color: ColorTokens.textSecondary),
              ),
          ],
        ),
      ),
    );
  }

  void _showMenu(BuildContext ctx, WidgetRef ref, Offset pos) async {
    final devices = ref.read(connectedDevicesProvider).valueOrNull ?? [];
    // Resolve bulk-selection context. Bulk menu items only appear when the
    // row is part of a multi-row selection AND the caller passed a song list
    // we can use to materialise the selected ids back into Song objects.
    final selection = ref.read(songSelectionProvider);
    final scope = selectionScopeKey;
    final list = selectionAllSongs;
    final isBulk = scope != null &&
        list != null &&
        selection.matches(scope) &&
        selection.isSelected(song.id) &&
        selection.count > 1;
    final bulkSongs = isBulk
        ? list.where((s) => selection.selectedIds.contains(s.id)).toList()
        : const <Song>[];
    final bulkLabel = '${bulkSongs.length} selected songs';

    final items = <PopupMenuEntry<String>>[
      const PopupMenuItem(
        value: 'play',
        child: _MenuItem(icon: Icons.play_arrow, label: 'Play'),
      ),
      for (final d in devices)
        PopupMenuItem(
          value: 'transfer:${d.path}',
          child: _MenuItem(
              icon: Icons.download,
              label: isBulk
                  ? 'Transfer $bulkLabel to ${d.label}'
                  : 'Transfer to ${d.label}'),
        ),
      if (onAddToPlaylist != null)
        PopupMenuItem(
          value: 'playlist',
          child: _MenuItem(
              icon: Icons.playlist_add,
              label: isBulk
                  ? 'Add $bulkLabel to Playlist'
                  : 'Add to Playlist'),
        ),
      if (onRemove != null)
        const PopupMenuItem(
          value: 'remove',
          child: _MenuItem(icon: Icons.remove_circle_outline, label: 'Remove from Playlist'),
        ),
      if (onGetInfo != null)
        const PopupMenuItem(
          value: 'info',
          child: _MenuItem(icon: Icons.info_outline, label: 'Get Info'),
        ),
    ];

    final result = await showMenu<String>(
      context: ctx,
      position: RelativeRect.fromLTRB(pos.dx, pos.dy, pos.dx, pos.dy),
      color: ColorTokens.surface,
      items: items,
    );

    if (result == 'play') onTap?.call();
    if (result != null && result.startsWith('transfer:')) {
      final devicePath = result.substring(9);
      final repo = ref.read(libraryRepositoryProvider);
      if (repo != null) {
        ref
            .read(transferQueueProvider.notifier)
            .enqueue(isBulk ? bulkSongs : [song], devicePath);
        if (isBulk) ref.read(songSelectionProvider.notifier).clear();
      }
    }
    if (result == 'playlist') {
      if (isBulk) {
        if (!ctx.mounted) return;
        unawaited(showAddToPlaylistDialog(
            ctx, ref, bulkSongs.map((s) => s.id).toList()));
        ref.read(songSelectionProvider.notifier).clear();
      } else {
        onAddToPlaylist?.call();
      }
    }
    if (result == 'remove') onRemove?.call();
    if (result == 'info') onGetInfo?.call();
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
