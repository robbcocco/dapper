import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../application/playback/playback_notifier.dart';
import '../../../application/providers/providers.dart';
import '../../../application/transfer/transfer_queue_notifier.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/color_tokens.dart';

class BottomBarWidget extends ConsumerWidget {
  const BottomBarWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      height: AppConstants.bottomBarHeight,
      decoration: const BoxDecoration(
        color: ColorTokens.surface,
        border: Border(top: BorderSide(color: ColorTokens.divider)),
      ),
      child: Row(
        children: [
          const Expanded(flex: 3, child: _PlayerControls()),
          Container(width: 1, color: ColorTokens.divider),
          Expanded(flex: 2, child: _TransferStatus(ref: ref)),
          Container(width: 1, color: ColorTokens.divider),
          Expanded(flex: 2, child: _DeviceInfo(ref: ref)),
        ],
      ),
    );
  }
}

// ── Player controls ───────────────────────────────────────────────────────────

class _PlayerControls extends ConsumerWidget {
  const _PlayerControls();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pb = ref.watch(playbackProvider);
    final notifier = ref.read(playbackProvider.notifier);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              // Shuffle
              _SmallIconButton(
                icon: Icons.shuffle,
                active: pb.isShuffled,
                onPressed: notifier.toggleShuffle,
              ),
              const SizedBox(width: 2),
              // Previous
              IconButton(
                icon: const Icon(Icons.skip_previous, size: 20),
                color: pb.hasPrevious
                    ? ColorTokens.textSecondary
                    : ColorTokens.textSecondary.withValues(alpha: 0.3),
                onPressed: pb.hasPrevious ? notifier.previous : null,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              ),
              const SizedBox(width: 2),
              // Play/Pause
              GestureDetector(
                onTap: pb.currentSong != null ? notifier.togglePlayPause : null,
                child: Icon(
                  pb.isBuffering
                      ? Icons.hourglass_top
                      : pb.isPlaying
                          ? Icons.pause_circle_filled
                          : Icons.play_circle_filled,
                  size: 30,
                  color: pb.currentSong != null
                      ? ColorTokens.textPrimary
                      : ColorTokens.textSecondary.withValues(alpha: 0.3),
                ),
              ),
              const SizedBox(width: 2),
              // Next
              IconButton(
                icon: const Icon(Icons.skip_next, size: 20),
                color: pb.hasNext
                    ? ColorTokens.textSecondary
                    : ColorTokens.textSecondary.withValues(alpha: 0.3),
                onPressed: pb.hasNext ? notifier.next : null,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              ),
              const SizedBox(width: 2),
              // Repeat
              _RepeatButton(mode: pb.repeatMode, onPressed: notifier.cycleRepeat),
              const SizedBox(width: 8),
              // Title + artist
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      pb.currentSong?.title ?? 'Not Playing',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: pb.currentSong != null
                            ? FontWeight.w500
                            : FontWeight.normal,
                        color: pb.currentSong != null
                            ? ColorTokens.textPrimary
                            : ColorTokens.textSecondary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (pb.currentSong?.artist != null)
                      Text(
                        pb.currentSong!.artist!,
                        style: const TextStyle(
                            fontSize: 10, color: ColorTokens.textSecondary),
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Time
              Text(
                pb.currentSong != null
                    ? '${_fmt(pb.position)} / ${_fmt(pb.duration)}'
                    : '',
                style: const TextStyle(
                    fontSize: 10, color: ColorTokens.textSecondary),
              ),
              const SizedBox(width: 8),
              // Volume
              Icon(
                pb.volume == 0
                    ? Icons.volume_off
                    : pb.volume < 0.5
                        ? Icons.volume_down
                        : Icons.volume_up,
                size: 14,
                color: ColorTokens.textSecondary,
              ),
              SizedBox(
                width: 72,
                child: SliderTheme(
                  data: SliderThemeData(
                    trackHeight: 2,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 4),
                    overlayShape: const RoundSliderOverlayShape(overlayRadius: 8),
                    activeTrackColor: ColorTokens.textSecondary,
                    inactiveTrackColor: ColorTokens.surfaceVariant,
                    thumbColor: ColorTokens.textSecondary,
                    overlayColor: ColorTokens.textSecondary.withValues(alpha: 0.15),
                  ),
                  child: Slider(
                    value: pb.volume,
                    onChanged: (v) => notifier.setVolume(v),
                  ),
                ),
              ),
            ],
          ),
          // Seek bar
          SizedBox(
            height: 16,
            child: SliderTheme(
              data: SliderThemeData(
                trackHeight: 2,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
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

// ── Transfer status ───────────────────────────────────────────────────────────

class _TransferStatus extends StatelessWidget {
  const _TransferStatus({required this.ref});
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    final queue = ref.watch(transferQueueProvider);
    final active = queue.activeCount;
    final progress = queue.aggregateProgress;
    final hasActive = active > 0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            hasActive
                ? 'Transferring $active file${active == 1 ? '' : 's'}…'
                : 'No transfer in progress',
            style: TextStyle(
              fontSize: 11,
              color: hasActive
                  ? ColorTokens.textPrimary
                  : ColorTokens.textSecondary,
            ),
          ),
          if (hasActive) ...[
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: progress > 0 ? progress : null,
                backgroundColor: ColorTokens.surfaceVariant,
                valueColor:
                    const AlwaysStoppedAnimation(ColorTokens.accent),
                minHeight: 3,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Device info ───────────────────────────────────────────────────────────────

class _DeviceInfo extends StatelessWidget {
  const _DeviceInfo({required this.ref});
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    final devices = ref.watch(connectedDevicesProvider).valueOrNull ?? [];
    final label = devices.isEmpty
        ? 'No device connected'
        : devices.map((d) => d.label).join(', ');

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: devices.isEmpty
                  ? ColorTokens.textSecondary
                  : ColorTokens.accent,
            ),
            overflow: TextOverflow.ellipsis,
          ),
          if (devices.isNotEmpty)
            Text(
              '${devices.first.availableFormatted} free',
              style: const TextStyle(
                  fontSize: 10, color: ColorTokens.textSecondary),
            ),
        ],
      ),
    );
  }
}
