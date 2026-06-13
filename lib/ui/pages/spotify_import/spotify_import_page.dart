import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../application/library/sidebar_state.dart';
import '../../../application/spotify_import/song_matcher.dart';
import '../../../application/spotify_import/spotify_import_notifier.dart';
import '../../../application/spotify_import/spotify_import_state.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/color_tokens.dart';
import '../../../domain/models/song.dart';

class SpotifyImportPage extends ConsumerWidget {
  const SpotifyImportPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(spotifyImportProvider);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, AppConstants.scrollBottomInset),
      child: switch (state) {
        ImportIdle() => const _IdleView(),
        ImportScraping() =>
          const _BusyView(message: 'Fetching playlist from Spotify…'),
        ImportMatching(:final playlistName, :final done, :final total) =>
          _MatchingView(
              playlistName: playlistName, done: done, total: total),
        ImportReview(
          :final playlistName,
          :final truncated,
          :final matches,
        ) =>
          _ReviewView(
              playlistName: playlistName,
              truncated: truncated,
              matches: matches),
        ImportCreating() =>
          const _BusyView(message: 'Creating Navidrome playlist…'),
        ImportDone(
          :final playlistName,
          :final importedCount,
          :final skippedCount,
        ) =>
          _DoneView(
              playlistName: playlistName,
              importedCount: importedCount,
              skippedCount: skippedCount),
        ImportError(:final message) => _ErrorView(message: message),
      },
    );
  }
}

// ── Idle (URL entry) ──────────────────────────────────────────────────────────

class _IdleView extends ConsumerStatefulWidget {
  const _IdleView();

  @override
  ConsumerState<_IdleView> createState() => _IdleViewState();
}

class _IdleViewState extends ConsumerState<_IdleView> {
  final _ctrl = TextEditingController();
  bool _valid = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Import from Spotify',
          style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: ColorTokens.textPrimary),
        ),
        const SizedBox(height: 8),
        const Text(
          'Paste a public Spotify playlist link. Dapper scrapes the track list '
          'and matches each song against your Navidrome library — you can fix '
          'any misses before the playlist is created.',
          style: TextStyle(fontSize: 12, color: ColorTokens.textSecondary),
        ),
        const SizedBox(height: 24),
        TextField(
          controller: _ctrl,
          autofocus: true,
          style: const TextStyle(fontSize: 13, color: ColorTokens.textPrimary),
          decoration: InputDecoration(
            hintText: 'https://open.spotify.com/playlist/…',
            hintStyle: const TextStyle(color: ColorTokens.textSecondary),
            filled: true,
            fillColor: ColorTokens.surfaceVariant,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide.none,
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          ),
          onChanged: (_) => setState(() {
            _valid = _ctrl.text.trim().isNotEmpty;
          }),
          onSubmitted: (_) => _start(),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            FilledButton.icon(
              onPressed: _valid ? _start : null,
              icon: const Icon(Icons.cloud_download_outlined, size: 16),
              label: const Text('Import'),
              style: FilledButton.styleFrom(
                backgroundColor: ColorTokens.accent,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                textStyle: const TextStyle(fontSize: 13),
              ),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: () => ref
                  .read(selectedSectionProvider.notifier)
                  .state = SidebarSection.playlists,
              child: const Text('Cancel'),
            ),
          ],
        ),
        const SizedBox(height: 32),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: ColorTokens.surface,
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline,
                  size: 14, color: ColorTokens.textSecondary),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Only public, non-collaborative playlists work. Spotify caps '
                  'embedded playlists at the first ~100 tracks; the importer '
                  'will warn you if it sees a truncated list.',
                  style: TextStyle(
                      fontSize: 11, color: ColorTokens.textSecondary),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _start() {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    unawaited(ref.read(spotifyImportProvider.notifier).startImport(text));
  }
}

// ── Busy ──────────────────────────────────────────────────────────────────────

class _BusyView extends StatelessWidget {
  const _BusyView({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(strokeWidth: 2),
          const SizedBox(height: 16),
          Text(message,
              style: const TextStyle(
                  fontSize: 13, color: ColorTokens.textSecondary)),
        ],
      ),
    );
  }
}

class _MatchingView extends StatelessWidget {
  const _MatchingView({
    required this.playlistName,
    required this.done,
    required this.total,
  });
  final String playlistName;
  final int done;
  final int total;

  @override
  Widget build(BuildContext context) {
    final pct = total == 0 ? 0.0 : done / total;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(playlistName,
              style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: ColorTokens.textPrimary)),
          const SizedBox(height: 16),
          SizedBox(
            width: 280,
            child: LinearProgressIndicator(
              value: pct,
              backgroundColor: ColorTokens.surface,
              color: ColorTokens.accent,
            ),
          ),
          const SizedBox(height: 8),
          Text('Matching $done of $total tracks…',
              style: const TextStyle(
                  fontSize: 12, color: ColorTokens.textSecondary)),
        ],
      ),
    );
  }
}

// ── Review ────────────────────────────────────────────────────────────────────

