import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/library/library_notifier.dart';
import '../../application/providers/providers.dart';
import '../../core/theme/color_tokens.dart';
import '../../domain/models/song.dart';

Future<void> showSongMetadataDialog(
  BuildContext context,
  WidgetRef ref,
  Song song,
) {
  return showDialog(
    context: context,
    builder: (_) => _SongMetadataDialog(song: song, ref: ref),
  );
}

class _SongMetadataDialog extends StatefulWidget {
  const _SongMetadataDialog({required this.song, required this.ref});
  final Song song;
  final WidgetRef ref;

  @override
  State<_SongMetadataDialog> createState() => _SongMetadataDialogState();
}

class _SongMetadataDialogState extends State<_SongMetadataDialog> {
  late final TextEditingController _title;
  late final TextEditingController _artist;
  late final TextEditingController _album;
  late final TextEditingController _albumArtist;
  late final TextEditingController _genre;
  late final TextEditingController _year;
  late final TextEditingController _track;
  late final TextEditingController _disc;

  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final s = widget.song;
    _title = TextEditingController(text: s.title);
    _artist = TextEditingController(text: s.artist ?? '');
    _album = TextEditingController(text: s.album ?? '');
    _albumArtist = TextEditingController(text: s.albumArtist ?? '');
    _genre = TextEditingController(text: s.genre ?? '');
    _year = TextEditingController(
        text: s.year != null ? '${s.year}' : '');
    _track = TextEditingController(
        text: s.track != null ? '${s.track}' : '');
    _disc = TextEditingController(
        text: s.discNumber != null ? '${s.discNumber}' : '');
  }

  @override
  void dispose() {
    _title.dispose();
    _artist.dispose();
    _album.dispose();
    _albumArtist.dispose();
    _genre.dispose();
    _year.dispose();
    _track.dispose();
    _disc.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final client = widget.ref.read(navidromeClientProvider);
    if (client == null) {
      setState(() => _error = 'Not connected to server');
      return;
    }

    final fields = <String, dynamic>{
      'title': _title.text.trim(),
      if (_artist.text.trim().isNotEmpty) 'artist': _artist.text.trim(),
      if (_album.text.trim().isNotEmpty) 'album': _album.text.trim(),
      if (_albumArtist.text.trim().isNotEmpty)
        'albumArtist': _albumArtist.text.trim(),
      if (_genre.text.trim().isNotEmpty) 'genre': _genre.text.trim(),
      if (_year.text.trim().isNotEmpty)
        'year': int.tryParse(_year.text.trim()),
      if (_track.text.trim().isNotEmpty)
        'trackNumber': int.tryParse(_track.text.trim()),
      if (_disc.text.trim().isNotEmpty)
        'discNumber': int.tryParse(_disc.text.trim()),
    };

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      await client.updateSong(widget.song.id, fields);
      // Invalidate album and playlist caches so the UI reflects changes.
      if (widget.song.albumId != null) {
        widget.ref.invalidate(albumProvider(widget.song.albumId!));
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() {
        _saving = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: ColorTokens.surface,
      title: const Text('Song Info',
          style: TextStyle(color: ColorTokens.textPrimary)),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _Field('Title', _title, autofocus: true),
              _Field('Artist', _artist),
              _Field('Album', _album),
              _Field('Album Artist', _albumArtist),
              _Field('Genre', _genre),
              Row(
                children: [
                  Expanded(child: _Field('Year', _year, numeric: true)),
                  const SizedBox(width: 8),
                  Expanded(child: _Field('Track', _track, numeric: true)),
                  const SizedBox(width: 8),
                  Expanded(child: _Field('Disc', _disc, numeric: true)),
                ],
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!,
                    style: const TextStyle(
                        fontSize: 11, color: Colors.redAccent)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          style: FilledButton.styleFrom(backgroundColor: ColorTokens.accent),
          child: _saving
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : const Text('Save'),
        ),
      ],
    );
  }
}

class _Field extends StatelessWidget {
  const _Field(this.label, this.controller,
      {this.autofocus = false, this.numeric = false});

  final String label;
  final TextEditingController controller;
  final bool autofocus;
  final bool numeric;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextField(
        controller: controller,
        autofocus: autofocus,
        keyboardType: numeric ? TextInputType.number : TextInputType.text,
        style: const TextStyle(fontSize: 13, color: ColorTokens.textPrimary),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(
              fontSize: 11, color: ColorTokens.textSecondary),
          filled: true,
          fillColor: ColorTokens.surfaceVariant,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: BorderSide.none,
          ),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          isDense: true,
        ),
      ),
    );
  }
}
