import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../application/providers/providers.dart';
import '../../../core/theme/color_tokens.dart';
import '../../../data/datasources/remote/subsonic_api.dart';
import '../../../data/datasources/remote/subsonic_client.dart';
import '../../../domain/models/navidrome_server.dart';

/// Shows the add/edit server dialog. Returns true if a server was saved.
Future<bool> showServerFormDialog(
  BuildContext context, {
  NavidromeServer? existing,
}) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _ServerFormDialog(existing: existing),
  );
  return result ?? false;
}

class _ServerFormDialog extends ConsumerStatefulWidget {
  const _ServerFormDialog({this.existing});
  final NavidromeServer? existing;

  @override
  ConsumerState<_ServerFormDialog> createState() => _ServerFormDialogState();
}

class _ServerFormDialogState extends ConsumerState<_ServerFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _urlCtrl;
  late final TextEditingController _userCtrl;
  final _passCtrl = TextEditingController();
  bool _obscurePass = true;
  bool _saving = false;
  String? _error;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.existing?.name ?? '');
    _urlCtrl = TextEditingController(text: widget.existing?.url ?? '');
    _userCtrl = TextEditingController(text: widget.existing?.username ?? '');
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _urlCtrl.dispose();
    _userCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });

    final url = _urlCtrl.text.trim().replaceAll(RegExp(r'/+$'), '');
    final username = _userCtrl.text.trim();
    final password = _passCtrl.text;

    // Resolve password: new input or existing stored password for edits.
    String resolvedPassword = password;
    if (resolvedPassword.isEmpty && _isEdit) {
      resolvedPassword =
          await ref.read(serverRepositoryProvider).loadPassword(widget.existing!.id) ?? '';
    }

    try {
      final client = SubsonicClient(baseUrl: url, username: username, password: resolvedPassword);
      final ok = await SubsonicApi(client).ping();
      if (!ok) throw Exception('Server returned non-ok status');
    } catch (e) {
      if (mounted) setState(() { _saving = false; _error = 'Connection failed: $e'; });
      return;
    }

    final server = _isEdit
        ? widget.existing!.copyWith(
            name: _nameCtrl.text.trim(),
            url: url,
            username: username,
          )
        : NavidromeServer(
            id: ServersNotifier.newId(),
            name: _nameCtrl.text.trim().isEmpty ? url : _nameCtrl.text.trim(),
            url: url,
            username: username,
          );

    if (_isEdit) {
      await ref.read(serversProvider.notifier).update(
            server,
            newPassword: password.isNotEmpty ? password : null,
          );
      if (password.isNotEmpty) {
        ref.invalidate(serverCredentialsProvider);
      }
    } else {
      await ref.read(serversProvider.notifier).add(server, resolvedPassword);
    }

    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: ColorTokens.surface,
      title: Text(
        _isEdit ? 'Edit Server' : 'Add Server',
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
                hint: 'Home, Work…',
              ),
              const SizedBox(height: 12),
              _FormField(
                controller: _urlCtrl,
                label: 'Server URL',
                hint: 'https://music.example.com',
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Required';
                  final uri = Uri.tryParse(v.trim());
                  if (uri == null || !uri.hasScheme) return 'Enter a valid URL';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              _FormField(
                controller: _userCtrl,
                label: 'Username',
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _passCtrl,
                obscureText: _obscurePass,
                style: const TextStyle(color: ColorTokens.textPrimary),
                decoration: InputDecoration(
                  labelText: _isEdit
                      ? 'Password (leave blank to keep current)'
                      : 'Password',
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
                      _obscurePass ? Icons.visibility_off : Icons.visibility,
                      size: 16,
                      color: ColorTokens.textSecondary,
                    ),
                    onPressed: () =>
                        setState(() => _obscurePass = !_obscurePass),
                  ),
                ),
                validator: _isEdit
                    ? null
                    : (v) => (v == null || v.isEmpty) ? 'Required' : null,
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
