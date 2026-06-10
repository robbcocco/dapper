import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../application/lidarr/lidarr_notifier.dart';
import '../../../application/providers/providers.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/color_tokens.dart';
import '../../../domain/models/device_settings.dart';
import '../../../domain/models/lidarr_models.dart';
import '../../../domain/models/lidarr_instance.dart';
import '../../../domain/models/navidrome_server.dart';
import '../device/device_settings_dialog.dart';
import 'lidarr_form_dialog.dart';
import 'server_form_dialog.dart';

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
    _tabController = TabController(length: 4, vsync: this);
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
              Tab(text: 'General'),
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
              _GeneralTab(),
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

// ── General tab ───────────────────────────────────────────────────────────────

class _GeneralTab extends ConsumerWidget {
  const _GeneralTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider);

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, AppConstants.scrollBottomInset),
      children: [
        const Text(
          'Transfer',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: ColorTokens.textPrimary,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Controls how many songs are downloaded simultaneously to a device.',
          style: TextStyle(fontSize: 11, color: ColorTokens.textSecondary),
        ),
        const SizedBox(height: 16),
        _PickerRow(
          label: 'Parallel downloads',
          child: SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 1, label: Text('1')),
              ButtonSegment(value: 2, label: Text('2')),
              ButtonSegment(value: 3, label: Text('3')),
              ButtonSegment(value: 4, label: Text('4')),
            ],
            selected: {settings.transferConcurrency},
            onSelectionChanged: (s) => ref
                .read(appSettingsProvider.notifier)
                .setTransferConcurrency(s.first),
            style: ButtonStyle(
              textStyle: WidgetStateProperty.all(
                  const TextStyle(fontSize: 12)),
              visualDensity: VisualDensity.compact,
            ),
          ),
        ),
        const SizedBox(height: 40),
        const Divider(color: ColorTokens.glassBorder),
        const SizedBox(height: 20),
        const Text(
          'Reset',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: ColorTokens.textPrimary,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Clears all servers, credentials, device settings, and app data. '
          'The app will return to the setup screen.',
          style: TextStyle(fontSize: 11, color: ColorTokens.textSecondary),
        ),
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton(
            onPressed: () => _confirmReset(context, ref),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.redAccent,
              side: const BorderSide(color: Colors.redAccent),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
            child: const Text('Reset all data', style: TextStyle(fontSize: 13)),
          ),
        ),
      ],
    );
  }

  Future<void> _confirmReset(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: ColorTokens.surface,
        title: const Text('Reset all data',
            style: TextStyle(color: ColorTokens.textPrimary, fontSize: 16)),
        content: const Text(
          'This will remove all servers, credentials, device settings, '
          'and cached data. The app will return to the setup screen.\n\n'
          'This cannot be undone.',
          style: TextStyle(fontSize: 13, color: ColorTokens.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel',
                style: TextStyle(color: ColorTokens.textSecondary)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    final supportDir = ref.read(appSupportDirProvider);

    // Close and wipe the database.
    await ref.read(appDatabaseProvider).close();
    ref.invalidate(appDatabaseProvider);
    _tryDelete(p.join(supportDir, 'dapper.db'));
    _tryDelete(p.join(supportDir, 'dapper.db-shm'));
    _tryDelete(p.join(supportDir, 'dapper.db-wal'));

    // Wipe persisted JSON files.
    _tryDelete(p.join(supportDir, 'app_settings.json'));
    _tryDelete(p.join(supportDir, 'transfer_queue.json'));

    // Wipe all stored credentials (server passwords + selected IDs). Goes
    // through the fallback store so both keychain and file backends are
    // cleared in one shot.
    await ref.read(secureStorageProvider).deleteAll();

    // Invalidate in-memory provider state so everything reloads from scratch.
    ref.invalidate(serversProvider);
    ref.invalidate(selectedServerIdProvider);
    ref.invalidate(lidarrInstancesProvider);
    ref.invalidate(selectedLidarrInstanceIdProvider);
    ref.invalidate(appSettingsProvider);
    ref.invalidate(allStoredDeviceSettingsProvider);
    // serverCredentialsProvider will become null → AppShell shows SetupPage.
  }

  void _tryDelete(String path) {
    try {
      final f = File(path);
      if (f.existsSync()) f.deleteSync();
    } catch (_) {}
  }
}

// ── Navidrome tab ─────────────────────────────────────────────────────────────

class _NavidromeTab extends ConsumerWidget {
  const _NavidromeTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final servers = ref.watch(serversProvider);
    final activeServer = ref.watch(selectedServerProvider);

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, AppConstants.scrollBottomInset),
      children: [
        Row(
          children: [
            const Text(
              'Navidrome Servers',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: ColorTokens.textPrimary,
              ),
            ),
            const Spacer(),
            FilledButton.icon(
              onPressed: () => showServerFormDialog(context),
              icon: const Icon(Icons.add, size: 14),
              label: const Text('Add Server', style: TextStyle(fontSize: 13)),
              style: FilledButton.styleFrom(
                backgroundColor: ColorTokens.accent,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (servers.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 48),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: const [
                Icon(Icons.dns_outlined, size: 40, color: ColorTokens.textSecondary),
                SizedBox(height: 12),
                Text('No servers configured',
                    style: TextStyle(fontSize: 14, color: ColorTokens.textSecondary)),
                SizedBox(height: 6),
                Text('Add a Navidrome server to get started',
                    style: TextStyle(fontSize: 11, color: ColorTokens.textSecondary)),
              ],
            ),
          )
        else
          ...servers.map((s) => _ServerTile(
                server: s,
                isActive: s.id == activeServer?.id,
              )),
      ],
    );
  }
}

