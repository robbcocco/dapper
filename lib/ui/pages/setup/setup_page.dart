import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:macos_window_utils/macos_window_utils.dart';

import '../../../application/providers/providers.dart';
import '../../../core/theme/color_tokens.dart';
import '../../../data/datasources/remote/subsonic_api.dart';
import '../../../data/datasources/remote/subsonic_client.dart';
import '../../../domain/models/navidrome_server.dart';

class SetupPage extends ConsumerStatefulWidget {
  const SetupPage({super.key});

  @override
  ConsumerState<SetupPage> createState() => _SetupPageState();
}

class _SetupPageState extends ConsumerState<SetupPage> {
  final _formKey = GlobalKey<FormState>();
  final _urlCtrl = TextEditingController();
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _obscurePass = true;
  bool _connecting = false;
  String? _error;

  @override
  void dispose() {
    _urlCtrl.dispose();
    _userCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _connecting = true;
      _error = null;
    });

    final url = _urlCtrl.text.trim().replaceAll(RegExp(r'/+$'), '');
    final username = _userCtrl.text.trim();
    final password = _passCtrl.text;

    try {
      final client =
          SubsonicClient(baseUrl: url, username: username, password: password);
      final ok = await SubsonicApi(client).ping();
      if (!ok) throw Exception('non-ok');
    } catch (e) {
      if (mounted) {
        setState(() {
          _connecting = false;
          _error = _friendlyError(e.toString());
        });
      }
      return;
    }

    final host = Uri.tryParse(url)?.host ?? url;
    final server = NavidromeServer(
      id: ServersNotifier.newId(),
      name: host,
      url: url,
      username: username,
    );
    await ref.read(serversProvider.notifier).add(server, password);
    // serverCredentialsProvider becomes non-null → AppShell rebuilds automatically.
  }

  String _friendlyError(String raw) {
    if (raw.contains('SocketException') ||
        raw.contains('Failed host lookup') ||
        raw.contains('Connection refused')) {
      return 'Could not reach the server. Check the URL and your network.';
    }
    if (raw.contains('401') || raw.contains('Unauthorized')) {
      return 'Invalid username or password.';
    }
    if (raw.contains('non-ok') || raw.contains('HandshakeException')) {
      return 'Connected, but authentication failed. Check your credentials.';
    }
    return 'Connection failed. $raw';
  }

  @override
  Widget build(BuildContext context) {
    final content = Center(
      child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
          child: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ── Header ────────────────────────────────────────────────────
                const Text(
                  'dapper',
                  style: TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.w700,
                    color: ColorTokens.textPrimary,
                    letterSpacing: -1.5,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Transfer music from Navidrome to your DAP',
                  style: TextStyle(
                    fontSize: 13,
                    color: ColorTokens.textSecondary,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 40),

                // ── Form card ─────────────────────────────────────────────────
                Container(
                  padding: const EdgeInsets.all(28),
                  decoration: BoxDecoration(
                    color: ColorTokens.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: ColorTokens.glassBorder),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.2),
                        blurRadius: 20,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'Connect to Navidrome',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: ColorTokens.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 20),

                        if (_error != null) ...[
                          _ErrorBanner(message: _error!),
                          const SizedBox(height: 16),
                        ],

                        _SetupField(
                          controller: _urlCtrl,
                          label: 'Server URL',
                          hint: 'https://music.example.com',
                          keyboardType: TextInputType.url,
                          onSubmitted: _connect,
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) {
                              return 'Required';
                            }
                            final uri = Uri.tryParse(v.trim());
                            if (uri == null || !uri.hasScheme) {
                              return 'Enter a valid URL';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),

                        _SetupField(
                          controller: _userCtrl,
                          label: 'Username',
                          onSubmitted: _connect,
                          validator: (v) =>
                              (v == null || v.trim().isEmpty) ? 'Required' : null,
                        ),
                        const SizedBox(height: 12),

                        _SetupField(
                          controller: _passCtrl,
                          label: 'Password',
                          obscureText: _obscurePass,
                          onSubmitted: _connect,
                          validator: (v) =>
                              (v == null || v.isEmpty) ? 'Required' : null,
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscurePass
                                  ? Icons.visibility_off
                                  : Icons.visibility,
                              size: 16,
                              color: ColorTokens.textSecondary,
                            ),
                            onPressed: () =>
                                setState(() => _obscurePass = !_obscurePass),
                          ),
                        ),
                        const SizedBox(height: 24),

                        FilledButton(
                          onPressed: _connecting ? null : _connect,
                          style: FilledButton.styleFrom(
                            backgroundColor: ColorTokens.accent,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: _connecting
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text(
                                  'Connect',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                        ),
                      ],
                    ),
                  ),
                ),

                // ── Footer note ───────────────────────────────────────────────
                const SizedBox(height: 20),
                const Text(
                  'Lidarr and other options can be configured later in Settings.',
                  style: TextStyle(fontSize: 11, color: ColorTokens.textSecondary),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
    );
    return Platform.isMacOS ? TitlebarSafeArea(child: content) : content;
  }
}


// ── Shared form field ─────────────────────────────────────────────────────────

class _SetupField extends StatelessWidget {
  const _SetupField({
    required this.controller,
    required this.label,
    this.hint,
    this.obscureText = false,
    this.keyboardType,
    this.suffixIcon,
    this.validator,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String label;
  final String? hint;
  final bool obscureText;
  final TextInputType? keyboardType;
  final Widget? suffixIcon;
  final String? Function(String?)? validator;
  final VoidCallback? onSubmitted;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      autocorrect: false,
      style: const TextStyle(color: ColorTokens.textPrimary),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: const TextStyle(color: ColorTokens.textSecondary),
        hintStyle:
            const TextStyle(color: ColorTokens.textSecondary, fontSize: 13),
        filled: true,
        fillColor: ColorTokens.surfaceVariant,
        suffixIcon: suffixIcon,
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
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Colors.redAccent),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Colors.redAccent, width: 1.5),
        ),
      ),
      validator: validator,
      onFieldSubmitted: onSubmitted != null ? (_) => onSubmitted!() : null,
    );
  }
}

// ── Error banner ──────────────────────────────────────────────────────────────

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.redAccent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.redAccent.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, size: 14, color: Colors.redAccent),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(fontSize: 12, color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );
  }
}
