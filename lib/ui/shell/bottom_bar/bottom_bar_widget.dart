import 'dart:ui';

import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../application/library/starred_notifier.dart';
import '../../../application/playback/playback_notifier.dart';
import '../../../application/providers/providers.dart';
import '../../../application/transfer/transfer_queue_notifier.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/color_tokens.dart';
import '../../../domain/models/transfer_task.dart';
import '../../widgets/cover_art_image.dart';

class BottomBarWidget extends StatelessWidget {
  const BottomBarWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
      child: Container(
        height: AppConstants.bottomBarHeight,
        // Opaque enough to read controls, translucent enough to hint at content below.
        color: const Color(0xB31C1C1E),
        child: const Row(
          children: [
            Expanded(flex: 3, child: _NowPlaying()),
            SizedBox(width: 1, child: ColoredBox(color: ColorTokens.glassBorder)),
            Expanded(flex: 5, child: _PlayerControls()),
            SizedBox(width: 1, child: ColoredBox(color: ColorTokens.glassBorder)),
            Expanded(flex: 3, child: _RightPanel()),
          ],
        ),
      ),
    );
  }
}

// ── Now Playing (left) ────────────────────────────────────────────────────────

class _NowPlaying extends ConsumerWidget {
  const _NowPlaying();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pb = ref.watch(playbackProvider);
    final song = pb.currentSong;
    final isStarred =
        song != null && ref.watch(starredProvider).contains(song.id);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
          children: [
            SizedBox(
              width: 44,
              height: 44,
              child: CoverArtImage(
                coverArtId: song?.coverArtId,
                size: 88,
                borderRadius: 6,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    song?.title ?? 'Not Playing',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: song != null
                          ? FontWeight.w600
                          : FontWeight.normal,
                      color: song != null
                          ? ColorTokens.textPrimary
                          : ColorTokens.textSecondary,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                  if (song?.artist != null)
                    Text(
                      song!.artist!,
                      style: const TextStyle(
                          fontSize: 11, color: ColorTokens.textSecondary),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                ],
              ),
            ),
            if (song != null)
              GestureDetector(
                onTap: () =>
                    ref.read(starredProvider.notifier).toggle(song.id),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Icon(
                    isStarred ? Icons.favorite : Icons.favorite_border,
                    size: 14,
                    color: isStarred
                        ? Colors.pinkAccent
                        : ColorTokens.textSecondary.withValues(alpha: 0.45),
                  ),
                ),
              ),
          ],
        ),
    );
  }
}

// ── Player controls (center) ──────────────────────────────────────────────────

class _PlayerControls extends ConsumerWidget {
  const _PlayerControls();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pb = ref.watch(playbackProvider);
    final notifier = ref.read(playbackProvider.notifier);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _SmallIconButton(
                icon: Icons.shuffle,
                active: pb.isShuffled,
                onPressed: notifier.toggleShuffle,
              ),
              const SizedBox(width: 4),
              IconButton(
                icon: const Icon(Icons.skip_previous, size: 22),
                color: pb.hasPrevious
                    ? ColorTokens.textSecondary
                    : ColorTokens.textSecondary.withValues(alpha: 0.3),
                onPressed: pb.hasPrevious ? notifier.previous : null,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
              const SizedBox(width: 4),
              GestureDetector(
                onTap: pb.currentSong != null ? notifier.togglePlayPause : null,
                child: Icon(
                  pb.isBuffering
                      ? Icons.hourglass_top
                      : pb.isPlaying
                          ? Icons.pause_circle_filled
                          : Icons.play_circle_filled,
                  size: 34,
                  color: pb.currentSong != null
                      ? ColorTokens.textPrimary
                      : ColorTokens.textSecondary.withValues(alpha: 0.3),
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                icon: const Icon(Icons.skip_next, size: 22),
                color: pb.hasNext
                    ? ColorTokens.textSecondary
                    : ColorTokens.textSecondary.withValues(alpha: 0.3),
                onPressed: pb.hasNext ? notifier.next : null,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
              const SizedBox(width: 4),
              _RepeatButton(
                  mode: pb.repeatMode, onPressed: notifier.cycleRepeat),
            ],
          ),
          const SizedBox(height: 2),
          Row(
            children: [
              Text(
                pb.currentSong != null ? _fmt(pb.position) : '0:00',
                style: const TextStyle(
                    fontSize: 10, color: ColorTokens.textSecondary),
              ),
              Expanded(
                child: SizedBox(
                  height: 16,
                  child: SliderTheme(
                    data: SliderThemeData(
                      trackHeight: 2,
                      thumbShape:
                          const RoundSliderThumbShape(enabledThumbRadius: 5),
                      overlayShape:
                          const RoundSliderOverlayShape(overlayRadius: 10),
                      activeTrackColor: ColorTokens.accent,
                      inactiveTrackColor: ColorTokens.surfaceVariant,
                      thumbColor: ColorTokens.accent,
                      overlayColor: ColorTokens.accent.withValues(alpha: 0.2),
                    ),
                    child: Slider(
                      value: _progress(pb),
                      onChangeEnd: (v) => notifier.seek(pb.duration * v),
                      onChanged: (_) {},
                    ),
                  ),
                ),
              ),
              Text(
                pb.currentSong != null ? _fmt(pb.duration) : '0:00',
                style: const TextStyle(
                    fontSize: 10, color: ColorTokens.textSecondary),
              ),
            ],
          ),
        ],
      ),
    );
  }

  double _progress(PlaybackState pb) {
    final total = pb.duration.inMilliseconds;
    if (total <= 0) return 0;
    return (pb.position.inMilliseconds / total).clamp(0.0, 1.0);
  }

  static String _fmt(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }
}