class _ServerTile extends ConsumerWidget {
  const _ServerTile({required this.server, required this.isActive});
  final NavidromeServer server;
  final bool isActive;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isActive
            ? ColorTokens.accent.withValues(alpha: 0.08)
            : ColorTokens.surfaceVariant,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isActive
              ? ColorTokens.accent.withValues(alpha: 0.3)
              : ColorTokens.glassBorder,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      server.name,
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: ColorTokens.textPrimary),
                    ),
                    if (isActive) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.green.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text('Active',
                            style: TextStyle(fontSize: 10, color: Colors.green)),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  server.url,
                  style: const TextStyle(
                      fontSize: 11, color: ColorTokens.textSecondary),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  server.username,
                  style: const TextStyle(
                      fontSize: 11, color: ColorTokens.textSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (!isActive)
            TextButton(
              onPressed: () =>
                  ref.read(selectedServerIdProvider.notifier).select(server.id),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                minimumSize: Size.zero,
              ),
              child: const Text('Connect',
                  style: TextStyle(fontSize: 12, color: ColorTokens.accent)),
            ),
          IconButton(
            icon: const Icon(Icons.edit_outlined,
                size: 14, color: ColorTokens.textSecondary),
            tooltip: 'Edit',
            onPressed: () => showServerFormDialog(context, existing: server),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline,
                size: 14, color: ColorTokens.textSecondary),
            tooltip: 'Remove',
            onPressed: () => _confirmDelete(context, ref),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: ColorTokens.surface,
        title: const Text('Remove Server',
            style: TextStyle(color: ColorTokens.textPrimary, fontSize: 16)),
        content: Text(
          'Remove "${server.name}"? This cannot be undone.',
          style: const TextStyle(
              fontSize: 13, color: ColorTokens.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel',
                style: TextStyle(color: ColorTokens.textSecondary)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok == true) {
      unawaited(ref.read(serversProvider.notifier).remove(server.id));
    }
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
        FolderStructure.custom => 'Custom',
      };
}


// ── Lidarr tab ────────────────────────────────────────────────────────────────

class _LidarrTab extends ConsumerWidget {
  const _LidarrTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final instances = ref.watch(lidarrInstancesProvider);
    final active = ref.watch(selectedLidarrInstanceProvider);

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, AppConstants.scrollBottomInset),
      children: [
        Row(
          children: [
            const Text(
              'Lidarr Instances',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: ColorTokens.textPrimary,
              ),
            ),
            const Spacer(),
            FilledButton.icon(
              onPressed: () => showLidarrFormDialog(context),
              icon: const Icon(Icons.add, size: 14),
              label: const Text('Add Instance', style: TextStyle(fontSize: 13)),
              style: FilledButton.styleFrom(
                backgroundColor: ColorTokens.accent,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (instances.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 48),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: const [
                Icon(Icons.album_outlined, size: 40, color: ColorTokens.textSecondary),
                SizedBox(height: 12),
                Text('No Lidarr instances configured',
                    style: TextStyle(fontSize: 14, color: ColorTokens.textSecondary)),
                SizedBox(height: 6),
                Text('Add a Lidarr instance to enable download management',
                    style: TextStyle(fontSize: 11, color: ColorTokens.textSecondary)),
              ],
            ),
          )
        else
          ...instances.map((i) => _LidarrInstanceTile(
                instance: i,
                isActive: i.id == active?.id,
              )),
        if (active != null) ...[
          const SizedBox(height: 24),
          const Divider(color: ColorTokens.glassBorder),
          const SizedBox(height: 16),
          const Text(
            'Default settings for new artists',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: ColorTokens.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Used when adding an artist from the library via ${active.name}.',
            style: const TextStyle(fontSize: 11, color: ColorTokens.textSecondary),
          ),
          const SizedBox(height: 20),
          _DefaultsPickers(active: active),
        ],
      ],
    );
  }
}

