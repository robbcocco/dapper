import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../application/device/device_settings_notifier.dart';
import '../../../application/transfer/transfer_path_resolver.dart';
import '../../../core/extensions/string_extensions.dart';
import '../../../core/theme/color_tokens.dart';
import '../../../domain/models/device_settings.dart';
import '../../../domain/models/song.dart';
import 'device_folder_picker_dialog.dart';

class DeviceSettingsDialog extends ConsumerStatefulWidget {
  const DeviceSettingsDialog({super.key, required this.devicePath});

  final String devicePath;

  static Future<void> show(BuildContext context, String devicePath) {
    return showDialog(
      context: context,
      builder: (_) => DeviceSettingsDialog(devicePath: devicePath),
    );
  }

  @override
  ConsumerState<DeviceSettingsDialog> createState() =>
      _DeviceSettingsDialogState();
}

class _DeviceSettingsDialogState extends ConsumerState<DeviceSettingsDialog> {
  // The bitrate dropdown's options. Null = unlimited (server decides).
  static const _bitRateChoices = <int?>[null, 96, 128, 192, 256, 320];

  late TextEditingController _rootCtrl;
  late TextEditingController _playlistCtrl;
  late TextEditingController _customTemplateCtrl;
  late TextEditingController _customFolderCtrl;
  late FolderStructure _folderStructure;
  late FilenameFormat _filenameFormat;
  late bool _includeYear;
  late bool _overwriteExisting;
  late TranscodeFormat _transcodeFormat;
  late int? _transcodeMaxBitRate;
  late bool _useZipDownload;

  @override
  void initState() {
    super.initState();
    final settings = ref.read(deviceSettingsProvider(widget.devicePath));
    _rootCtrl = TextEditingController(text: settings.musicRootFolder);
    _playlistCtrl = TextEditingController(text: settings.playlistFolder);
    _folderStructure = settings.folderStructure;
    _filenameFormat = settings.filenameFormat;
    _includeYear = settings.includeYear;
    _overwriteExisting = settings.overwriteExisting;
    _transcodeFormat = settings.transcodeFormat;
    _transcodeMaxBitRate = settings.transcodeMaxBitRate;
    _useZipDownload = settings.useZipDownload;
    _customTemplateCtrl =
        TextEditingController(text: settings.customFilenameTemplate);
    _customFolderCtrl =
        TextEditingController(text: settings.customFolderTemplate);
  }

  @override
  void dispose() {
    _rootCtrl.dispose();
    _playlistCtrl.dispose();
    _customTemplateCtrl.dispose();
    _customFolderCtrl.dispose();
    super.dispose();
  }