class _ReviewView extends ConsumerStatefulWidget {
  const _ReviewView({
    required this.playlistName,
    required this.truncated,
    required this.matches,
  });
  final String playlistName;
  final bool truncated;
  final List<TrackMatch> matches;

  @override
  ConsumerState<_ReviewView> createState() => _ReviewViewState();
}

class _ReviewViewState extends ConsumerState<_ReviewView> {
  late final TextEditingController _nameCtrl;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.playlistName);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final matched = widget.matches.where((m) => m.selectedId != null).length;
    final missing = widget.matches.length - matched;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _nameCtrl,
                style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: ColorTokens.textPrimary),
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Text(
              '$matched of ${widget.matches.length} matched',
              style: const TextStyle(
                  fontSize: 12, color: ColorTokens.textSecondary),
            ),
            if (missing > 0) ...[
              const SizedBox(width: 12),
              Text(
                '$missing need attention',
                style: const TextStyle(
                    fontSize: 12, color: Colors.orangeAccent),
              ),
            ],
          ],
        ),
        if (widget.truncated) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Row(
              children: [
                Icon(Icons.warning_amber_rounded,
                    size: 14, color: Colors.orangeAccent),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Spotify only exposes the first ~100 tracks for this '
                    'playlist — the rest are not visible without login.',
                    style: TextStyle(
                        fontSize: 11, color: Colors.orangeAccent),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 16),
        Expanded(
          child: ListView.builder(
            itemCount: widget.matches.length,
            itemBuilder: (context, i) => _MatchRow(
              index: i,
              match: widget.matches[i],
              onTap: () => _pickCandidate(i),
            ),
          ),
        ),
        const Divider(height: 24, color: ColorTokens.glassBorder),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: () =>
                  ref.read(spotifyImportProvider.notifier).reset(),
              child: const Text('Cancel'),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: matched == 0
                  ? null
                  : () => ref
                      .read(spotifyImportProvider.notifier)
                      .commitImport(name: _nameCtrl.text.trim().isEmpty
                          ? null
                          : _nameCtrl.text.trim()),
              icon: const Icon(Icons.check, size: 16),
              label: Text('Create playlist ($matched)'),
              style: FilledButton.styleFrom(
                backgroundColor: ColorTokens.accent,
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 10),
                textStyle: const TextStyle(fontSize: 13),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _pickCandidate(int index) async {
    final match = widget.matches[index];
    final picked = await showDialog<_PickResult>(
      context: context,
      builder: (_) => _CandidatePickerDialog(match: match),
    );
    if (picked == null) return;
    ref
        .read(spotifyImportProvider.notifier)
        .setSelection(index, picked.songId, song: picked.song);
  }
}

class _MatchRow extends StatelessWidget {
  const _MatchRow({
    required this.index,
    required this.match,
    required this.onTap,
  });

  final int index;
  final TrackMatch match;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final selected = _selectedSong();
    final isMatched = selected != null;
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        decoration: const BoxDecoration(
          border: Border(
            bottom: BorderSide(color: ColorTokens.glassBorder, width: 0.5),
          ),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 24,
              child: Text('${index + 1}',
                  style: const TextStyle(
                      fontSize: 11, color: ColorTokens.textSecondary)),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    match.source.title,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 13, color: ColorTokens.textPrimary),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    match.source.artist,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 11, color: ColorTokens.textSecondary),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            const Icon(Icons.arrow_forward,
                size: 14, color: ColorTokens.textSecondary),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isMatched ? selected.title : 'No match — tap to choose',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      color: isMatched
                          ? ColorTokens.textPrimary
                          : Colors.orangeAccent,
                      fontStyle: isMatched
                          ? FontStyle.normal
                          : FontStyle.italic,
                    ),
                  ),
                  if (isMatched) ...[
                    const SizedBox(height: 2),
                    Text(
                      selected.artist ?? selected.albumArtist ?? '',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 11, color: ColorTokens.textSecondary),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            Icon(
              isMatched ? Icons.check_circle : Icons.error_outline,
              size: 16,
              color: isMatched ? Colors.greenAccent : Colors.orangeAccent,
            ),
          ],
        ),
      ),
    );
  }

  Song? _selectedSong() {
    final id = match.selectedId;
    if (id == null) return null;
    for (final c in match.candidates) {
      if (c.song.id == id) return c.song;
    }
    return null;
  }
}

// ── Candidate picker dialog ───────────────────────────────────────────────────

class _PickResult {
  const _PickResult(this.songId, [this.song]);
  final String? songId;
  final Song? song;
}

class _CandidatePickerDialog extends ConsumerStatefulWidget {
  const _CandidatePickerDialog({required this.match});
  final TrackMatch match;

  @override
  ConsumerState<_CandidatePickerDialog> createState() =>
      _CandidatePickerDialogState();
}

