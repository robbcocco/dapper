import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../../core/theme/color_tokens.dart';

/// Folder-only picker scoped to [devicePath]. Returns the chosen path
/// **relative to** [devicePath] (so it slots straight into
/// `DeviceSettings.musicRootFolder`), or null on cancel.
///
/// Reuses the same expand-on-tap tree pattern as DeviceFileBrowser but
/// hides files and exposes a "Select this folder" affordance per node.
class DeviceFolderPickerDialog extends StatefulWidget {
  const DeviceFolderPickerDialog({
    super.key,
    required this.devicePath,
    this.initialRelative = '',
  });

  final String devicePath;
  final String initialRelative;

  static Future<String?> show(BuildContext context,
      {required String devicePath, String initialRelative = ''}) {
    return showDialog<String>(
      context: context,
      builder: (_) => DeviceFolderPickerDialog(
        devicePath: devicePath,
        initialRelative: initialRelative,
      ),
    );
  }

  @override
  State<DeviceFolderPickerDialog> createState() =>
      _DeviceFolderPickerDialogState();
}

class _DeviceFolderPickerDialogState extends State<DeviceFolderPickerDialog> {
  String _selectedAbsolute = '';

  @override
  void initState() {
    super.initState();
    _selectedAbsolute = widget.initialRelative.isEmpty
        ? widget.devicePath
        : p.joinAll([widget.devicePath, ...p.split(widget.initialRelative)]);
  }

  String get _relative {
    final rel = p.relative(_selectedAbsolute, from: widget.devicePath);
    return rel == '.' ? '' : rel;
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: ColorTokens.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 560),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Choose music folder',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: ColorTokens.textPrimary,
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: ColorTokens.surfaceVariant,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  _relative.isEmpty ? '(device root)' : _relative,
                  style: const TextStyle(
                      fontSize: 12, color: ColorTokens.textPrimary),
                ),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: ColorTokens.glassBorder),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: ListView(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    children: [
                      _FolderNode(
                        path: widget.devicePath,
                        rootPath: widget.devicePath,
                        depth: 0,
                        selectedPath: _selectedAbsolute,
                        onSelect: (abs) =>
                            setState(() => _selectedAbsolute = abs),
                        startExpanded: true,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
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
                    onPressed: () => Navigator.of(context).pop(_relative),
                    style: FilledButton.styleFrom(
                        backgroundColor: ColorTokens.accent),
                    child: const Text('Select'),
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

class _FolderNode extends StatefulWidget {
  const _FolderNode({
    super.key,
    required this.path,
    required this.rootPath,
    required this.depth,
    required this.selectedPath,
    required this.onSelect,
    this.startExpanded = false,
  });

  final String path;
  final String rootPath;
  final int depth;
  final String selectedPath;
  final ValueChanged<String> onSelect;
  final bool startExpanded;

  @override
  State<_FolderNode> createState() => _FolderNodeState();
}

class _FolderNodeState extends State<_FolderNode> {
  bool _expanded = false;
  List<Directory>? _children;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    if (widget.startExpanded) _toggle();
  }

  Future<void> _toggle() async {
    if (_expanded) {
      setState(() => _expanded = false);
      return;
    }
    if (_children == null) {
      setState(() => _loading = true);
      try {
        final entries = await Directory(widget.path).list().toList();
        final dirs = entries
            .whereType<Directory>()
            .where((d) => !p.basename(d.path).startsWith('.'))
            .toList()
          ..sort((a, b) => p
              .basename(a.path)
              .toLowerCase()
              .compareTo(p.basename(b.path).toLowerCase()));
        if (mounted) {
          setState(() {
            _children = dirs;
            _loading = false;
            _expanded = true;
          });
        }
      } catch (_) {
        if (mounted) setState(() => _loading = false);
      }
      return;
    }
    setState(() => _expanded = true);
  }

  @override
  Widget build(BuildContext context) {
    final isSelected = widget.path == widget.selectedPath;
    final name = widget.depth == 0
        ? '(device root)'
        : p.basename(widget.path);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => widget.onSelect(widget.path),
          onDoubleTap: _toggle,
          child: Container(
            color: isSelected
                ? ColorTokens.accent.withValues(alpha: 0.16)
                : null,
            padding: EdgeInsets.only(
              left: 10.0 + widget.depth * 14,
              right: 10,
              top: 5,
              bottom: 5,
            ),
            child: Row(
              children: [
                GestureDetector(
                  onTap: _toggle,
                  child: SizedBox(
                    width: 16,
                    child: _loading
                        ? const SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(strokeWidth: 1.5),
                          )
                        : Icon(
                            _expanded
                                ? Icons.keyboard_arrow_down
                                : Icons.keyboard_arrow_right,
                            size: 14,
                            color: ColorTokens.textSecondary,
                          ),
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  _expanded ? Icons.folder_open : Icons.folder,
                  size: 14,
                  color: ColorTokens.accent,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    name,
                    style: const TextStyle(
                        fontSize: 12, color: ColorTokens.textPrimary),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_expanded && _children != null)
          ..._children!.map((d) => _FolderNode(
                key: ValueKey(d.path),
                path: d.path,
                rootPath: widget.rootPath,
                depth: widget.depth + 1,
                selectedPath: widget.selectedPath,
                onSelect: widget.onSelect,
              )),
      ],
    );
  }
}