  void _save() {
    final rootError = validateMusicRootPath(_rootCtrl.text);
    if (rootError != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Music root: $rootError')),
      );
      return;
    }
    if (_filenameFormat == FilenameFormat.custom) {
      final tplError = validateFilenameTemplate(_customTemplateCtrl.text);
      if (tplError != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Filename template: $tplError')),
        );
        return;
      }
    }
    if (_folderStructure == FolderStructure.custom) {
      final tplError = validateFolderTemplate(_customFolderCtrl.text);
      if (tplError != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Folder template: $tplError')),
        );
        return;
      }
    }
    ref.read(deviceSettingsProvider(widget.devicePath).notifier).save(
          DeviceSettings(
            devicePath: widget.devicePath,
            musicRootFolder: _rootCtrl.text.trim(),
            playlistFolder: _playlistCtrl.text.trim(),
            folderStructure: _folderStructure,
            filenameFormat: _filenameFormat,
            includeYear: _includeYear,
            overwriteExisting: _overwriteExisting,
            transcodeFormat: _transcodeFormat,
            // Bit-rate is only meaningful when actually transcoding.
            transcodeMaxBitRate: _transcodeFormat == TranscodeFormat.original
                ? null
                : _transcodeMaxBitRate,
            // Bulk-zip mode is only honoured for original-format transfers;
            // persist the user's choice regardless so they don't lose it on a
            // round-trip through transcoded mode.
            useZipDownload: _useZipDownload,
            customFilenameTemplate: _customTemplateCtrl.text.trim(),
            customFolderTemplate: _customFolderCtrl.text.trim(),
          ),
        );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: ColorTokens.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints:
            const BoxConstraints(maxWidth: 480, maxHeight: 720),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
              const Text(
                'Device Settings',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: ColorTokens.textPrimary,
                ),
              ),
              const SizedBox(height: 24),

              _SectionLabel('FOLDERS'),
              const SizedBox(height: 8),
              _MusicRootField(
                controller: _rootCtrl,
                devicePath: widget.devicePath,
                onChanged: () => setState(() {}),
              ),
              const SizedBox(height: 12),
              _SettingRow(
                label: 'Playlist folder',
                hint: 'Relative to device root (not music root)',
                child: _TextField(
                  controller: _playlistCtrl,
                  hint: 'e.g. Playlists',
                ),
              ),

              const SizedBox(height: 20),
              _SectionLabel('FOLDER STRUCTURE'),
              const SizedBox(height: 8),
              RadioGroup<FolderStructure>(
                groupValue: _folderStructure,
                onChanged: (v) => setState(() => _folderStructure = v!),
                child: Column(
                  children: [
                    (FolderStructure.artistAlbum, 'Artist / Album / track'),
                    (FolderStructure.artistAlbumYear, 'Artist / Year - Album / track'),
                    (FolderStructure.artistOnly, 'Artist / track'),
                    (FolderStructure.flat, 'Flat (all files in music root)'),
                    (FolderStructure.custom, 'Custom template'),
                  ].map(
                    (entry) => RadioListTile<FolderStructure>(
                      value: entry.$1,
                      title: Text(entry.$2,
                          style: const TextStyle(
                              fontSize: 13, color: ColorTokens.textPrimary)),
                      dense: true,
                      activeColor: ColorTokens.accent,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ).toList(),
                ),
              ),
              if (_folderStructure == FolderStructure.custom) ...[
                const SizedBox(height: 4),
                _CustomFolderField(
                  controller: _customFolderCtrl,
                  onChanged: () => setState(() {}),
                ),
              ],

              const SizedBox(height: 20),
              _SectionLabel('FILENAME FORMAT'),
              const SizedBox(height: 8),
              RadioGroup<FilenameFormat>(
                groupValue: _filenameFormat,
                onChanged: (v) => setState(() => _filenameFormat = v!),
                child: Column(
                  children: [
                    (FilenameFormat.discTrack, '1-01 - Title  (disc · track · title)'),
                    (FilenameFormat.track,     '01 Title  (track · title)'),
                    (FilenameFormat.none,      'Title  (no prefix)'),
                    (FilenameFormat.custom,    'Custom template'),
                  ].map(
                    (entry) => RadioListTile<FilenameFormat>(
                      value: entry.$1,
                      title: Text(entry.$2,
                          style: const TextStyle(
                              fontSize: 13, color: ColorTokens.textPrimary)),
                      dense: true,
                      activeColor: ColorTokens.accent,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ).toList(),
                ),
              ),
              if (_filenameFormat == FilenameFormat.custom) ...[
                const SizedBox(height: 4),
                _CustomTemplateField(
                  controller: _customTemplateCtrl,
                  onChanged: () => setState(() {}),
                ),
              ],

              const SizedBox(height: 20),
              _SectionLabel('TRANSCODING'),
              const SizedBox(height: 8),
              _SettingRow(
                label: 'Format',
                hint: 'Re-encode on the server before transfer',
                child: DropdownButtonFormField<TranscodeFormat>(
                  initialValue: _transcodeFormat,
                  isDense: true,
                  decoration: const InputDecoration(
                    filled: true,
                    fillColor: ColorTokens.surfaceVariant,
                    border: OutlineInputBorder(borderSide: BorderSide.none),
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  ),
                  dropdownColor: ColorTokens.surface,
                  style: const TextStyle(
                      fontSize: 13, color: ColorTokens.textPrimary),
                  items: TranscodeFormat.values
                      .map((f) => DropdownMenuItem(
                            value: f,
                            child: Text(f.label),
                          ))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setState(() => _transcodeFormat = v);
                  },
                ),
              ),
              if (_transcodeFormat != TranscodeFormat.original) ...[
                const SizedBox(height: 12),
                _SettingRow(
                  label: 'Max bitrate',
                  hint: 'Server caps re-encoded streams',
                  child: DropdownButtonFormField<int?>(
                    initialValue: _bitRateChoices.contains(_transcodeMaxBitRate)
                        ? _transcodeMaxBitRate
                        : null,
                    isDense: true,
                    decoration: const InputDecoration(
                      filled: true,
                      fillColor: ColorTokens.surfaceVariant,
                      border: OutlineInputBorder(borderSide: BorderSide.none),
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    ),
                    dropdownColor: ColorTokens.surface,
                    style: const TextStyle(
                        fontSize: 13, color: ColorTokens.textPrimary),
                    items: _bitRateChoices
                        .map((br) => DropdownMenuItem<int?>(
                              value: br,
                              child: Text(br == null ? 'Unlimited' : '$br kbps'),
                            ))
                        .toList(),
                    onChanged: (v) =>
                        setState(() => _transcodeMaxBitRate = v),
                  ),
                ),
              ],

              const SizedBox(height: 20),
              _SectionLabel('FILE OPTIONS'),
              const SizedBox(height: 8),
              _Switch(
                label: 'Include year in album folder name',
                value: _includeYear,
                onChanged: (v) => setState(() => _includeYear = v),
              ),
              _Switch(
                label: 'Overwrite existing files',
                value: _overwriteExisting,
                onChanged: (v) => setState(() => _overwriteExisting = v),
              ),
              _Switch(
                label: 'Bulk album download (zip, faster)',
                value: _useZipDownload,
                onChanged: _transcodeFormat == TranscodeFormat.original
                    ? (v) => setState(() => _useZipDownload = v)
                    : (_) {},
              ),
              if (_transcodeFormat != TranscodeFormat.original)
                const Padding(
                  padding: EdgeInsets.only(left: 4, bottom: 4),
                  child: Text(
                    'Bulk zip is only available in Original format.',
                    style: TextStyle(
                        fontSize: 11, color: ColorTokens.textSecondary),
                  ),
                ),

              const SizedBox(height: 28),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel',
                        style: TextStyle(color: ColorTokens.textSecondary)),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _save,
                    style: FilledButton.styleFrom(
                        backgroundColor: ColorTokens.accent),
                    child: const Text('Save'),
                  ),
                ],
              ),
            ],
          ),
          ),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);
  final String label;

  @override
  Widget build(BuildContext context) => Text(
        label,
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: ColorTokens.textSecondary,
          letterSpacing: 0.8,
        ),
      );
}

