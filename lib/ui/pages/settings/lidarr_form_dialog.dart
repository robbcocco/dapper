import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../application/providers/providers.dart';
import '../../../core/theme/color_tokens.dart';
import '../../../data/datasources/remote/lidarr_client.dart';
import '../../../domain/models/lidarr_instance.dart';

/// Shows the add/edit Lidarr instance dialog. Returns true if an instance was saved.
Future<bool> showLidarrFormDialog(
  BuildContext context, {
  LidarrInstance? existing,
}) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _LidarrFormDialog(existing: existing),
  );
  return result ?? false;
}

class _LidarrFormDialog extends ConsumerStatefulWidget {
  const _LidarrFormDialog({this.existing});
  final LidarrInstance? existing;

  @override
  ConsumerState<_LidarrFormDialog> createState() => _LidarrFormDialogState();
}

class _LidarrFormDialogState extends ConsumerState<_LidarrFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _urlCtrl;
  final _keyCtrl = TextEditingController();
  bool _obscureKey = true;
  bool _saving = false;
  String? _error;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.existing?.name ?? '');
    _urlCtrl = TextEditingController(text: widget.existing?.url ?? '');
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _urlCtrl.dispose();
    _keyCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });

    final url = _urlCtrl.text.trim().replaceAll(RegExp(r'/+$'), '');
    final apiKey = _keyCtrl.text.trim();

    // Resolve key: new input or existing stored key for edits.
    String resolvedKey = apiKey;
    if (resolvedKey.isEmpty && _isEdit) {
      resolvedKey =
          await ref.read(lidarrRepositoryProvider).loadApiKey(widget.existing!.id) ?? '';
    }

    final client = LidarrClient(baseUrl: url, apiKey: resolvedKey);
    try {
      final ok = await client.testConnection();
      if (!ok) throw Exception('Server returned non-ok status');
    } catch (e) {
      if (mounted) setState(() { _saving = false; _error = _friendlyError(e); });
      return;
    } finally {
      client.dispose();
    }

    final instance = _isEdit
        ? widget.existing!.copyWith(
            name: _nameCtrl.text.trim(),
            url: url,
          )
        : LidarrInstance(
            id: LidarrInstancesNotifier.newId(),
            name: _nameCtrl.text.trim().isEmpty ? url : _nameCtrl.text.trim(),
            url: url,
          );

    if (_isEdit) {
      await ref.read(lidarrInstancesProvider.notifier).update(
            instance,
            newApiKey: apiKey.isNotEmpty ? apiKey : null,
          );
      if (apiKey.isNotEmpty) {
        ref.invalidate(lidarrCredentialsProvider);
      }
    } else {
      await ref.read(lidarrInstancesProvider.notifier).add(instance, resolvedKey);
    }

    if (mounted) Navigator.of(context).pop(true);
  }

  String _friendlyError(Object e) {
    final raw = e.toString();
    if (raw.contains('401') || raw.contains('Unauthorized')) {
      return 'Invalid API key.';
    }
    if (raw.contains('Timeout') ||
        raw.contains('SocketException') ||
        raw.contains('connectionError') ||
        raw.contains('Failed host lookup') ||
        raw.contains('Connection refused')) {
      return 'Couldn\'t reach Lidarr. Check the URL and that it\'s running.';
    }
    return 'Connection failed: $raw';
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: ColorTokens.surface,
      title: Text(
        _isEdit ? 'Edit Lidarr Instance' : 'Add Lidarr Instance',
        style: const TextStyle(color: ColorTokens.textPrimary, fontSize: 16),
      ),
      content: SizedBox(
        width: 400,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_error != null) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.redAccent.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.redAccent.withValues(alpha: 0.4)),
                  ),
                  child: Text(_error!,
                      style: const TextStyle(fontSize: 12, color: Colors.redAccent)),
                ),
                const SizedBox(height: 12),
              ],
              _FormField(
                controller: _nameCtrl,
                label: 'Name',
                hint: 'Main, Podcasts…',
              ),
              const SizedBox(height: 12),
              _FormField(
                controller: _urlCtrl,
                label: 'Lidarr URL',
                hint: 'http://localhost:8686',
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Required';
                  final uri = Uri.tryParse(v.trim());
                  if (uri == null || !uri.hasScheme) return 'Enter a valid URL';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _keyCtrl,
                obscureText: _obscureKey,
                style: const TextStyle(color: ColorTokens.textPrimary),
                decoration: InputDecoration(
                  labelText: _isEdit
                      ? 'API Key (leave blank to keep current)'
                      : 'API Key',
                  labelStyle: const TextStyle(color: ColorTokens.textSecondary),
                  filled: true,
                  fillColor: ColorTokens.surfaceVariant,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: ColorTokens.divider),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: ColorTokens.glassBorder),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide:
                        const BorderSide(color: ColorTokens.accent, width: 1.5),
                  ),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscureKey ? Icons.visibility_off : Icons.visibility,
                      size: 16,
                      color: ColorTokens.textSecondary,
                    ),
                    onPressed: () =>
                        setState(() => _obscureKey = !_obscureKey),
                  ),
                ),
                validator: _isEdit
                    ? null
                    : (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel',
              style: TextStyle(color: ColorTokens.textSecondary)),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          style: FilledButton.styleFrom(backgroundColor: ColorTokens.accent),
          child: _saving
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                      strokeWidth: 1.5, color: Colors.white),
                )
              : Text(_isEdit ? 'Save' : 'Test & Add'),
        ),
      ],
    );
  }
}

class _FormField extends StatelessWidget {
  const _FormField({
    required this.controller,
    required this.label,
    this.hint,
    this.validator,
  });

  final TextEditingController controller;
  final String label;
  final String? hint;
  final String? Function(String?)? validator;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      style: const TextStyle(color: ColorTokens.textPrimary),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: const TextStyle(color: ColorTokens.textSecondary),
        hintStyle: const TextStyle(color: ColorTokens.textSecondary),
        filled: true,
        fillColor: ColorTokens.surfaceVariant,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: ColorTokens.divider),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: ColorTokens.glassBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: ColorTokens.accent, width: 1.5),
        ),
      ),
      validator: validator,
    );
  }
}
