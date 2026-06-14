import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../application/lidarr/lidarr_notifier.dart';
import '../../../application/library/sidebar_state.dart';
import '../../../application/providers/providers.dart';
import '../../../application/spotify_import/song_matcher.dart';
import '../../../application/spotify_import/spotify_import_notifier.dart';
import '../../../application/spotify_import/spotify_import_state.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/color_tokens.dart';
import '../../../domain/models/lidarr_models.dart';
import '../../../domain/models/song.dart';
import '../../../domain/models/spotify_track.dart';

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
          'Import from a playlist',
          style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: ColorTokens.textPrimary),
        ),
        const SizedBox(height: 8),
        const Text(
          'Paste a public Spotify or Tidal playlist link. Dapper scrapes the '
          'track list and matches each song against your Navidrome library — '
          'you can fix any misses before the playlist is created.',
          style: TextStyle(fontSize: 12, color: ColorTokens.textSecondary),
        ),
        const SizedBox(height: 24),
        TextField(
          controller: _ctrl,
          autofocus: true,
          style: const TextStyle(fontSize: 13, color: ColorTokens.textPrimary),
          decoration: InputDecoration(
            hintText: 'open.spotify.com/playlist/… or tidal.com/playlist/…',
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
                  'Only public playlists work. Spotify caps embedded '
                  'playlists at the first ~100 tracks; Tidal returns the '
                  'full list. The importer warns you if it sees a truncated '
                  'list.',
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

  Future<void> _openLidarr(BuildContext context, SpotifyTrack track) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _LidarrLookupDialog(track: track),
    );
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
                children: [
                  TextButton.icon(
                    onPressed: () =>
                        Navigator.pop(context, const _PickResult(null)),
                    icon: const Icon(Icons.block, size: 14),
                    label: const Text('Skip'),
                    style: TextButton.styleFrom(
                        foregroundColor: ColorTokens.textSecondary),
                  ),
                  const SizedBox(width: 4),
                  Consumer(builder: (context, ref, _) {
                    final lidarrReady =
                        ref.watch(lidarrClientProvider) != null;
                    return TextButton.icon(
                      onPressed: lidarrReady
                          ? () => _openLidarr(context, widget.match.source)
                          : null,
                      icon: const Icon(Icons.cloud_download_outlined, size: 14),
                      label: const Text('Find on Lidarr'),
                      style: TextButton.styleFrom(
                          foregroundColor: ColorTokens.accent),
                    );
                  }),
                  const Spacer(),
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

// ── Lidarr lookup dialog ──────────────────────────────────────────────────────

class _LidarrLookupDialog extends ConsumerStatefulWidget {
  const _LidarrLookupDialog({required this.track});
  final SpotifyTrack track;

  @override
  ConsumerState<_LidarrLookupDialog> createState() =>
      _LidarrLookupDialogState();
}

enum _LidarrLookupMode { artist, album }

class _LidarrLookupDialogState extends ConsumerState<_LidarrLookupDialog> {
  late final TextEditingController _ctrl;
  Timer? _debounce;
  _LidarrLookupMode _mode = _LidarrLookupMode.artist;

  List<LidarrArtist>? _artistResults;
  List<LidarrAlbumLookup>? _albumResults;
  bool _searching = false;

  /// Tracks which row is in the middle of a POST so the spinner shows on
  /// the right row. For artists we key on mbid, for albums on foreignAlbumId.
  String? _addingKey;

  @override
  void initState() {
    super.initState();
    final seed =
        widget.track.artist.split(RegExp(r'[,&]')).first.trim();
    _ctrl = TextEditingController(text: seed);
    if (seed.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _lookup(seed));
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _setMode(_LidarrLookupMode m) {
    if (m == _mode) return;
    final primaryArtist =
        widget.track.artist.split(RegExp(r'[,&]')).first.trim();
    // Tidal exposes the album name per track; Spotify doesn't. When it's
    // there, prefill album mode with "<artist> <album>" so the user lands
    // on relevant results immediately.
    final seed = m == _LidarrLookupMode.artist
        ? primaryArtist
        : (widget.track.album != null && widget.track.album!.isNotEmpty
            ? '$primaryArtist ${widget.track.album}'.trim()
            : primaryArtist);
    setState(() {
      _mode = m;
      _artistResults = null;
      _albumResults = null;
      _ctrl.text = seed;
    });
    _ctrl.selection = TextSelection.collapsed(offset: _ctrl.text.length);
    if (seed.isNotEmpty) _lookup(seed);
  }

  void _onChanged(String v) {
    _debounce?.cancel();
    if (v.trim().isEmpty) {
      setState(() {
        _artistResults = null;
        _albumResults = null;
        _searching = false;
      });
      return;
    }
    setState(() => _searching = true);
    _debounce =
        Timer(const Duration(milliseconds: 400), () => _lookup(v.trim()));
  }

  Future<void> _lookup(String query) async {
    final client = ref.read(lidarrClientProvider);
    if (client == null) return;
    try {
      if (_mode == _LidarrLookupMode.artist) {
        final results = await client.lookupArtists(query);
        if (!mounted) return;
        setState(() {
          _artistResults = results;
          _searching = false;
        });
      } else {
        final results = await client.lookupAlbums(query);
        if (!mounted) return;
        setState(() {
          _albumResults = results;
          _searching = false;
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _searching = false);
    }
  }

  Future<void> _addArtist(LidarrArtist a) async {
    final client = ref.read(lidarrClientProvider);
    if (client == null) return;
    final instance = ref.read(selectedLidarrInstanceProvider);
    if (instance?.defaultRootFolderId == null ||
        instance?.defaultRootFolderPath == null ||
        instance?.defaultQualityProfileId == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text(
            'Set a root folder + quality profile in Settings → Lidarr first.'),
      ));
      return;
    }
    setState(() => _addingKey = a.mbid);
    try {
      final added = await client.addArtist(
        mbid: a.mbid,
        name: a.name,
        rootFolderId: instance!.defaultRootFolderId!,
        rootFolderPath: instance.defaultRootFolderPath!,
        qualityProfileId: instance.defaultQualityProfileId!,
      );
      if (added.id > 0) {
        unawaited(client.triggerArtistSearch(added.id));
      }
      if (!mounted) return;
      ref.invalidate(lidarrArtistsProvider);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Added ${a.name} to Lidarr.'),
      ));
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      setState(() => _addingKey = null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to add: $e')),
      );
    }
  }

  /// Adds the album and either kicks off Lidarr's automatic search or
  /// opens the interactive release picker on the new album id.
  Future<void> _addAlbum(
    LidarrAlbumLookup album, {
    required bool interactive,
  }) async {
    final client = ref.read(lidarrClientProvider);
    if (client == null) return;
    final instance = ref.read(selectedLidarrInstanceProvider);
    if (instance?.defaultRootFolderPath == null ||
        instance?.defaultQualityProfileId == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text(
            'Set a root folder + quality profile in Settings → Lidarr first.'),
      ));
      return;
    }
    setState(() => _addingKey = album.foreignAlbumId);
    try {
      final newId = await client.addAlbum(
        album: album,
        rootFolderPath: instance!.defaultRootFolderPath!,
        qualityProfileId: instance.defaultQualityProfileId!,
        // Skip the automatic search when the user is going to pick a
        // release manually — otherwise Lidarr would grab something in the
        // background while the picker is still open.
        searchOnAdd: !interactive,
      );
      if (!mounted) return;
      ref.invalidate(lidarrArtistsProvider);
      setState(() => _addingKey = null);

      if (interactive && newId > 0) {
        await showDialog<void>(
          context: context,
          builder: (_) =>
              _ReleasePickerDialog(albumId: newId, albumTitle: album.title),
        );
        if (!mounted) return;
        Navigator.pop(context);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              'Added "${album.title}" to Lidarr and started search.'),
        ));
        Navigator.pop(context);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _addingKey = null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to add album: $e')),
      );
    }
  }

  Future<void> _triggerExistingAlbumSearch(LidarrAlbumLookup album) async {
    final client = ref.read(lidarrClientProvider);
    if (client == null) return;
    try {
      await client.triggerAlbumSearch(album.lidarrAlbumId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Started search for "${album.title}".'),
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Search failed: $e')),
      );
    }
  }

  Future<void> _openReleases(LidarrAlbumLookup album) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _ReleasePickerDialog(
        albumId: album.lidarrAlbumId,
        albumTitle: album.title,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lidarrByMbid = ref.watch(lidarrArtistByMbidProvider);
    return Dialog(
      backgroundColor: ColorTokens.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: SizedBox(
        width: 540,
        height: 520,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Find on Lidarr',
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: ColorTokens.textPrimary)),
                  const SizedBox(height: 4),
                  Text(
                    'Missing: ${widget.track.artist} — ${widget.track.title}',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 12, color: ColorTokens.textSecondary),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: SegmentedButton<_LidarrLookupMode>(
                segments: const [
                  ButtonSegment(
                    value: _LidarrLookupMode.artist,
                    icon: Icon(Icons.person, size: 14),
                    label: Text('Artist'),
                  ),
                  ButtonSegment(
                    value: _LidarrLookupMode.album,
                    icon: Icon(Icons.album, size: 14),
                    label: Text('Album'),
                  ),
                ],
                selected: {_mode},
                onSelectionChanged: (s) => _setMode(s.first),
                style: ButtonStyle(
                  textStyle: WidgetStateProperty.all(
                      const TextStyle(fontSize: 12)),
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: TextField(
                controller: _ctrl,
                style: const TextStyle(
                    fontSize: 13, color: ColorTokens.textPrimary),
                decoration: InputDecoration(
                  hintText: _mode == _LidarrLookupMode.artist
                      ? 'Search Lidarr for an artist…'
                      : 'Search Lidarr for an album…',
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
                onChanged: _onChanged,
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: _mode == _LidarrLookupMode.artist
                  ? _buildArtistBody(lidarrByMbid)
                  : _buildAlbumBody(),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Close'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildArtistBody(Map<String, LidarrArtist> lidarrByMbid) {
    if (_searching && _artistResults == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final results = _artistResults ?? const <LidarrArtist>[];
    if (results.isEmpty) {
      return const Center(
        child: Text('No results.',
            style: TextStyle(
                fontSize: 12, color: ColorTokens.textSecondary)),
      );
    }
    return ListView.builder(
      itemCount: results.length,
      itemBuilder: (_, i) {
        final a = results[i];
        final alreadyAdded =
            a.isInLidarr || lidarrByMbid.containsKey(a.mbid);
        final isAdding = _addingKey == a.mbid;
        return ListTile(
          dense: true,
          contentPadding: const EdgeInsets.symmetric(
              horizontal: 20, vertical: 2),
          leading: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: a.posterUrl != null
                ? CachedNetworkImage(
                    imageUrl: a.posterUrl!,
                    width: 32,
                    height: 32,
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => const _LidarrAvatar(),
                  )
                : const _LidarrAvatar(),
          ),
          title: Text(a.name,
              style: const TextStyle(
                  fontSize: 13, color: ColorTokens.textPrimary),
              overflow: TextOverflow.ellipsis),
          trailing: isAdding
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 1.5))
              : alreadyAdded
                  ? TextButton.icon(
                      onPressed: () => _openArtistDiscography(a),
                      icon: const Icon(Icons.album_outlined, size: 12),
                      label: const Text('Open'),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        minimumSize: Size.zero,
                        foregroundColor: Colors.green,
                        textStyle: const TextStyle(fontSize: 11),
                      ),
                    )
                  : TextButton(
                      onPressed: () => _addArtist(a),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        minimumSize: Size.zero,
                        foregroundColor: ColorTokens.accent,
                        textStyle: const TextStyle(fontSize: 11),
                      ),
                      child: const Text('Add'),
                    ),
        );
      },
    );
  }

  Future<void> _openArtistDiscography(LidarrArtist a) async {
    // For Lidarr-internal lookup rows the id is already set; for results
    // straight from MusicBrainz it isn't, so fall back to the locally
    // cached artist list (matched by mbid).
    var artistId = a.id;
    if (artistId == 0) {
      final byMbid = ref.read(lidarrArtistByMbidProvider);
      artistId = byMbid[a.mbid]?.id ?? 0;
    }
    if (artistId == 0) return;
    await showDialog<void>(
      context: context,
      builder: (_) => _DiscographyDialog(artistId: artistId, artistName: a.name),
    );
  }

  Widget _buildAlbumBody() {
    if (_searching && _albumResults == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final results = _albumResults ?? const <LidarrAlbumLookup>[];
    if (results.isEmpty) {
      return const Center(
        child: Text('No results.',
            style: TextStyle(
                fontSize: 12, color: ColorTokens.textSecondary)),
      );
    }
    return ListView.builder(
      itemCount: results.length,
      itemBuilder: (_, i) {
        final a = results[i];
        final isAdding = _addingKey == a.foreignAlbumId;
        final yearLabel = a.year != null ? ' · ${a.year}' : '';
        final typeLabel = a.albumType != null &&
                a.albumType != LidarrAlbumType.other
            ? ' · ${a.albumType!.label.replaceAll('s', '')}'
            : '';
        return ListTile(
          dense: true,
          contentPadding: const EdgeInsets.symmetric(
              horizontal: 20, vertical: 4),
          leading: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: a.coverUrl != null
                ? CachedNetworkImage(
                    imageUrl: a.coverUrl!,
                    width: 36,
                    height: 36,
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => const _LidarrAlbumAvatar(),
                  )
                : const _LidarrAlbumAvatar(),
          ),
          title: Text(a.title,
              style: const TextStyle(
                  fontSize: 13, color: ColorTokens.textPrimary),
              overflow: TextOverflow.ellipsis),
          subtitle: Text('${a.artistName}$yearLabel$typeLabel',
              style: const TextStyle(
                  fontSize: 11, color: ColorTokens.textSecondary),
              overflow: TextOverflow.ellipsis),
          trailing: isAdding
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 1.5))
              : a.isInLidarr
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'Auto search',
                          icon: const Icon(Icons.search,
                              size: 16, color: ColorTokens.textSecondary),
                          onPressed: () => _triggerExistingAlbumSearch(a),
                        ),
                        IconButton(
                          tooltip: 'Pick a release',
                          icon: const Icon(Icons.manage_search,
                              size: 16, color: ColorTokens.textSecondary),
                          onPressed: () => _openReleases(a),
                        ),
                      ],
                    )
                  : _AlbumActions(
                      album: a,
                      onAddAndSearch: () => _addAlbum(a, interactive: false),
                      onAddAndPick: () => _addAlbum(a, interactive: true),
                      onTriggerSearch: () => _triggerExistingAlbumSearch(a),
                      onOpenReleases: () => _openReleases(a),
                    ),
        );
      },
    );
  }
}