class _LidarrInstanceTile extends ConsumerWidget {
  const _LidarrInstanceTile({required this.instance, required this.isActive});
  final LidarrInstance instance;
  final bool isActive;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isActive
            ? ColorTokens.accent.withValues(alpha: 0.08)
            : ColorTokens.surfaceVariant,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isActive
              ? ColorTokens.accent.withValues(alpha: 0.3)
              : ColorTokens.glassBorder,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      instance.name,
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: ColorTokens.textPrimary),
                    ),
                    if (isActive) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.green.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text('Active',
                            style: TextStyle(fontSize: 10, color: Colors.green)),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  instance.url,
                  style: const TextStyle(
                      fontSize: 11, color: ColorTokens.textSecondary),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (!isActive)
            TextButton(
              onPressed: () => ref
                  .read(selectedLidarrInstanceIdProvider.notifier)
                  .select(instance.id),
              style: TextButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                minimumSize: Size.zero,
              ),
              child: const Text('Connect',
                  style: TextStyle(fontSize: 12, color: ColorTokens.accent)),
            ),
          IconButton(
            icon: const Icon(Icons.edit_outlined,
                size: 14, color: ColorTokens.textSecondary),
            tooltip: 'Edit',
            onPressed: () => showLidarrFormDialog(context, existing: instance),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline,
                size: 14, color: ColorTokens.textSecondary),
            tooltip: 'Remove',
            onPressed: () => _confirmDelete(context, ref),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: ColorTokens.surface,
        title: const Text('Remove Instance',
            style: TextStyle(color: ColorTokens.textPrimary, fontSize: 16)),
        content: Text(
          'Remove "${instance.name}"? This cannot be undone.',
          style: const TextStyle(
              fontSize: 13, color: ColorTokens.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel',
                style: TextStyle(color: ColorTokens.textSecondary)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok == true) {
      unawaited(
          ref.read(lidarrInstancesProvider.notifier).remove(instance.id));
    }
  }
}

class _DefaultsPickers extends ConsumerWidget {
  const _DefaultsPickers({required this.active});
  final LidarrInstance active;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rootFolders = ref.watch(lidarrRootFoldersProvider);
    final qualityProfiles = ref.watch(lidarrQualityProfilesProvider);

    return Column(
      children: [
        _PickerRow(
          label: 'Root folder',
          child: rootFolders.when(
            loading: () => const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 1.5)),
            error: (e, _) => Text('$e',
                style:
                    const TextStyle(color: Colors.redAccent, fontSize: 11)),
            data: (folders) => DropdownButton<LidarrRootFolder>(
              value: folders
                  .where((f) => f.id == active.defaultRootFolderId)
                  .firstOrNull,
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
                                color: ColorTokens.textPrimary, fontSize: 13)),
                      ))
                  .toList(),
              onChanged: (f) {
                if (f == null) return;
                ref.read(lidarrInstancesProvider.notifier).update(
                      active.copyWith(
                        defaultRootFolderId: f.id,
                        defaultRootFolderPath: f.path,
                      ),
                    );
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
                style:
                    const TextStyle(color: Colors.redAccent, fontSize: 11)),
            data: (profiles) => DropdownButton<LidarrQualityProfile>(
              value: profiles
                  .where((p) => p.id == active.defaultQualityProfileId)
                  .firstOrNull,
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
                                color: ColorTokens.textPrimary, fontSize: 13)),
                      ))
                  .toList(),
              onChanged: (p) {
                if (p == null) return;
                ref.read(lidarrInstancesProvider.notifier).update(
                      active.copyWith(
                        defaultQualityProfileId: p.id,
                        defaultQualityProfileName: p.name,
                      ),
                    );
              },
            ),
          ),
        ),
      ],
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


