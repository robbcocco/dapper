import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/theme/color_tokens.dart';
import '../../../data/datasources/remote/musicbrainz_client.dart';
import '../../../domain/models/album.dart';
import '../../../domain/models/musicbrainz_result.dart';
import '../../widgets/cover_art_image.dart';

class AlbumInfoDialog extends StatelessWidget {
  const AlbumInfoDialog({super.key, required this.album});

  final Album album;

  static Future<void> show(BuildContext context, Album album) async {
    await showDialog<void>(
      context: context,
      builder: (_) => AlbumInfoDialog(album: album),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: ColorTokens.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 780, maxHeight: 580),
        child: _AlbumInfoContent(album: album),
      ),
    );
  }
}

class _AlbumInfoContent extends StatefulWidget {
  const _AlbumInfoContent({required this.album});

  final Album album;

  @override
  State<_AlbumInfoContent> createState() => _AlbumInfoContentState();
}

class _AlbumInfoContentState extends State<_AlbumInfoContent> {
  final _mb = MusicBrainzClient();
  late final TextEditingController _searchCtrl;

  List<MbReleaseGroup> _results = [];
  bool _searching = false;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _searchCtrl = TextEditingController(
      text: [
        widget.album.name,
        if (widget.album.artist != null) widget.album.artist!,
      ].join(' '),
    );
    _search();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onSearchChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), _search);
  }

  Future<void> _search() async {
    if (_searchCtrl.text.trim().isEmpty) return;
    setState(() {
      _searching = true;
      _results = [];
    });
    final results = await _mb.searchByText(_searchCtrl.text.trim());
    if (!mounted) return;
    setState(() {
      _results = results;
      _searching = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final album = widget.album;

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Title row ──────────────────────────────────────────────────────
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Get Info',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: ColorTokens.textPrimary,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 16),
                color: ColorTokens.textSecondary,
                onPressed: () => Navigator.of(context).pop(),
                padding: EdgeInsets.zero,
                constraints:
                    const BoxConstraints(minWidth: 24, minHeight: 24),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // ── Main content: info panel + MusicBrainz ─────────────────────────
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Left: current metadata
                _InfoPanel(album: album),
                const SizedBox(width: 20),
                const VerticalDivider(
                    width: 1, color: ColorTokens.glassBorder),
                const SizedBox(width: 20),

                // Right: MusicBrainz search
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Fix via MusicBrainz',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: ColorTokens.textSecondary
                              .withValues(alpha: 0.7),
                          letterSpacing: 0.6,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _searchCtrl,
                        style: const TextStyle(
                            fontSize: 13, color: ColorTokens.textPrimary),
                        decoration: InputDecoration(
                          hintText: 'Search MusicBrainz…',
                          hintStyle: const TextStyle(
                              fontSize: 12,
                              color: ColorTokens.textSecondary),
                          prefixIcon: _searching
                              ? const Padding(
                                  padding: EdgeInsets.all(10),
                                  child: SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 1.5),
                                  ),
                                )
                              : const Icon(Icons.search,
                                  size: 16,
                                  color: ColorTokens.textSecondary),
                          prefixIconConstraints:
                              const BoxConstraints(minWidth: 36, minHeight: 36),
                          filled: true,
                          fillColor: ColorTokens.surfaceVariant,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide.none,
                          ),
                        ),
                        onChanged: _onSearchChanged,
                        onSubmitted: (_) => _search(),
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: _results.isEmpty && !_searching
                            ? const Center(
                                child: Text('No results',
                                    style: TextStyle(
                                        color: ColorTokens.textSecondary,
                                        fontSize: 13)),
                              )
                            : GridView.builder(
                                gridDelegate:
                                    const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 3,
                                  crossAxisSpacing: 10,
                                  mainAxisSpacing: 10,
                                  childAspectRatio: 0.72,
                                ),
                                itemCount: _results.length,
                                itemBuilder: (_, i) => _MbResultCard(
                                  result: _results[i],
                                ),
                              ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // ── Bottom actions ─────────────────────────────────────────────────
          Row(
            children: [
              const Icon(Icons.info_outline,
                  size: 12, color: ColorTokens.textSecondary),
              const SizedBox(width: 6),
              const Expanded(
                child: Text(
                  'Navidrome does not yet support metadata editing via its API. '
                  'Use MusicBrainz results as a reference.',
                  style: TextStyle(
                      fontSize: 10, color: ColorTokens.textSecondary),
                ),
              ),
              const SizedBox(width: 12),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Close',
                    style: TextStyle(color: ColorTokens.textSecondary)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Left info panel ───────────────────────────────────────────────────────────

class _InfoPanel extends StatelessWidget {
  const _InfoPanel({required this.album});
  final Album album;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 180,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: CoverArtImage(
              coverArtId: album.coverArtId,
              size: 360,
              borderRadius: 8,
            ),
          ),
          const SizedBox(height: 14),
          _MetaRow(label: 'Title', value: album.name),
          if (album.artist != null) _MetaRow(label: 'Artist', value: album.artist!),
          if (album.year != null) _MetaRow(label: 'Year', value: '${album.year}'),
          if (album.genre != null && album.genre!.isNotEmpty)
            _MetaRow(label: 'Genre', value: album.genre!),
          _MetaRow(label: 'Songs', value: '${album.songCount}'),
          if (album.duration > 0)
            _MetaRow(label: 'Duration', value: _fmtDuration(album.duration)),
        ],
      ),
    );
  }

  static String _fmtDuration(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    if (h > 0) return '${h}h ${m}m';
    return '${m}m';
  }
}

class _MetaRow extends StatelessWidget {
  const _MetaRow({required this.label, required this.value});
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
            width: 56,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: ColorTokens.textSecondary,
                letterSpacing: 0.4,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                  fontSize: 11, color: ColorTokens.textPrimary),
              overflow: TextOverflow.ellipsis,
              maxLines: 2,
            ),
          ),
        ],
      ),
    );
  }
}

// ── MusicBrainz result card ───────────────────────────────────────────────────

class _MbResultCard extends StatelessWidget {
  const _MbResultCard({required this.result});

  final MbReleaseGroup result;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: ColorTokens.glassBorder),
        color: ColorTokens.surfaceVariant,
      ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: ClipRRect(
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(7)),
                child: Image.network(
                  result.coverArtThumbUrl,
                  fit: BoxFit.cover,
                  width: double.infinity,
                  errorBuilder: (_, __, ___) => const ColoredBox(
                    color: ColorTokens.surfaceVariant,
                    child: Center(
                      child: Icon(Icons.image_not_supported_outlined,
                          size: 24,
                          color: ColorTokens.textSecondary),
                    ),
                  ),
                  loadingBuilder: (_, child, progress) => progress == null
                      ? child
                      : const Center(
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child:
                                CircularProgressIndicator(strokeWidth: 1.5),
                          ),
                        ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    result.title,
                    style: const TextStyle(
                        fontSize: 11, color: ColorTokens.textPrimary),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (result.year != null)
                    Text(
                      result.year!,
                      style: const TextStyle(
                          fontSize: 10,
                          color: ColorTokens.textSecondary),
                    ),
                ],
              ),
            ),
          ],
        ),
    );
  }
}