class _AlbumActions extends StatelessWidget {
  const _AlbumActions({
    required this.album,
    required this.onAddAndSearch,
    required this.onAddAndPick,
    required this.onTriggerSearch,
    required this.onOpenReleases,
  });

  final LidarrAlbumLookup album;
  final VoidCallback onAddAndSearch;
  final VoidCallback onAddAndPick;
  final VoidCallback onTriggerSearch;
  final VoidCallback onOpenReleases;

  @override
  Widget build(BuildContext context) {
    final inLidarr = album.isInLidarr;
    return PopupMenuButton<String>(
      tooltip: 'Options',
      icon: Icon(
        inLidarr ? Icons.check_circle : Icons.add_circle_outline,
        size: 18,
        color: inLidarr ? Colors.green : ColorTokens.accent,
      ),
      color: ColorTokens.surface,
      onSelected: (v) {
        switch (v) {
          case 'add_search':
            onAddAndSearch();
          case 'add_pick':
            onAddAndPick();
          case 'search':
            onTriggerSearch();
          case 'pick':
            onOpenReleases();
        }
      },
      itemBuilder: (_) => inLidarr
          ? const [
              PopupMenuItem(
                value: 'search',
                child: _MenuRow(
                    icon: Icons.search, label: 'Search for releases'),
              ),
              PopupMenuItem(
                value: 'pick',
                child: _MenuRow(
                    icon: Icons.manage_search,
                    label: 'Pick a release manually…'),
              ),
            ]
          : const [
              PopupMenuItem(
                value: 'add_search',
                child: _MenuRow(
                    icon: Icons.download, label: 'Add & auto search'),
              ),
              PopupMenuItem(
                value: 'add_pick',
                child: _MenuRow(
                    icon: Icons.manage_search,
                    label: 'Add & pick a release…'),
              ),
            ],
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 14, color: ColorTokens.textPrimary),
        const SizedBox(width: 8),
        Text(label,
            style: const TextStyle(
                fontSize: 12, color: ColorTokens.textPrimary)),
      ],
    );
  }
}

