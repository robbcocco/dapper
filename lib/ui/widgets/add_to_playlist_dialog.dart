import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/library/library_notifier.dart';
import '../../application/library/playlist_actions_notifier.dart';
import '../../core/theme/color_tokens.dart';
import '../../domain/models/playlist.dart';

/// Shows a bottom-sheet style dialog to pick a playlist (or create new),
/// then calls [onSelected] with the chosen playlist ID.
Future<void> showAddToPlaylistDialog(
  BuildContext context,
  WidgetRef ref,
  List<String> songIds,
) async {
  await showDialog<void>(
    context: context,
    builder: (_) => _AddToPlaylistDialog(songIds: songIds, ref: ref),
  );
}

class _AddToPlaylistDialog extends ConsumerStatefulWidget {
  const _AddToPlaylistDialog({required this.songIds, required this.ref});
  final List<String> songIds;
  final WidgetRef ref;

  @override
  ConsumerState<_AddToPlaylistDialog> createState() =>
      _AddToPlaylistDialogState();
}

class _AddToPlaylistDialogState extends ConsumerState<_AddToPlaylistDialog> {
  bool _creating = false;
  final _nameCtrl = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final playlists = ref.watch(playlistsProvider);

    return Dialog(
      backgroundColor: ColorTokens.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 20, 20, 12),
              child: Text(
                'Add to Playlist',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: ColorTokens.textPrimary,
                ),
              ),
            ),
            if (_creating) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: TextField(
                  controller: _nameCtrl,
                  autofocus: true,
                  style: const TextStyle(
                      fontSize: 13, color: ColorTokens.textPrimary),
                  decoration: InputDecoration(
                    hintText: 'Playlist name',
                    hintStyle: const TextStyle(color: ColorTokens.textSecondary),
                    filled: true,
                    fillColor: ColorTokens.surfaceVariant,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                  ),
                  onSubmitted: (_) => _createAndAdd(),
                ),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () =>
                          setState(() => _creating = false),
                      child: const Text('Cancel',
                          style:
                              TextStyle(color: ColorTokens.textSecondary)),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: _loading ? null : _createAndAdd,
                      style: FilledButton.styleFrom(
                          backgroundColor: ColorTokens.accent),
                      child: _loading
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Text('Create'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ] else ...[
              // New playlist button
              InkWell(
                onTap: () => setState(() => _creating = true),
                child: const Padding(
                  padding:
                      EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  child: Row(
                    children: [
                      Icon(Icons.add_circle_outline,
                          size: 18, color: ColorTokens.accent),
                      SizedBox(width: 12),
                      Text('New Playlist',
                          style: TextStyle(
                              fontSize: 13, color: ColorTokens.accent)),
                    ],
                  ),
                ),
              ),
              const Divider(color: ColorTokens.divider, height: 1),
              // Existing playlists
              playlists.when(
                data: (list) => ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 280),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: list.length,
                    itemExtent: 44,
                    itemBuilder: (_, i) =>
                        _PlaylistItem(playlist: list[i], onTap: () => _addTo(list[i])),
                  ),
                ),
                loading: () => const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (e, _) => Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text('$e',
                      style: const TextStyle(color: ColorTokens.textSecondary)),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _addTo(Playlist playlist) async {
    Navigator.of(context).pop();
    await ref
        .read(playlistActionsProvider.notifier)
        .addSongs(playlist.id, widget.songIds);
  }

  Future<void> _createAndAdd() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;
    setState(() => _loading = true);
    Navigator.of(context).pop();
    await ref
        .read(playlistActionsProvider.notifier)
        .createPlaylist(name, songIds: widget.songIds);
  }
}

class _PlaylistItem extends StatelessWidget {
  const _PlaylistItem({required this.playlist, required this.onTap});
  final Playlist playlist;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        child: Row(
          children: [
            const Icon(Icons.queue_music,
                size: 18, color: ColorTokens.textSecondary),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                playlist.name,
                style: const TextStyle(
                    fontSize: 13, color: ColorTokens.textPrimary),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(
              '${playlist.songCount}',
              style: const TextStyle(
                  fontSize: 11, color: ColorTokens.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
