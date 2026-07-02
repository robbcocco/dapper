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
import '../../widgets/confirm_dialog.dart';
import '../../widgets/cover_art_image.dart';
import '../../widgets/lyrics_dialog.dart';
import '../../widgets/transfer_queue_grouping.dart';

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
    final isStarred = song != null &&
        ref.watch(starredProvider.select((s) => s.contains(song.id)));

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
            if (song != null) ...[
              GestureDetector(
                behavior: HitTestBehavior.opaque,
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
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => showLyricsDialog(context, song),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Icon(
                    Icons.lyrics_outlined,
                    size: 14,
                    color: ColorTokens.textSecondary.withValues(alpha: 0.6),
                  ),
                ),
              ),
            ],
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
                behavior: HitTestBehavior.opaque,
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
    final (isEmpty, active, completed, total) = ref.watch(
      transferQueueProvider.select((q) {
        final countable = q.where((t) =>
            t.status != TransferStatus.cancelled &&
            t.status != TransferStatus.failed);
        return (
          q.isEmpty,
          q.activeCount,
          countable.where((t) => t.status == TransferStatus.completed).length,
          countable.length,
        );
      }),
    );
    // Each in-progress song contributes its partial byte progress as a
    // fraction of one song. m.length is the actual downloading count (≤ concurrency),
    // not the full active count which includes queued songs.
    final (inProgressFraction, inProgressCount) = ref.watch(
      transferProgressProvider.select((m) {
        if (m.isEmpty) return (0.0, 0);
        var received = 0, totalBytes = 0;
        for (final e in m.values) { received += e.$1; totalBytes += e.$2; }
        return (totalBytes > 0 ? received / totalBytes : 0.0, m.length);
      }),
    );
    final progress = total > 0
        ? (completed + inProgressFraction * inProgressCount) / total
        : 0.0;
    final hasActive = active > 0;

    if (isEmpty) return const SizedBox(width: 28, height: 28);

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
                    child: _SpinningProgress(
                      progress: progress,
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
    // Anchor the popup to the spinner icon — bottom-right corner of the
    // popup lines up with the tap location (the icon), and the popup
    // extends up-and-to-the-left from there.
    const popupWidth = 300.0;
    const popupHeight = 360.0;
    final size = MediaQuery.sizeOf(context);
    showMenu<void>(
      context: context,
      position: RelativeRect.fromLTRB(
        pos.dx - popupWidth,            // left edge of popup
        pos.dy - popupHeight,           // top edge of popup
        size.width - pos.dx,            // right inset from screen right
        size.height - pos.dy,           // bottom inset from screen bottom
      ),
      color: ColorTokens.surface,
      elevation: 10,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: ColorTokens.glassBorder),
      ),
      items: const [
        PopupMenuItem(
          enabled: false,
          padding: EdgeInsets.zero,
          child: _TransferPopupContent(),
        ),
      ],
    );
  }
}

class _TransferPopupContent extends ConsumerWidget {
  const _TransferPopupContent();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Progress lives in a separate provider, so byte ticks never reach this
    // popup. The header actions and the task list each watch the queue in
    // their own Consumer, so a status change repaints only the affected
    // subtree while the shell + divider stay put.
    final notifier = ref.read(transferQueueProvider.notifier);