// ── Right panel: volume + transfer ────────────────────────────────────────────

class _RightPanel extends ConsumerWidget {
  const _RightPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pb = ref.watch(playbackProvider);
    final notifier = ref.read(playbackProvider.notifier);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
          children: [
            // Volume icon (adaptive)
            Icon(
              pb.volume == 0
                  ? Icons.volume_off
                  : pb.volume < 0.5
                      ? Icons.volume_down
                      : Icons.volume_up,
              size: 14,
              color: ColorTokens.textSecondary.withValues(alpha: 0.7),
            ),
            // Volume slider
            Expanded(
              child: SliderTheme(
                data: SliderThemeData(
                  trackHeight: 2,
                  thumbShape:
                      const RoundSliderThumbShape(enabledThumbRadius: 4),
                  overlayShape:
                      const RoundSliderOverlayShape(overlayRadius: 8),
                  activeTrackColor: ColorTokens.textSecondary,
                  inactiveTrackColor: ColorTokens.surfaceVariant,
                  thumbColor: ColorTokens.textSecondary,
                  overlayColor:
                      ColorTokens.textSecondary.withValues(alpha: 0.15),
                ),
                child: Slider(
                  value: pb.volume,
                  onChanged: notifier.setVolume,
                ),
              ),
            ),
            // Transfer status button
            const SizedBox(width: 4),
            const _TransferButton(),
          ],
        ),
    );
  }
}

// ── Transfer status popup button ──────────────────────────────────────────────

class _TransferButton extends ConsumerWidget {
  const _TransferButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final queue = ref.watch(transferQueueProvider);
    final active = queue.activeCount;
    final hasActive = active > 0;

    if (queue.isEmpty) return const SizedBox(width: 28, height: 28);

    return Tooltip(
      message: hasActive
          ? 'Transferring $active file${active == 1 ? '' : 's'}…'
          : 'Transfer complete — tap for details',
      preferBelow: false,
      child: GestureDetector(
        onTapDown: (d) => _show(context, ref, d.globalPosition),
        child: SizedBox(
          width: 28,
          height: 28,
          child: Center(
            child: hasActive
                ? SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.5,
                      value: queue.aggregateProgress > 0
                          ? queue.aggregateProgress
                          : null,
                      color: ColorTokens.accent,
                    ),
                  )
                : Icon(
                    Icons.cloud_done_outlined,
                    size: 15,
                    color: ColorTokens.textSecondary.withValues(alpha: 0.55),
                  ),
          ),
        ),
      ),
    );
  }

  void _show(BuildContext context, WidgetRef ref, Offset pos) {
    showMenu<void>(
      context: context,
      position: RelativeRect.fromLTRB(
          pos.dx - 296, pos.dy - 360, pos.dx + 4, pos.dy),
      color: ColorTokens.surface,
      elevation: 10,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: ColorTokens.glassBorder),
      ),
      items: [
        PopupMenuItem(
          enabled: false,
          padding: EdgeInsets.zero,
          child: _TransferPopupContent(
            onClear: () =>
                ref.read(transferQueueProvider.notifier).clearCompleted(),
          ),
        ),
      ],
    );
  }
}