class _LidarrAlbumAvatar extends StatelessWidget {
  const _LidarrAlbumAvatar();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: ColorTokens.surfaceVariant,
        borderRadius: BorderRadius.circular(4),
      ),
      child: const Icon(Icons.album,
          size: 18, color: ColorTokens.textSecondary),
    );
  }
}

class _LidarrAvatar extends StatelessWidget {
  const _LidarrAvatar();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 32,
      height: 32,
      decoration: const BoxDecoration(
        color: ColorTokens.surfaceVariant,
        shape: BoxShape.circle,
      ),
      child: const Icon(Icons.person,
          size: 16, color: ColorTokens.textSecondary),
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

// ── Release picker dialog ─────────────────────────────────────────────────────

/// Interactive release picker: lists every indexer hit for [albumId] and
/// lets the user grab a specific one. Mirrors the "Interactive search"
/// sheet on the Lidarr page, but rendered as a centered dialog because the
/// Spotify-import flow is already inside a dialog stack.
class _ReleasePickerDialog extends ConsumerStatefulWidget {
  const _ReleasePickerDialog({
    required this.albumId,
    required this.albumTitle,
  });

  final int albumId;
  final String albumTitle;

  @override
  ConsumerState<_ReleasePickerDialog> createState() =>
      _ReleasePickerDialogState();
}

class _ReleasePickerDialogState extends ConsumerState<_ReleasePickerDialog> {
  List<LidarrRelease>? _releases;
  bool _loading = true;
  String? _error;
  String? _grabbingGuid;
  final Set<String> _grabbedGuids = {};

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    final client = ref.read(lidarrClientProvider);
    if (client == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final releases = await client.searchReleases(widget.albumId);
      // Approved + most-seeded first so the obvious pick floats up.
      releases.sort((a, b) {
        if (a.rejected != b.rejected) return a.rejected ? 1 : -1;
        return (b.seeders ?? 0).compareTo(a.seeders ?? 0);
      });
      if (!mounted) return;
      setState(() {
        _releases = releases;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _grab(LidarrRelease r) async {
    final client = ref.read(lidarrClientProvider);
    if (client == null) return;
    setState(() => _grabbingGuid = r.guid);
    try {
      await client.grabRelease(r.raw);
      if (!mounted) return;
      setState(() {
        _grabbingGuid = null;
        _grabbedGuids.add(r.guid);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _grabbingGuid = null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Grab failed: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: ColorTokens.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: SizedBox(
        width: 620,
        height: 560,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 12, 8),
              child: Row(
                children: [
                  const Icon(Icons.manage_search,
                      size: 18, color: ColorTokens.textSecondary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(widget.albumTitle,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: ColorTokens.textPrimary)),
                  ),
                  if (!_loading)
                    IconButton(
                      tooltip: 'Refresh',
                      icon: const Icon(Icons.refresh,
                          size: 16, color: ColorTokens.textSecondary),
                      onPressed: _fetch,
                    ),
                ],
              ),
            ),
            const Divider(height: 1, color: ColorTokens.glassBorder),
            Expanded(child: _buildBody()),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Close'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_error!,
              textAlign: TextAlign.center,
              style:
                  const TextStyle(fontSize: 12, color: Colors.redAccent)),
        ),
      );
    }
    final releases = _releases ?? const [];
    if (releases.isEmpty) {
      return const Center(
        child: Text('No releases found from indexers.',
            style: TextStyle(
                fontSize: 12, color: ColorTokens.textSecondary)),
      );
    }
    return ListView.separated(
      itemCount: releases.length,
      separatorBuilder: (_, __) =>
          const Divider(height: 1, color: ColorTokens.glassBorder),
      itemBuilder: (_, i) {
        final r = releases[i];
        final isGrabbing = _grabbingGuid == r.guid;
        final isGrabbed = _grabbedGuids.contains(r.guid);
        return ListTile(
          dense: true,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
          title: Text(r.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                color: r.rejected
                    ? ColorTokens.textSecondary
                    : ColorTokens.textPrimary,
              )),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Wrap(
              spacing: 8,
              runSpacing: 2,
              children: [
                _MetaChip(label: r.indexer),
                _MetaChip(label: r.formattedSize),
                _MetaChip(label: r.quality),
                if (r.protocol == 'torrent' && r.seeders != null)
                  _MetaChip(label: '${r.seeders}↑ ${r.leechers ?? 0}↓'),
                if (r.ageInDays > 0)
                  _MetaChip(label: '${r.ageInDays}d old'),
                if (r.rejected)
                  _MetaChip(
                    label: r.rejections.isEmpty
                        ? 'rejected'
                        : r.rejections.first,
                    color: Colors.orangeAccent,
                  ),
              ],
            ),
          ),
          trailing: isGrabbed
              ? const Icon(Icons.check_circle,
                  size: 16, color: Colors.green)
              : isGrabbing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 1.5))
                  : IconButton(
                      tooltip: r.rejected
                          ? 'Grab anyway'
                          : 'Grab this release',
                      icon: Icon(
                        Icons.download,
                        size: 18,
                        color: r.rejected
                            ? Colors.orangeAccent
                            : ColorTokens.accent,
                      ),
                      onPressed: () => _grab(r),
                    ),
        );
      },
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.label, this.color});
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: (color ?? ColorTokens.textSecondary).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          color: color ?? ColorTokens.textSecondary,
        ),
      ),
    );
  }
}