    return SizedBox(
      width: 300,
      height: 360,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 6, 6),
            child: Consumer(builder: (context, ref, _) {
              final queue = ref.watch(transferQueueProvider);
              final hasActive = queue.any((t) =>
                  t.status == TransferStatus.queued ||
                  t.status == TransferStatus.inProgress);
              final hasFailed =
                  queue.any((t) => t.status == TransferStatus.failed);
              final hasFinished = queue.any((t) =>
                  t.status == TransferStatus.completed ||
                  t.status == TransferStatus.failed ||
                  t.status == TransferStatus.cancelled);
              final isPaused = notifier.isAnyDevicePaused;
              return Row(
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
                if (hasActive || isPaused)
                  _BulkIconButton(
                    icon: isPaused ? Icons.play_arrow : Icons.pause,
                    tooltip: isPaused ? 'Resume all' : 'Pause all',
                    onPressed: isPaused
                        ? notifier.resume
                        : notifier.pause,
                  ),
                if (hasFailed)
                  _BulkIconButton(
                    icon: Icons.refresh,
                    tooltip: 'Retry all failed',
                    onPressed: notifier.retryAllFailed,
                  ),
                if (hasActive)
                  _BulkIconButton(
                    icon: Icons.cancel_outlined,
                    tooltip: 'Cancel all',
                    onPressed: () async {
                      // showDialog reopens against the root navigator; the
                      // popup menu may close itself but the confirm dialog
                      // appears on top either way.
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
                  ),
                if (hasFinished)
                  TextButton(
                    onPressed: notifier.clearCompleted,
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
              );
            }),
          ),
          const Divider(height: 1, color: ColorTokens.glassBorder),
          Expanded(
            child: Consumer(builder: (context, ref, _) {
              final tasks = ref
                  .watch(transferQueueProvider)
                  .where((t) => t.status != TransferStatus.cancelled)
                  .toList();
              if (tasks.isEmpty) {
                return const Center(
                  child: Text('No transfers',
                      style: TextStyle(
                          fontSize: 12,
                          color: ColorTokens.textSecondary)),
                );
              }
              final rows = buildQueueRows(tasks);
              return ListView.builder(
                padding: const EdgeInsets.only(bottom: 6),
                itemCount: rows.length,
                itemBuilder: (_, i) {
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
      ),
    );
  }
}

class _TaskRow extends ConsumerWidget {
  const _TaskRow({required this.task});
  final TransferTask task;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (icon, iconColor) = switch (task.status) {
      TransferStatus.completed => (Icons.check_circle_outline, Colors.green),
      TransferStatus.failed => (Icons.error_outline, Colors.redAccent),
      TransferStatus.inProgress => (Icons.sync, ColorTokens.accent),
      _ => (Icons.schedule, ColorTokens.textSecondary),
    };

    final (received, total) = task.status == TransferStatus.inProgress
        ? ref.watch(transferProgressProvider.select((m) =>
            m[task.id] ?? (0, 0)))
        : (0, 0);
    final pct = total > 0 ? '${((received / total) * 100).round()}%' : null;

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
                        value: total > 0 ? received / total : null,
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

    final (icon, iconColor) = switch (status) {
      TransferStatus.completed => (Icons.check_circle_outline, Colors.green),
      TransferStatus.failed => (Icons.error_outline, Colors.redAccent),
      TransferStatus.inProgress => (Icons.sync, ColorTokens.accent),
      _ => (Icons.schedule, ColorTokens.textSecondary),
    };

    final firstError = group
        .firstWhere(
          (t) => t.status == TransferStatus.failed,
          orElse: () => leader,
        )
        .errorMessage;

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
                        '$artist — $album',
                        style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: ColorTokens.textPrimary),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '$completed/$total',
                      style: const TextStyle(
                          fontSize: 10, color: ColorTokens.accent),
                    ),
                  ],
                ),
                if (status == TransferStatus.inProgress ||
                    status == TransferStatus.queued)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        value: progressValue,
                        minHeight: 2,
                        backgroundColor: ColorTokens.surfaceVariant,
                        valueColor:
                            const AlwaysStoppedAnimation(ColorTokens.accent),
                      ),
                    ),
                  ),
                if (status == TransferStatus.failed)
                  Text(
                    firstError ?? 'Failed',
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

// ── Spinning progress indicator ───────────────────────────────────────────────

class _SpinningProgress extends StatefulWidget {
  const _SpinningProgress({required this.progress, required this.color});
  final double progress;
  final Color color;

  @override
  State<_SpinningProgress> createState() => _SpinningProgressState();
}

class _SpinningProgressState extends State<_SpinningProgress>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RotationTransition(
      turns: _ctrl,
      child: CircularProgressIndicator(
        strokeWidth: 1.5,
        // Arc length = progress so you can still read completion at a glance,
        // but the whole thing keeps rotating so it never looks frozen.
        value: widget.progress > 0 ? widget.progress : null,
        color: widget.color,
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

/// Small icon button used for bulk queue actions in the transfer popup /
/// device page. The onPressed is nullable so we can disable an action
/// (e.g. resume without a library repo) instead of removing it and
/// shifting the row layout.
class _BulkIconButton extends StatelessWidget {
  const _BulkIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon, size: 14),
      tooltip: tooltip,
      color: ColorTokens.textSecondary,
      onPressed: onPressed,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
      splashRadius: 14,
    );
  }
}