class _CandidatePickerDialogState
    extends ConsumerState<_CandidatePickerDialog> {
  final _searchCtrl = TextEditingController();
  List<Song>? _manualResults;
  bool _searching = false;
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onSearchChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () => _search(v));
  }

  Future<void> _search(String v) async {
    final q = v.trim();
    if (q.isEmpty) {
      setState(() => _manualResults = null);
      return;
    }
    setState(() => _searching = true);
    final results = await ref
        .read(spotifyImportProvider.notifier)
        .manualSearch(q);
    if (!mounted) return;
    setState(() {
      _manualResults = results;
      _searching = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final visible = _manualResults ??
        widget.match.candidates.map((c) => c.song).toList();
    final scoresById = {
      for (final c in widget.match.candidates) c.song.id: c.score,
    };
    return Dialog(
      backgroundColor: ColorTokens.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: SizedBox(
        width: 520,
        height: 480,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Pick a match',
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: ColorTokens.textPrimary)),
                  const SizedBox(height: 4),
                  Text(
                    '${widget.match.source.artist} — ${widget.match.source.title}',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 12, color: ColorTokens.textSecondary),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: TextField(
                controller: _searchCtrl,
                style: const TextStyle(
                    fontSize: 13, color: ColorTokens.textPrimary),
                decoration: InputDecoration(
                  hintText: 'Search the library…',
                  hintStyle:
                      const TextStyle(color: ColorTokens.textSecondary),
                  prefixIcon: const Icon(Icons.search,
                      size: 14, color: ColorTokens.textSecondary),
                  filled: true,
                  fillColor: ColorTokens.surfaceVariant,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
                ),
                onChanged: _onSearchChanged,
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: _searching
                  ? const Center(child: CircularProgressIndicator())
                  : visible.isEmpty
                      ? const Center(
                          child: Text(
                            'No candidates found.',
                            style: TextStyle(
                                fontSize: 12,
                                color: ColorTokens.textSecondary),
                          ),
                        )
                      : ListView.builder(
                          itemCount: visible.length,
                          itemBuilder: (context, i) {
                            final song = visible[i];
                            final score = scoresById[song.id];
                            final isCurrent =
                                widget.match.selectedId == song.id;
                            return InkWell(
                              onTap: () => Navigator.pop(
                                  context, _PickResult(song.id, song)),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 20, vertical: 10),
                                color: isCurrent
                                    ? ColorTokens.selectionBackground
                                    : null,
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(song.title,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                  fontSize: 13,
                                                  color: ColorTokens
                                                      .textPrimary)),
                                          const SizedBox(height: 2),
                                          Text(
                                            '${song.artist ?? ''} · ${song.album ?? ''}',
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                                fontSize: 11,
                                                color: ColorTokens
                                                    .textSecondary),
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (score != null) ...[
                                      const SizedBox(width: 12),
                                      Text(
                                        '${(score * 100).toStringAsFixed(0)}%',
                                        style: const TextStyle(
                                            fontSize: 11,
                                            color: ColorTokens.textSecondary),
                                      ),
                                    ],
                                    if (isCurrent) ...[
                                      const SizedBox(width: 8),
                                      const Icon(Icons.check,
                                          size: 14, color: ColorTokens.accent),
                                    ],
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton.icon(
                    onPressed: () =>
                        Navigator.pop(context, const _PickResult(null)),
                    icon: const Icon(Icons.block, size: 14),
                    label: const Text('Skip this track'),
                    style: TextButton.styleFrom(
                        foregroundColor: ColorTokens.textSecondary),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Done ──────────────────────────────────────────────────────────────────────

class _DoneView extends ConsumerWidget {
  const _DoneView({
    required this.playlistName,
    required this.importedCount,
    required this.skippedCount,
  });
  final String playlistName;
  final int importedCount;
  final int skippedCount;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.check_circle,
              size: 56, color: Colors.greenAccent),
          const SizedBox(height: 16),
          Text(
            'Created "$playlistName"',
            style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: ColorTokens.textPrimary),
          ),
          const SizedBox(height: 4),
          Text(
            '$importedCount imported · $skippedCount skipped',
            style: const TextStyle(
                fontSize: 12, color: ColorTokens.textSecondary),
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              FilledButton(
                onPressed: () {
                  ref.read(spotifyImportProvider.notifier).reset();
                  ref.read(selectedSectionProvider.notifier).state =
                      SidebarSection.playlists;
                },
                style: FilledButton.styleFrom(
                    backgroundColor: ColorTokens.accent),
                child: const Text('Go to playlists'),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: () =>
                    ref.read(spotifyImportProvider.notifier).reset(),
                child: const Text('Import another'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Error ─────────────────────────────────────────────────────────────────────

class _ErrorView extends ConsumerWidget {
  const _ErrorView({required this.message});
  final String message;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline,
              size: 48, color: Colors.redAccent),
          const SizedBox(height: 16),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 13, color: ColorTokens.textPrimary),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () =>
                ref.read(spotifyImportProvider.notifier).reset(),
            style: FilledButton.styleFrom(backgroundColor: ColorTokens.accent),
            child: const Text('Start over'),
          ),
        ],
      ),
    );
  }
}
