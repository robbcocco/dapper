import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../application/lidarr/lidarr_notifier.dart';
import '../../../application/providers/providers.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/color_tokens.dart';
import '../../../data/datasources/remote/lidarr_client.dart';
import '../../../data/datasources/remote/subsonic_api.dart';
import '../../../data/datasources/remote/subsonic_client.dart';
import '../../../domain/models/device_settings.dart';
import '../../../domain/models/lidarr_models.dart';
import '../device/device_settings_dialog.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: ColorTokens.glassBorder)),
          ),
          child: TabBar(
            controller: _tabController,
            labelColor: ColorTokens.accent,
            unselectedLabelColor: ColorTokens.textSecondary,
            indicatorColor: ColorTokens.accent,
            indicatorSize: TabBarIndicatorSize.label,
            labelStyle: const TextStyle(fontSize: 13),
            tabs: const [
              Tab(text: 'Navidrome'),
              Tab(text: 'Lidarr'),
              Tab(text: 'Devices'),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: const [
              _NavidromeTab(),
              _LidarrTab(),
              _DevicesTab(),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Navidrome tab ─────────────────────────────────────────────────────────────

class _NavidromeTab extends ConsumerStatefulWidget {
  const _NavidromeTab();

  @override
  ConsumerState<_NavidromeTab> createState() => _NavidromeTabState();
}

class _NavidromeTabState extends ConsumerState<_NavidromeTab> {
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
      final client = _PingClient(
        url: url,
        username: username,
        password: password.isNotEmpty
            ? password
            : (await storage.read(key: 'password') ?? ''),
      );
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
        child: ListView(
          padding: const EdgeInsets.fromLTRB(32, 32, 32, AppConstants.scrollBottomInset),
          children: [
            if (isConnected) ...[
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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

            Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
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
                    style:
                        const TextStyle(color: ColorTokens.textPrimary),
                    decoration: InputDecoration(
                      labelText: isConnected
                          ? 'New Password (leave blank to keep current)'
                          : 'Password',
                      labelStyle: const TextStyle(
                          color: ColorTokens.textSecondary),
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
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePass
                              ? Icons.visibility_off
                              : Icons.visibility,
                          color: ColorTokens.textSecondary,
                        ),
                        onPressed: () => setState(
                            () => _obscurePass = !_obscurePass),
                      ),
                    ),
                    validator: (v) =>
                        (!isConnected && (v == null || v.isEmpty))
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
                        : Text(isConnected
                            ? 'Update Connection'
                            : 'Connect'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Devices tab ───────────────────────────────────────────────────────────────

class _DevicesTab extends ConsumerWidget {
  const _DevicesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final storedAsync = ref.watch(allStoredDeviceSettingsProvider);
    final connectedDevices =
        ref.watch(connectedDevicesProvider).valueOrNull ?? [];

    return storedAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) =>
          Center(child: Text('$e', style: const TextStyle(color: ColorTokens.textSecondary))),
      data: (stored) {
        if (stored.isEmpty) {
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.devices_other,
                    size: 40, color: ColorTokens.textSecondary),
                SizedBox(height: 12),
                Text('No devices configured yet',
                    style: TextStyle(
                        fontSize: 14, color: ColorTokens.textSecondary)),
                SizedBox(height: 6),
                Text(
                    'Connect a device and open its settings via the Device page',
                    style: TextStyle(
                        fontSize: 11, color: ColorTokens.textSecondary)),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, AppConstants.scrollBottomInset),
          itemCount: stored.length,
          itemBuilder: (context, i) {
            final s = stored[i];
            final isConnected =
                connectedDevices.any((d) => d.path == s.devicePath);
            return _DeviceSettingsTile(
              settings: s,
              isConnected: isConnected,
            );
          },
        );
      },
    );
  }
}

class _DeviceSettingsTile extends StatelessWidget {
  const _DeviceSettingsTile({
    required this.settings,
    required this.isConnected,
  });

  final DeviceSettings settings;
  final bool isConnected;

  @override
  Widget build(BuildContext context) {
    final pathParts = settings.devicePath.split('/');
    final label = pathParts.lastWhere((p) => p.isNotEmpty,
        orElse: () => settings.devicePath);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: ColorTokens.surfaceVariant,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: ColorTokens.glassBorder),
      ),
      child: Row(
        children: [
          Icon(
            isConnected ? Icons.usb : Icons.usb_off,
            size: 18,
            color: isConnected ? ColorTokens.accent : ColorTokens.textSecondary,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                      fontSize: 13, color: ColorTokens.textPrimary),
                ),
                Text(
                  settings.devicePath,
                  style: const TextStyle(
                      fontSize: 10, color: ColorTokens.textSecondary),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  _summary(settings),
                  style: const TextStyle(
                      fontSize: 11, color: ColorTokens.textSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: isConnected
                  ? Colors.green.withValues(alpha: 0.12)
                  : ColorTokens.divider,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              isConnected ? 'Connected' : 'Not connected',
              style: TextStyle(
                fontSize: 10,
                color: isConnected ? Colors.green : ColorTokens.textSecondary,
              ),
            ),
          ),
          const SizedBox(width: 8),
          if (isConnected)
            IconButton(
              icon: const Icon(Icons.settings_outlined,
                  size: 16, color: ColorTokens.textSecondary),
              tooltip: 'Edit settings',
              onPressed: () =>
                  DeviceSettingsDialog.show(context, settings.devicePath),
              padding: EdgeInsets.zero,
              constraints:
                  const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
        ],
      ),
    );
  }

  String _summary(DeviceSettings s) {
    final parts = <String>[];
    if (s.musicRootFolder.isNotEmpty) parts.add('Root: ${s.musicRootFolder}');
    parts.add(_folderLabel(s.folderStructure));
    return parts.join(' · ');
  }

  String _folderLabel(FolderStructure f) => switch (f) {
        FolderStructure.artistAlbum => 'Artist / Album',
        FolderStructure.artistAlbumYear => 'Artist / Year - Album',
        FolderStructure.artistOnly => 'Artist',
        FolderStructure.flat => 'Flat',
      };
}


