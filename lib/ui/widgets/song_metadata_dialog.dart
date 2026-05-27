import 'package:flutter/material.dart';

import '../../core/theme/color_tokens.dart';
import '../../domain/models/song.dart';

Future<void> showSongMetadataDialog(BuildContext context, Song song) {
  return showDialog(
    context: context,
    builder: (_) => _SongMetadataDialog(song: song),
  );
}

class _SongMetadataDialog extends StatelessWidget {
  const _SongMetadataDialog({required this.song});
  final Song song;

  @override
  Widget build(BuildContext context) {
    final s = song;
    return AlertDialog(
      backgroundColor: ColorTokens.surface,
      title: const Text('Song Info',
          style: TextStyle(color: ColorTokens.textPrimary)),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _Row('Title', s.title),
            if (s.artist != null) _Row('Artist', s.artist!),
            if (s.albumArtist != null) _Row('Album Artist', s.albumArtist!),
            if (s.album != null) _Row('Album', s.album!),
            if (s.genre != null && s.genre!.isNotEmpty)
              _Row('Genre', s.genre!),
            if (s.year != null) _Row('Year', '${s.year}'),
            if (s.track != null) _Row('Track', '${s.track}'),
            if (s.discNumber != null) _Row('Disc', '${s.discNumber}'),
            if (s.duration != null)
              _Row('Duration', _fmt(s.duration!)),
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.info_outline,
                    size: 12, color: ColorTokens.textSecondary),
                const SizedBox(width: 6),
                const Expanded(
                  child: Text(
                    'Navidrome does not support metadata editing via its API.',
                    style: TextStyle(
                        fontSize: 10, color: ColorTokens.textSecondary),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close',
              style: TextStyle(color: ColorTokens.textSecondary)),
        ),
      ],
    );
  }

  static String _fmt(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: ColorTokens.textSecondary,
                letterSpacing: 0.3,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                  fontSize: 11, color: ColorTokens.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}
