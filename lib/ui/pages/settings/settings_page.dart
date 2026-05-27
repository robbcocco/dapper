import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../application/providers/providers.dart';
import '../../../core/theme/color_tokens.dart';
import '../../../data/datasources/remote/subsonic_api.dart';
import '../../../data/datasources/remote/subsonic_client.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  final _formKey = GlobalKey<FormState>();
  final _urlCtrl = TextEditingController();
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _saving = false;
  bool _disconnecting = false;
  bool _obscurePass = true;
  String? _errorMessage;
  String? _currentUrl;

  @override
  void initState() {
    super.initState();
    _loadCurrentCredentials();
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    _userCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadCurrentCredentials() async {
    final storage = ref.read(secureStorageProvider);
    final url = await storage.read(key: 'server_url');
    final username = await storage.read(key: 'username');
    if (!mounted) return;
    setState(() {
      _currentUrl = url;
      if (url != null) _urlCtrl.text = url;
      if (username != null) _userCtrl.text = username;
    });
  }

  Future<void> _disconnect() async {
    setState(() => _disconnecting = true);
    final storage = ref.read(secureStorageProvider);
    await Future.wait([
      storage.delete(key: 'server_url'),
      storage.delete(key: 'username'),
      storage.delete(key: 'password'),
    ]);
    if (!mounted) return;
    ref.invalidate(serverCredentialsProvider);
    setState(() {
      _disconnecting = false;
      _currentUrl = null;
      _urlCtrl.clear();
      _userCtrl.clear();
      _passCtrl.clear();
      _errorMessage = null;
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _errorMessage = null;
    });

    final url = _urlCtrl.text.trim().replaceAll(RegExp(r'/+$'), '');
    final username = _userCtrl.text.trim();
    final password = _passCtrl.text;

    final storage = ref.read(secureStorageProvider);

    await storage.write(key: 'server_url', value: url);
    await storage.write(key: 'username', value: username);
    if (password.isNotEmpty) {
      await storage.write(key: 'password', value: password);
    }

    try {
      final client = _PingClient(url: url, username: username, password: password.isNotEmpty ? password : (await storage.read(key: 'password') ?? ''));
      final ok = await client.ping();
      if (!ok) throw Exception('Server returned non-ok status');

      if (mounted) {
        ref.invalidate(serverCredentialsProvider);
        setState(() {
          _currentUrl = url;
          _saving = false;
          _passCtrl.clear();
          _errorMessage = null;
        });
      }
    } catch (e) {
      // Restore previous credentials on failure.
      await Future.wait([
        storage.delete(key: 'server_url'),
        storage.delete(key: 'username'),
        storage.delete(key: 'password'),
      ]);
      if (mounted) {
        setState(() {
          _saving = false;
          _errorMessage = 'Connection failed: ${e.toString()}';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isConnected = _currentUrl != null;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Connected banner ────────────────────────────────────────────
                if (isConnected) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.08),
                      border: Border.all(
                          color: Colors.green.withValues(alpha: 0.3)),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.check_circle_outline,
                            size: 14, color: Colors.green),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _currentUrl!,
                            style: const TextStyle(
                                fontSize: 12, color: Colors.green),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        TextButton(
                          onPressed: _disconnecting ? null : _disconnect,
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            minimumSize: Size.zero,
                          ),
                          child: _disconnecting
                              ? const SizedBox(
                                  width: 12,
                                  height: 12,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 1.5,
                                      color: Colors.redAccent))
                              : const Text('Disconnect',
                                  style: TextStyle(
                                      fontSize: 11, color: Colors.redAccent)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Update connection',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: ColorTokens.textPrimary,
                    ),
                  ),
                ] else
                  const Text(
                    'Connect to Navidrome',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: ColorTokens.textPrimary,
                    ),
                  ),

                const SizedBox(height: 32),

                // ── Form fields ─────────────────────────────────────────────────
                _Field(
                  controller: _urlCtrl,
                  label: 'Server URL',
                  hint: 'https://music.example.com',
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Required';
                    final uri = Uri.tryParse(v.trim());
                    if (uri == null || !uri.hasScheme) {
                      return 'Enter a valid URL (https://...)';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                _Field(
                  controller: _userCtrl,
                  label: 'Username',
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _passCtrl,
                  obscureText: _obscurePass,
                  style: const TextStyle(color: ColorTokens.textPrimary),
                  decoration: InputDecoration(
                    labelText: isConnected
                        ? 'New Password (leave blank to keep current)'
                        : 'Password',
                    labelStyle: const TextStyle(
                        color: ColorTokens.textSecondary),
                    filled: true,
                    fillColor: ColorTokens.surfaceVariant,
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePass
                            ? Icons.visibility_off
                            : Icons.visibility,
                        color: ColorTokens.textSecondary,
                      ),
                      onPressed: () =>
                          setState(() => _obscurePass = !_obscurePass),
                    ),
                  ),
                  validator: (v) => (!isConnected && (v == null || v.isEmpty))
                      ? 'Required'
                      : null,
                ),

                if (_errorMessage != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _errorMessage!,
                    style: const TextStyle(
                        color: Colors.redAccent, fontSize: 12),
                  ),
                ],
                const SizedBox(height: 32),
                FilledButton(
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(isConnected ? 'Update Connection' : 'Connect'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
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
        border: const OutlineInputBorder(),
      ),
      validator: validator,
    );
  }
}

class _PingClient {
  _PingClient({
    required this.url,
    required this.username,
    required this.password,
  });

  final String url;
  final String username;
  final String password;

  Future<bool> ping() async {
    final client = SubsonicClient(
      baseUrl: url,
      username: username,
      password: password,
    );
    final api = SubsonicApi(client);
    return api.ping();
  }
}