// ── Artist discography dialog ─────────────────────────────────────────────────

/// Mini Lidarr artist page rendered as a centered dialog. Lists every album
/// Lidarr already knows about for the artist, with per-album auto-search
/// and interactive-grab buttons — same actions as the full Lidarr page but
/// without leaving the Spotify import flow.
class _DiscographyDialog extends ConsumerStatefulWidget {
  const _DiscographyDialog({
    required this.artistId,
    required this.artistName,
  });

  final int artistId;
  final String artistName;

  @override
  ConsumerState<_DiscographyDialog> createState() =>
      _DiscographyDialogState();
}

class _DiscographyDialogState extends ConsumerState<_DiscographyDialog> {
  final Map<int, bool> _searching = {};
  final Set<int> _searched = {};

  Future<void> _autoSearch(int albumId) async {
    final client = ref.read(lidarrClientProvider);
    if (client == null) return;
    setState(() => _searching[albumId] = true);
    try {
      await client.triggerAlbumSearch(albumId);
      if (!mounted) return;
      setState(() {
        _searching.remove(albumId);
        _searched.add(albumId);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _searching.remove(albumId));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Search failed: $e')),
      );
    }
  }

  Future<void> _interactive(int albumId, String title) async {
    await showDialog<void>(
      context: context,
      builder: (_) =>
          _ReleasePickerDialog(albumId: albumId, albumTitle: title),
    );
  }