class _SettingRow extends StatelessWidget {
  const _SettingRow(
      {required this.label, required this.child, this.hint});
  final String label;
  final String? hint;
  final Widget child;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                        fontSize: 13, color: ColorTokens.textPrimary)),
                if (hint != null)
                  Text(hint!,
                      style: const TextStyle(
                          fontSize: 11, color: ColorTokens.textSecondary)),
              ],
            ),
          ),
          const SizedBox(width: 16),
          SizedBox(width: 160, child: child),
        ],
      );
}

class _TextField extends StatelessWidget {
  const _TextField({required this.controller, this.hint});
  final TextEditingController controller;
  final String? hint;

  @override
  Widget build(BuildContext context) => TextField(
        controller: controller,
        style: const TextStyle(
            fontSize: 13, color: ColorTokens.textPrimary),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle:
              const TextStyle(color: ColorTokens.textSecondary, fontSize: 12),
          filled: true,
          fillColor: ColorTokens.surfaceVariant,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: BorderSide.none,
          ),
          isDense: true,
        ),
      );
}

class _MusicRootField extends StatelessWidget {
  const _MusicRootField({
    required this.controller,
    required this.devicePath,
    required this.onChanged,
  });

  final TextEditingController controller;
  final String devicePath;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final raw = controller.text.trim();
    final error = validateMusicRootPath(raw);
    final preview = error == null
        ? DeviceSettings(
                devicePath: devicePath, musicRootFolder: raw)
            .resolvedMusicRoot
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text('Music root path',
                      style: TextStyle(
                          fontSize: 13, color: ColorTokens.textPrimary)),
                  Text('Relative to device root. Leave empty for root.',
                      style: TextStyle(
                          fontSize: 11, color: ColorTokens.textSecondary)),
                ],
              ),
            ),
            const SizedBox(width: 16),
            SizedBox(
              width: 200,
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: controller,
                      onChanged: (_) => onChanged(),
                      style: const TextStyle(
                          fontSize: 13, color: ColorTokens.textPrimary),
                      decoration: const InputDecoration(
                        hintText: 'e.g. Music/FLAC',
                        hintStyle: TextStyle(
                            color: ColorTokens.textSecondary, fontSize: 12),
                        filled: true,
                        fillColor: ColorTokens.surfaceVariant,
                        contentPadding: EdgeInsets.symmetric(
                            horizontal: 10, vertical: 8),
                        border: OutlineInputBorder(
                          borderRadius:
                              BorderRadius.all(Radius.circular(6)),
                          borderSide: BorderSide.none,
                        ),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    icon: const Icon(Icons.folder_open, size: 16),
                    color: ColorTokens.textSecondary,
                    tooltip: 'Browse',
                    onPressed: () async {
                      final picked = await DeviceFolderPickerDialog.show(
                        context,
                        devicePath: devicePath,
                        initialRelative: raw,
                      );
                      if (picked == null) return;
                      controller.text = picked;
                      onChanged();
                    },
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints(minWidth: 28, minHeight: 28),
                  ),
                ],
              ),
            ),
          ],
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 2),
            child: Text(error,
                style: const TextStyle(
                    fontSize: 11, color: Colors.redAccent)),
          )
        else if (preview != null && raw.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 2),
            child: Text(
              '→ $preview',
              style: const TextStyle(
                  fontSize: 11, color: ColorTokens.textSecondary),
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
    );
  }
}

