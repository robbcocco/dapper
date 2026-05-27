import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../../core/theme/color_tokens.dart';

const _audioExtensions = {
  'flac', 'mp3', 'aac', 'm4a', 'ogg', 'opus',
  'wav', 'aiff', 'aif', 'ape', 'wv', 'dsf', 'dff',
};

bool _isAudio(String path) =>
    _audioExtensions.contains(p.extension(path).toLowerCase().replaceFirst('.', ''));

class DeviceFileBrowser extends StatefulWidget {
  const DeviceFileBrowser({super.key, required this.rootPath});

  final String rootPath;

  @override
  State<DeviceFileBrowser> createState() => _DeviceFileBrowserState();
}

class _DeviceFileBrowserState extends State<DeviceFileBrowser> {
  // Incrementing this forces _FolderNode to rebuild from scratch.
  int _generation = 0;

  void _refresh() => setState(() => _generation++);

  @override
  void didUpdateWidget(DeviceFileBrowser old) {
    super.didUpdateWidget(old);
    // Root path changed (settings updated or different device selected).
    if (old.rootPath != widget.rootPath) _generation++;
  }

  @override
  Widget build(BuildContext context) {
    final root = Directory(widget.rootPath);
    if (!root.existsSync()) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.folder_off_outlined,
                size: 36, color: ColorTokens.textSecondary),
            const SizedBox(height: 12),
            Text(
              'Folder not found on device',
              style: const TextStyle(
                  fontSize: 13, color: ColorTokens.textSecondary),
            ),
            const SizedBox(height: 4),
            Text(
              widget.rootPath,
              style: const TextStyle(
                  fontSize: 10, color: ColorTokens.textSecondary),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _refresh,
              icon: const Icon(Icons.refresh, size: 14),
              label: const Text('Retry', style: TextStyle(fontSize: 12)),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        // ── Toolbar ──────────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 8, 0),
          child: Row(
            children: [
              Text(
                p.basename(widget.rootPath).isEmpty
                    ? widget.rootPath
                    : p.basename(widget.rootPath),
                style: const TextStyle(
                    fontSize: 10, color: ColorTokens.textSecondary),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.refresh,
                    size: 15, color: ColorTokens.textSecondary),
                tooltip: 'Refresh',
                onPressed: _refresh,
                padding: EdgeInsets.zero,
                constraints:
                    const BoxConstraints(minWidth: 28, minHeight: 28),
              ),
            ],
          ),
        ),
        const Divider(height: 1, color: ColorTokens.divider),

        // ── Tree ─────────────────────────────────────────────────────────────
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
              _FolderNode(
                key: ValueKey('${widget.rootPath}/$_generation'),
                path: widget.rootPath,
                depth: 0,
                startExpanded: true,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _FolderNode extends StatefulWidget {
  const _FolderNode({
    super.key,
    required this.path,
    required this.depth,
    this.startExpanded = false,
  });

  final String path;
  final int depth;
  final bool startExpanded;

  @override
  State<_FolderNode> createState() => _FolderNodeState();
}

class _FolderNodeState extends State<_FolderNode> {
  bool _expanded = false;
  List<FileSystemEntity>? _children;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.startExpanded) _expand();
  }

  void _expand() {
    if (_expanded) {
      setState(() => _expanded = false);
      return;
    }
    if (_children != null) {
      setState(() => _expanded = true);
      return;
    }
    setState(() => _loading = true);
    Directory(widget.path).list().toList().then((entities) {
      entities.sort((a, b) {
        final aIsDir = a is Directory;
        final bIsDir = b is Directory;
        if (aIsDir != bIsDir) return aIsDir ? -1 : 1;
        return p.basename(a.path).toLowerCase()
            .compareTo(p.basename(b.path).toLowerCase());
      });
      if (mounted) {
        setState(() {
          _children = entities;
          _expanded = true;
          _loading = false;
          _error = null;
        });
      }
    }).catchError((e) {
      if (mounted) setState(() { _loading = false; _error = e.toString(); });
    });
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.depth == 0
        ? p.basename(widget.path).isEmpty ? widget.path : p.basename(widget.path)
        : p.basename(widget.path);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: _expand,
          child: Padding(
            padding: EdgeInsets.only(
              left: 16.0 + widget.depth * 16,
              right: 16,
              top: 4,
              bottom: 4,
            ),
            child: Row(
              children: [
                if (_loading)
                  const SizedBox(
                    width: 14, height: 14,
                    child: CircularProgressIndicator(strokeWidth: 1.5),
                  )
                else
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
                      fontSize: 12,
                      color: ColorTokens.textPrimary,
                      fontWeight: FontWeight.w500,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (_error != null)
                  const Icon(Icons.error_outline,
                      size: 12, color: Colors.redAccent)
                else if (_expanded && _children != null)
                  Text(
                    _summary(_children!),
                    style: const TextStyle(
                        fontSize: 10, color: ColorTokens.textSecondary),
                  ),
              ],
            ),
          ),
        ),
        if (_expanded && _children != null)
          ..._children!.map((entity) {
            if (entity is Directory) {
              return _FolderNode(
                key: ValueKey(entity.path),
                path: entity.path,
                depth: widget.depth + 1,
              );
            } else if (entity is File && _isAudio(entity.path)) {
              return _AudioFileRow(path: entity.path, depth: widget.depth + 1);
            }
            return const SizedBox.shrink();
          }),
      ],
    );
  }

  String _summary(List<FileSystemEntity> entities) {
    final dirs = entities.whereType<Directory>().length;
    final files = entities.where((e) => e is File && _isAudio(e.path)).length;
    final parts = <String>[];
    if (dirs > 0) parts.add('$dirs folder${dirs == 1 ? '' : 's'}');
    if (files > 0) parts.add('$files track${files == 1 ? '' : 's'}');
    return parts.join(', ');
  }
}

class _AudioFileRow extends StatelessWidget {
  const _AudioFileRow({required this.path, required this.depth});

  final String path;
  final int depth;

  @override
  Widget build(BuildContext context) {
    final name = p.basenameWithoutExtension(path);
    final ext = p.extension(path).replaceFirst('.', '').toUpperCase();

    return Padding(
      padding: EdgeInsets.only(
        left: 16.0 + depth * 16,
        right: 16,
        top: 2,
        bottom: 2,
      ),
      child: Row(
        children: [
          const Icon(Icons.music_note, size: 12, color: ColorTokens.textSecondary),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              name,
              style: const TextStyle(fontSize: 11, color: ColorTokens.textSecondary),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
              color: ColorTokens.surfaceVariant,
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text(
              ext,
              style: const TextStyle(fontSize: 9, color: ColorTokens.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}