  @override
  Widget build(BuildContext context) {
    final albumsAsync =
        ref.watch(lidarrAlbumsByArtistProvider(widget.artistId));

    return Dialog(
      backgroundColor: ColorTokens.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: SizedBox(
        width: 580,
        height: 560,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 12, 8),
              child: Row(
                children: [
                  const Icon(Icons.person,
                      size: 18, color: ColorTokens.textSecondary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(widget.artistName,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: ColorTokens.textPrimary)),
                  ),
                  IconButton(
                    tooltip: 'Refresh',
                    icon: const Icon(Icons.refresh,
                        size: 16, color: ColorTokens.textSecondary),
                    onPressed: () => ref.invalidate(
                        lidarrAlbumsByArtistProvider(widget.artistId)),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: ColorTokens.glassBorder),
            Expanded(
              child: albumsAsync.when(
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text('Could not load discography: $e',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontSize: 12, color: Colors.redAccent)),
                  ),
                ),
                data: (albums) => _buildList(albums),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Close'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildList(List<LidarrAlbum> albums) {
    if (albums.isEmpty) {
      return const Center(
        child: Text('No albums known for this artist yet.',
            style: TextStyle(
                fontSize: 12, color: ColorTokens.textSecondary)),
      );
    }
    // Group by type, missing-first within group so the user lands on the
    // albums they probably want to grab without scrolling.
    final groups = <LidarrAlbumType, List<LidarrAlbum>>{};
    for (final t in LidarrAlbumType.values) {
      final g = albums.where((a) => a.albumType == t).toList()
        ..sort((a, b) {
          if (a.hasFile != b.hasFile) return a.hasFile ? 1 : -1;
          return (b.year ?? 0).compareTo(a.year ?? 0);
        });
      if (g.isNotEmpty) groups[t] = g;
    }
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        for (final entry in groups.entries) ...[
          Padding(
            padding:
                const EdgeInsets.fromLTRB(20, 12, 20, 6),
            child: Text(
              '${entry.key.label} · ${entry.value.length}',
              style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: ColorTokens.textSecondary,
                  letterSpacing: 0.5),
            ),
          ),
          for (final album in entry.value)
            _DiscographyRow(
              album: album,
              isSearching: _searching[album.id] == true,
              isSearched: _searched.contains(album.id),
              onAutoSearch: () => _autoSearch(album.id),
              onInteractiveSearch: () =>
                  _interactive(album.id, album.title),
            ),
        ],
      ],
    );
  }
}