class _CustomFolderField extends StatelessWidget {
  const _CustomFolderField({
    required this.controller,
    required this.onChanged,
  });
  final TextEditingController controller;
  final VoidCallback onChanged;

  static const _sampleSong = Song(
    id: 'sample',
    title: 'Astronomy Domine',
    album: 'The Piper at the Gates of Dawn',
    artist: 'Pink Floyd',
    albumArtist: 'Pink Floyd',
    track: 1,
    discNumber: 1,
    year: 1967,
    suffix: 'flac',
  );

  @override
  Widget build(BuildContext context) {
    final raw = controller.text;
    final error = raw.trim().isEmpty
        ? 'Template cannot be empty'
        : validateFolderTemplate(raw);
    final preview = error == null
        ? raw
            .replaceAll('\\', '/')
            .split('/')
            .map((seg) =>
                renderFilenameTemplate(seg, _sampleSong).toSafeFilename())
            .where((s) => s.isNotEmpty)
            .join(' / ')
        : null;

    return Padding(
      padding: const EdgeInsets.only(left: 16, top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: controller,
            onChanged: (_) => onChanged(),
            style: const TextStyle(
                fontSize: 13, color: ColorTokens.textPrimary),
            decoration: const InputDecoration(
              hintText: '{albumArtist}/{year} - {album}',
              hintStyle: TextStyle(
                  color: ColorTokens.textSecondary, fontSize: 12),
              filled: true,
              fillColor: ColorTokens.surfaceVariant,
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(6)),
                borderSide: BorderSide.none,
              ),
              isDense: true,
            ),
          ),
          const SizedBox(height: 6),
          if (error != null)
            Text(error,
                style:
                    const TextStyle(fontSize: 11, color: Colors.redAccent))
          else
            Text('→ $preview',
                style: const TextStyle(
                    fontSize: 11, color: ColorTokens.textSecondary),
                overflow: TextOverflow.ellipsis),
          const SizedBox(height: 6),
          const Text(
            'Use / to separate path components. {title} not allowed.',
            style:
                TextStyle(fontSize: 10, color: ColorTokens.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _CustomTemplateField extends StatelessWidget {
  const _CustomTemplateField({
    required this.controller,
    required this.onChanged,
  });
  final TextEditingController controller;
  final VoidCallback onChanged;

  static const _sampleSong = Song(
    id: 'sample',
    title: 'Astronomy Domine',
    album: 'The Piper at the Gates of Dawn',
    artist: 'Pink Floyd',
    albumArtist: 'Pink Floyd',
    track: 1,
    discNumber: 1,
    year: 1967,
    suffix: 'flac',
  );

  @override
  Widget build(BuildContext context) {
    final raw = controller.text;
    final error = raw.trim().isEmpty
        ? 'Template cannot be empty'
        : validateFilenameTemplate(raw);
    final preview = error == null
        ? '${renderFilenameTemplate(raw, _sampleSong).toSafeFilename()}.flac'
        : null;

    return Padding(
      padding: const EdgeInsets.only(left: 16, top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: controller,
            onChanged: (_) => onChanged(),
            style: const TextStyle(
                fontSize: 13, color: ColorTokens.textPrimary),
            decoration: const InputDecoration(
              hintText: '{track:02} - {title}',
              hintStyle: TextStyle(
                  color: ColorTokens.textSecondary, fontSize: 12),
              filled: true,
              fillColor: ColorTokens.surfaceVariant,
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(6)),
                borderSide: BorderSide.none,
              ),
              isDense: true,
            ),
          ),
          const SizedBox(height: 6),
          if (error != null)
            Text(error,
                style:
                    const TextStyle(fontSize: 11, color: Colors.redAccent))
          else
            Text('→ $preview',
                style: const TextStyle(
                    fontSize: 11, color: ColorTokens.textSecondary),
                overflow: TextOverflow.ellipsis),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: const [
              '{track}',
              '{track:02}',
              '{disc}',
              '{disc:02}',
              '{title}',
              '{artist}',
              '{albumArtist}',
              '{album}',
              '{year}',
            ]
                .map((t) => GestureDetector(
                      onTap: () {
                        final s = controller.selection;
                        final start =
                            s.start >= 0 ? s.start : controller.text.length;
                        final end = s.end >= 0 ? s.end : start;
                        final before = controller.text.substring(0, start);
                        final after = controller.text.substring(end);
                        controller.text = '$before$t$after';
                        controller.selection = TextSelection.collapsed(
                            offset: before.length + t.length);
                        onChanged();
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: ColorTokens.surfaceVariant,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          t,
                          style: const TextStyle(
                              fontSize: 10,
                              color: ColorTokens.textSecondary,
                              fontFamily: 'monospace'),
                        ),
                      ),
                    ))
                .toList(),
          ),
        ],
      ),
    );
  }
}

class _Switch extends StatelessWidget {
  const _Switch(
      {required this.label,
      required this.value,
      required this.onChanged});
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => SwitchListTile(
        value: value,
        onChanged: onChanged,
        title: Text(label,
            style: const TextStyle(
                fontSize: 13, color: ColorTokens.textPrimary)),
        dense: true,
        activeThumbColor: ColorTokens.accent,
        contentPadding: EdgeInsets.zero,
      );
}
