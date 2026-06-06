import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/playback/lyrics_provider.dart';
import '../../application/playback/playback_notifier.dart';
import '../../core/theme/color_tokens.dart';
import '../../domain/models/lyrics.dart';
import '../../domain/models/song.dart';
import 'error_retry.dart';

/// Centered modal that shows lyrics for [song]. When the server returns
/// synced lyrics and [song] is currently playing, the active line is
/// highlighted and the list auto-scrolls to keep it in view.
Future<void> showLyricsDialog(BuildContext context, Song song) =>
    showDialog<void>(
      context: context,
      builder: (_) => _LyricsDialog(song: song),
    );

class _LyricsDialog extends ConsumerWidget {
  const _LyricsDialog({required this.song});
  final Song song;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(lyricsProvider(song.id));
    return Dialog(
      backgroundColor: ColorTokens.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 560),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(song.title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: ColorTokens.textPrimary,
                  )),
              if (song.artist != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(song.artist!,
                      style: const TextStyle(
                        fontSize: 12,
                        color: ColorTokens.textSecondary,
                      )),
                ),
              const SizedBox(height: 14),
              const Divider(height: 1, color: ColorTokens.glassBorder),
              Expanded(
                child: async.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (e, _) => ErrorRetry(
                    error: e,
                    onRetry: () => ref.invalidate(lyricsProvider(song.id)),
                    compact: true,
                  ),
                  data: (lyrics) {
                    if (lyrics == null || lyrics.isEmpty) {
                      return const Center(
                        child: Text(
                          'No lyrics available for this track.',
                          style: TextStyle(
                              color: ColorTokens.textSecondary, fontSize: 13),
                        ),
                      );
                    }
                    return lyrics.synced
                        ? _SyncedLyricsView(lyrics: lyrics, song: song)
                        : _PlainLyricsView(lyrics: lyrics);
                  },
                ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Close',
                      style: TextStyle(color: ColorTokens.textSecondary)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlainLyricsView extends StatelessWidget {
  const _PlainLyricsView({required this.lyrics});
  final Lyrics lyrics;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Text(
        lyrics.lines.map((l) => l.text).join('\n'),
        style: const TextStyle(
          fontSize: 13,
          color: ColorTokens.textPrimary,
          height: 1.55,
        ),
      ),
    );
  }
}

/// Auto-scrolling view for synced lyrics. Highlights the line whose
/// timestamp is the latest one we've passed; falls through to a plain view
/// when the song being looked at isn't the currently playing one (no
/// position to anchor against).
class _SyncedLyricsView extends ConsumerStatefulWidget {
  const _SyncedLyricsView({required this.lyrics, required this.song});

  final Lyrics lyrics;
  final Song song;

  @override
  ConsumerState<_SyncedLyricsView> createState() => _SyncedLyricsViewState();
}

class _SyncedLyricsViewState extends ConsumerState<_SyncedLyricsView> {
  final _scrollCtrl = ScrollController();
  int _lastHighlighted = -1;

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pb = ref.watch(playbackProvider);
    final isCurrent = pb.currentSong?.id == widget.song.id;
    final active = isCurrent ? _activeIndex(pb.position) : -1;

    // Scroll the active line to a third-from-top position so users see
    // upcoming lyrics. We do this from a post-frame callback so the layout
    // has settled.
    if (active >= 0 && active != _lastHighlighted) {
      _lastHighlighted = active;
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollTo(active));
    }

    return ListView.builder(
      controller: _scrollCtrl,
      padding: const EdgeInsets.symmetric(vertical: 14),
      itemCount: widget.lyrics.lines.length,
      itemBuilder: (_, i) {
        final line = widget.lyrics.lines[i];
        final highlighted = i == active;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Text(
            line.text.isEmpty ? ' ' : line.text, // keep blank rows visible
            style: TextStyle(
              fontSize: highlighted ? 14 : 13,
              fontWeight: highlighted ? FontWeight.w600 : FontWeight.w400,
              color: highlighted
                  ? ColorTokens.textPrimary
                  : ColorTokens.textSecondary,
              height: 1.55,
            ),
          ),
        );
      },
    );
  }

  /// Returns the index of the last line whose `start` is ≤ position. Linear
  /// scan is fine — lyric tracks are tiny (tens of lines).
  int _activeIndex(Duration position) {
    var idx = -1;
    for (var i = 0; i < widget.lyrics.lines.length; i++) {
      final s = widget.lyrics.lines[i].start;
      if (s == null) continue;
      if (s <= position) {
        idx = i;
      } else {
        break;
      }
    }
    return idx;
  }

  void _scrollTo(int index) {
    if (!_scrollCtrl.hasClients) return;
    // Heuristic line height. Doesn't need to be exact — the user sees a
    // smooth animated scroll either way.
    const approxLineHeight = 28.0;
    final viewport = _scrollCtrl.position.viewportDimension;
    final target =
        (index * approxLineHeight) - (viewport / 3);
    final clamped = target.clamp(
      _scrollCtrl.position.minScrollExtent,
      _scrollCtrl.position.maxScrollExtent,
    );
    _scrollCtrl.animateTo(
      clamped,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }
}