class _DiscographyRow extends StatelessWidget {
  const _DiscographyRow({
    required this.album,
    required this.isSearching,
    required this.isSearched,
    required this.onAutoSearch,
    required this.onInteractiveSearch,
  });

  final LidarrAlbum album;
  final bool isSearching;
  final bool isSearched;
  final VoidCallback onAutoSearch;
  final VoidCallback onInteractiveSearch;

  @override
  Widget build(BuildContext context) {
    final statusColor = album.hasFile ? Colors.green : Colors.orange;
    final statusLabel = album.hasFile ? 'Downloaded' : 'Missing';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: album.coverUrl != null
                ? CachedNetworkImage(
                    imageUrl: album.coverUrl!,
                    width: 40,
                    height: 40,
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => const _LidarrAlbumAvatar(),
                  )
                : const _LidarrAlbumAvatar(),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(album.title,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 13, color: ColorTokens.textPrimary)),
                const SizedBox(height: 2),
                Row(
                  children: [
                    if (album.year != null) ...[
                      Text('${album.year}',
                          style: const TextStyle(
                              fontSize: 11,
                              color: ColorTokens.textSecondary)),
                      const SizedBox(width: 6),
                    ],
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(statusLabel,
                          style: TextStyle(
                              fontSize: 10, color: statusColor)),
                    ),
                    if (!album.monitored) ...[
                      const SizedBox(width: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: ColorTokens.textSecondary
                              .withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text('Unmonitored',
                            style: TextStyle(
                                fontSize: 10,
                                color: ColorTokens.textSecondary)),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          if (!album.hasFile)
            SizedBox(
              width: 32,
              height: 32,
              child: isSearched
                  ? const Center(
                      child: Icon(Icons.check_circle_outline,
                          size: 16, color: Colors.green),
                    )
                  : isSearching
                      ? const Padding(
                          padding: EdgeInsets.all(8),
                          child: CircularProgressIndicator(strokeWidth: 1.5),
                        )
                      : IconButton(
                          tooltip: 'Auto search',
                          padding: EdgeInsets.zero,
                          icon: const Icon(Icons.search,
                              size: 16, color: ColorTokens.textSecondary),
                          onPressed: onAutoSearch,
                        ),
            ),
          SizedBox(
            width: 32,
            height: 32,
            child: IconButton(
              tooltip: 'Pick a release',
              padding: EdgeInsets.zero,
              icon: const Icon(Icons.manage_search,
                  size: 16, color: ColorTokens.textSecondary),
              onPressed: onInteractiveSearch,
            ),
          ),
        ],
      ),
    );
  }
}
