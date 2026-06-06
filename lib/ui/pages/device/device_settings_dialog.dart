import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../application/device/device_settings_notifier.dart';
import '../../../core/theme/color_tokens.dart';
import '../../../domain/models/device_settings.dart';

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
  late FolderStructure _folderStructure;
  late FilenameFormat _filenameFormat;
  late bool _includeYear;
  late bool _overwriteExisting;
  late TranscodeFormat _transcodeFormat;
  late int? _transcodeMaxBitRate;

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
  }

  @override
  void dispose() {
    _rootCtrl.dispose();
    _playlistCtrl.dispose();
    super.dispose();
  }

  void _save() {
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
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.all(28),
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
              _SettingRow(
                label: 'Music root folder',
                hint: 'Leave empty to use device root',
                child: _TextField(
                  controller: _rootCtrl,
                  hint: 'e.g. Music',
                ),
              ),
              const SizedBox(height: 12),
              _SettingRow(
                label: 'Playlist folder',
                hint: 'Relative to music root',
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
