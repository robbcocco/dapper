import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/library/starred_notifier.dart';
import '../../application/playback/playback_notifier.dart';
import '../../application/providers/providers.dart';
import '../../core/theme/color_tokens.dart';
import '../../domain/models/song.dart';

/// Generic song row used across Songs, Album detail, and Playlist pages.
class SongRow extends ConsumerWidget {
  const SongRow({
    super.key,
    required this.song,
    this.index,
    this.showArtist = false,
    this.onTap,
    this.onAddToPlaylist,
    this.onRemove,
    this.onGetInfo,
    this.trailing,
  });

  final Song song;
  final int? index;
  final bool showArtist;
  final VoidCallback? onTap;
  final VoidCallback? onAddToPlaylist;
  final VoidCallback? onRemove;
  final VoidCallback? onGetInfo;
  final Widget? trailing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final starred = ref.watch(starredProvider);
    final isStarred = starred.contains(song.id);
    final currentSong = ref.watch(
        playbackProvider.select((s) => s.currentSong));
    final isPlaying = currentSong?.id == song.id;

    final rowHeight = showArtist ? 48.0 : 40.0;

    return GestureDetector(
      onTap: onTap,
      onSecondaryTapUp: (d) => _showMenu(context, ref, d.globalPosition),
      child: Container(
        height: rowHeight,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        decoration: BoxDecoration(
          color: isPlaying
              ? ColorTokens.accent.withValues(alpha: 0.08)
              : Colors.transparent,
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
    final device = ref.read(selectedDeviceProvider);
    final items = <PopupMenuEntry<String>>[
      const PopupMenuItem(
        value: 'play',
        child: _MenuItem(icon: Icons.play_arrow, label: 'Play'),
      ),
      if (device != null)
        PopupMenuItem(
          value: 'transfer',
          child: _MenuItem(icon: Icons.download, label: 'Transfer to ${device.label}'),
        ),
      if (onAddToPlaylist != null)
        const PopupMenuItem(
          value: 'playlist',
          child: _MenuItem(icon: Icons.playlist_add, label: 'Add to Playlist'),
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
    if (result == 'transfer') {
      final d = ref.read(selectedDeviceProvider);
      final repo = ref.read(libraryRepositoryProvider);
      if (d != null && repo != null) {
        ref.read(transferQueueProvider.notifier)
            .enqueue([song], d.path, repo.downloadUri);
      }
    }
    if (result == 'playlist') onAddToPlaylist?.call();
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