class _TransferPopupContent extends ConsumerWidget {
  const _TransferPopupContent({required this.onClear});
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasks = ref
        .watch(transferQueueProvider)
        .where((t) => t.status != TransferStatus.cancelled)
        .toList();

    return SizedBox(
      width: 300,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 8, 8),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Transfer Queue',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: ColorTokens.textPrimary,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: onClear,
                  style: TextButton.styleFrom(
                    foregroundColor: ColorTokens.accent,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: const Size(0, 28),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('Clear done',
                      style: TextStyle(fontSize: 11)),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: ColorTokens.glassBorder),
          if (tasks.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Text('No transfers',
                  style: TextStyle(
                      fontSize: 12, color: ColorTokens.textSecondary)),
            )
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 280),
              child: ListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.only(bottom: 6),
                itemCount: tasks.length,
                itemBuilder: (_, i) => _TaskRow(task: tasks[i]),
              ),
            ),
        ],
      ),
    );
  }
}

class _TaskRow extends StatelessWidget {
  const _TaskRow({required this.task});
  final TransferTask task;

  @override
  Widget build(BuildContext context) {
    final (icon, iconColor) = switch (task.status) {
      TransferStatus.completed => (Icons.check_circle_outline, Colors.green),
      TransferStatus.failed => (Icons.error_outline, Colors.redAccent),
      TransferStatus.inProgress => (Icons.sync, ColorTokens.accent),
      _ => (Icons.schedule, ColorTokens.textSecondary),
    };

    final pct = task.status == TransferStatus.inProgress && task.totalBytes > 0
        ? '${(task.progress * 100).round()}%'
        : null;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(icon, size: 13, color: iconColor),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        task.song.title,
                        style: const TextStyle(
                            fontSize: 12, color: ColorTokens.textPrimary),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (pct != null) ...[
                      const SizedBox(width: 6),
                      Text(
                        pct,
                        style: const TextStyle(
                            fontSize: 10, color: ColorTokens.accent),
                      ),
                    ],
                  ],
                ),
                if (task.status == TransferStatus.inProgress)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        // null = indeterminate until we know total size
                        value: task.totalBytes > 0 ? task.progress : null,
                        minHeight: 2,
                        backgroundColor: ColorTokens.surfaceVariant,
                        valueColor:
                            const AlwaysStoppedAnimation(ColorTokens.accent),
                      ),
                    ),
                  ),
                if (task.status == TransferStatus.failed)
                  Text(
                    task.errorMessage ?? 'Failed',
                    style: const TextStyle(
                        fontSize: 10, color: Colors.redAccent),
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Shared small widgets ──────────────────────────────────────────────────────

class _SmallIconButton extends StatelessWidget {
  const _SmallIconButton({
    required this.icon,
    required this.onPressed,
    this.active = false,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon, size: 16),
      color: active
          ? ColorTokens.accent
          : ColorTokens.textSecondary.withValues(alpha: 0.6),
      onPressed: onPressed,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
    );
  }
}

class _RepeatButton extends StatelessWidget {
  const _RepeatButton({required this.mode, required this.onPressed});

  final RepeatMode mode;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final (icon, active) = switch (mode) {
      RepeatMode.none => (Icons.repeat, false),
      RepeatMode.all => (Icons.repeat, true),
      RepeatMode.one => (Icons.repeat_one, true),
    };
    return IconButton(
      icon: Icon(icon, size: 16),
      color: active
          ? ColorTokens.accent
          : ColorTokens.textSecondary.withValues(alpha: 0.6),
      onPressed: onPressed,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
    );
  }
}