// ── Lidarr tab ────────────────────────────────────────────────────────────────

class _LidarrTab extends ConsumerStatefulWidget {
  const _LidarrTab();

  @override
  ConsumerState<_LidarrTab> createState() => _LidarrTabState();
}

class _LidarrTabState extends ConsumerState<_LidarrTab> {
  final _formKey = GlobalKey<FormState>();
  final _urlCtrl = TextEditingController();
  final _keyCtrl = TextEditingController();
  bool _obscureKey = true;
  bool _saving = false;
  bool _disconnecting = false;
  String? _errorMessage;
  String? _currentUrl;

  LidarrRootFolder? _selectedRootFolder;
  LidarrQualityProfile? _selectedQualityProfile;

  @override
  void initState() {
    super.initState();
    _loadCurrentCredentials();
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    _keyCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadCurrentCredentials() async {
    final storage = ref.read(secureStorageProvider);
    final url = await storage.read(key: 'lidarr_url');
    final rootFolderId = await storage.read(key: 'lidarr_root_folder_id');
    final rootFolderPath = await storage.read(key: 'lidarr_root_folder_path');
    final qualityProfileId =
        await storage.read(key: 'lidarr_quality_profile_id');
    final qualityProfileName =
        await storage.read(key: 'lidarr_quality_profile_name');
    if (!mounted) return;
    setState(() {
      _currentUrl = url;
      if (url != null) _urlCtrl.text = url;
      if (rootFolderId != null && rootFolderPath != null) {
        _selectedRootFolder = LidarrRootFolder(
          id: int.tryParse(rootFolderId) ?? 0,
          path: rootFolderPath,
        );
      }
      if (qualityProfileId != null && qualityProfileName != null) {
        _selectedQualityProfile = LidarrQualityProfile(
          id: int.tryParse(qualityProfileId) ?? 0,
          name: qualityProfileName,
        );
      }
    });
  }

  Future<void> _disconnect() async {
    setState(() => _disconnecting = true);
    final storage = ref.read(secureStorageProvider);
    await Future.wait([
      storage.delete(key: 'lidarr_url'),
      storage.delete(key: 'lidarr_api_key'),
      storage.delete(key: 'lidarr_root_folder_id'),
      storage.delete(key: 'lidarr_root_folder_path'),
      storage.delete(key: 'lidarr_quality_profile_id'),
      storage.delete(key: 'lidarr_quality_profile_name'),
    ]);
    if (!mounted) return;
    ref.invalidate(lidarrCredentialsProvider);
    ref.invalidate(lidarrRootFoldersProvider);
    ref.invalidate(lidarrQualityProfilesProvider);
    setState(() {
      _disconnecting = false;
      _currentUrl = null;
      _urlCtrl.clear();
      _keyCtrl.clear();
      _selectedRootFolder = null;
      _selectedQualityProfile = null;
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
    final apiKey = _keyCtrl.text.trim();
    final storage = ref.read(secureStorageProvider);

    final effectiveKey = apiKey.isNotEmpty
        ? apiKey
        : (await storage.read(key: 'lidarr_api_key') ?? '');

    try {
      final client = LidarrClient(baseUrl: url, apiKey: effectiveKey);
      final ok = await client.testConnection();
      if (!ok) throw Exception('Server returned non-ok status');

      await storage.write(key: 'lidarr_url', value: url);
      if (apiKey.isNotEmpty) {
        await storage.write(key: 'lidarr_api_key', value: apiKey);
      }

      if (!mounted) return;
      ref.invalidate(lidarrCredentialsProvider);
      ref.invalidate(lidarrRootFoldersProvider);
      ref.invalidate(lidarrQualityProfilesProvider);
      setState(() {
        _currentUrl = url;
        _saving = false;
        _keyCtrl.clear();
        _errorMessage = null;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _errorMessage = 'Connection failed: $e';
        });
      }
    }
  }

  Future<void> _savePickerSelections() async {
    final storage = ref.read(secureStorageProvider);
    final rf = _selectedRootFolder;
    final qp = _selectedQualityProfile;
    if (rf != null) {
      await storage.write(
          key: 'lidarr_root_folder_id', value: rf.id.toString());
      await storage.write(key: 'lidarr_root_folder_path', value: rf.path);
    }
    if (qp != null) {
      await storage.write(
          key: 'lidarr_quality_profile_id', value: qp.id.toString());
      await storage.write(
          key: 'lidarr_quality_profile_name', value: qp.name);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isConnected = _currentUrl != null;
    final rootFolders = ref.watch(lidarrRootFoldersProvider);
    final qualityProfiles = ref.watch(lidarrQualityProfilesProvider);

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(32, 32, 32, AppConstants.scrollBottomInset),
          children: [
            if (isConnected) ...[
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.08),
                  border:
                      Border.all(color: Colors.green.withValues(alpha: 0.3)),
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
                        style:
                            const TextStyle(fontSize: 12, color: Colors.green),
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
                'Connect to Lidarr',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: ColorTokens.textPrimary,
                ),
              ),

            const SizedBox(height: 32),

            Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Field(
                    controller: _urlCtrl,
                    label: 'Lidarr URL',
                    hint: 'http://localhost:8686',
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return 'Required';
                      final uri = Uri.tryParse(v.trim());
                      if (uri == null || !uri.hasScheme) {
                        return 'Enter a valid URL (http://...)';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _keyCtrl,
                    obscureText: _obscureKey,
                    style: const TextStyle(color: ColorTokens.textPrimary),
                    decoration: InputDecoration(
                      labelText: isConnected
                          ? 'New API Key (leave blank to keep current)'
                          : 'API Key',
                      labelStyle:
                          const TextStyle(color: ColorTokens.textSecondary),
                      filled: true,
                      fillColor: ColorTokens.surfaceVariant,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide:
                            const BorderSide(color: ColorTokens.divider),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide:
                            const BorderSide(color: ColorTokens.glassBorder),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(
                            color: ColorTokens.accent, width: 1.5),
                      ),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscureKey
                              ? Icons.visibility_off
                              : Icons.visibility,
                          color: ColorTokens.textSecondary,
                        ),
                        onPressed: () =>
                            setState(() => _obscureKey = !_obscureKey),
                      ),
                    ),
                    validator: (v) =>
                        (!isConnected && (v == null || v.trim().isEmpty))
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
                            child:
                                CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(isConnected
                            ? 'Update Connection'
                            : 'Connect'),
                  ),
                ],
              ),
            ),

            if (isConnected) ...[
              const SizedBox(height: 32),
              const Divider(color: ColorTokens.glassBorder),
              const SizedBox(height: 24),
              const Text(
                'Default settings for new artists',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: ColorTokens.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'These are used when adding an artist from the library.',
                style:
                    TextStyle(fontSize: 11, color: ColorTokens.textSecondary),
              ),
              const SizedBox(height: 20),
              _PickerRow(
                label: 'Root folder',
                child: rootFolders.when(
                  loading: () => const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 1.5)),
                  error: (e, _) => Text('$e',
                      style: const TextStyle(
                          color: Colors.redAccent, fontSize: 11)),
                  data: (folders) => DropdownButton<LidarrRootFolder>(
                    value: folders.any((f) =>
                            f.id == _selectedRootFolder?.id)
                        ? _selectedRootFolder
                        : null,
                    hint: const Text('Select…',
                        style: TextStyle(
                            color: ColorTokens.textSecondary, fontSize: 13)),
                    dropdownColor: ColorTokens.surface,
                    style: const TextStyle(
                        color: ColorTokens.textPrimary, fontSize: 13),
                    underline: const SizedBox.shrink(),
                    items: folders
                        .map((f) => DropdownMenuItem(
                              value: f,
                              child: Text(f.path,
                                  style: const TextStyle(
                                      color: ColorTokens.textPrimary,
                                      fontSize: 13)),
                            ))
                        .toList(),
                    onChanged: (f) {
                      setState(() => _selectedRootFolder = f);
                      _savePickerSelections();
                    },
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _PickerRow(
                label: 'Quality profile',
                child: qualityProfiles.when(
                  loading: () => const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 1.5)),
                  error: (e, _) => Text('$e',
                      style: const TextStyle(
                          color: Colors.redAccent, fontSize: 11)),
                  data: (profiles) => DropdownButton<LidarrQualityProfile>(
                    value: profiles.any((p) =>
                            p.id == _selectedQualityProfile?.id)
                        ? _selectedQualityProfile
                        : null,
                    hint: const Text('Select…',
                        style: TextStyle(
                            color: ColorTokens.textSecondary, fontSize: 13)),
                    dropdownColor: ColorTokens.surface,
                    style: const TextStyle(
                        color: ColorTokens.textPrimary, fontSize: 13),
                    underline: const SizedBox.shrink(),
                    items: profiles
                        .map((p) => DropdownMenuItem(
                              value: p,
                              child: Text(p.name,
                                  style: const TextStyle(
                                      color: ColorTokens.textPrimary,
                                      fontSize: 13)),
                            ))
                        .toList(),
                    onChanged: (p) {
                      setState(() => _selectedQualityProfile = p);
                      _savePickerSelections();
                    },
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PickerRow extends StatelessWidget {
  const _PickerRow({required this.label, required this.child});
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 120,
          child: Text(
            label,
            style: const TextStyle(
                fontSize: 13, color: ColorTokens.textSecondary),
          ),
        ),
        const SizedBox(width: 8),
        child,
      ],
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
