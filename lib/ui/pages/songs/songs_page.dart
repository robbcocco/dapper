import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../application/library/library_notifier.dart';
import '../../../application/playback/playback_notifier.dart';
import '../../../core/theme/color_tokens.dart';
import '../../widgets/add_to_playlist_dialog.dart';
import '../../widgets/song_metadata_dialog.dart';
import '../../widgets/song_row.dart';

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

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(allSongsProvider);

    if (s.isLoading && s.songs.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (s.error != null && s.songs.isEmpty) {
      return Center(
        child: Text('${s.error}',
            style: const TextStyle(color: ColorTokens.textSecondary)),
      );
    }

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 12),
          decoration: const BoxDecoration(
              border:
                  Border(bottom: BorderSide(color: ColorTokens.divider))),
          child: Row(
            children: [
              const Text(
                'Songs',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: ColorTokens.textPrimary,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '${s.songs.length}${s.hasMore ? '+' : ''} songs',
                style: const TextStyle(
                    fontSize: 12, color: ColorTokens.textSecondary),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            controller: _scrollCtrl,
            itemCount: s.songs.length + (s.isLoading ? 1 : 0),
            itemExtent: 48,
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
              return SongRow(
                song: song,
                index: i,
                showArtist: true,
                onTap: () => ref
                    .read(playbackProvider.notifier)
                    .playSong(song, queue: s.songs, index: i),
                onAddToPlaylist: () =>
                    showAddToPlaylistDialog(context, ref, [song.id]),
                onGetInfo: () =>
                    showSongMetadataDialog(context, ref, song),
              );
            },
          ),
        ),
      ],
    );
  }
}
