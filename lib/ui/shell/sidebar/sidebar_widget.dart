import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:macos_window_utils/macos_window_utils.dart';
import 'package:macos_window_utils/widgets/transparent_macos_sidebar.dart';

import '../../../application/library/library_notifier.dart';
import '../../../application/library/playlist_actions_notifier.dart';
import '../../../application/library/search_focus.dart';
import '../../../application/library/sidebar_state.dart';
import '../../../application/providers/providers.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/color_tokens.dart';
import '../../../domain/models/connected_device.dart';
import '../../../domain/models/navidrome_server.dart';
import '../../../platform/device_fs.dart';
import '../../widgets/device_eject.dart';

class _SearchBar extends ConsumerStatefulWidget {
  const _SearchBar();

  @override
  ConsumerState<_SearchBar> createState() => _SearchBarState();
}

class _SearchBarState extends ConsumerState<_SearchBar> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(searchQueryProvider, (_, next) {
      if (next.isEmpty && _ctrl.text.isNotEmpty) {
        _ctrl.clear();
        setState(() {});
      }
    });

    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
      child: SizedBox(
        height: 26,
        child: TextField(
          controller: _ctrl,
          focusNode: ref.watch(searchFocusProvider),
          style: const TextStyle(fontSize: 12, color: ColorTokens.textPrimary),
          decoration: InputDecoration(
            hintText: 'Search…',
            hintStyle: const TextStyle(
                fontSize: 12, color: ColorTokens.textSecondary),
            prefixIcon: const Icon(Icons.search,
                size: 13, color: ColorTokens.textSecondary),
            prefixIconConstraints:
                const BoxConstraints(minWidth: 28, minHeight: 26),
            suffixIcon: _ctrl.text.isNotEmpty
                ? GestureDetector(
                    onTap: () {
                      _ctrl.clear();
                      ref.read(searchQueryProvider.notifier).state = '';
                      setState(() {});
                    },
                    child: const Icon(Icons.close,
                        size: 11, color: ColorTokens.textSecondary),
                  )
                : null,
            suffixIconConstraints:
                const BoxConstraints(minWidth: 24, minHeight: 24),
            filled: true,
            fillColor: ColorTokens.surfaceVariant.withValues(alpha: 0.65),
            contentPadding: EdgeInsets.zero,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(
                  color: ColorTokens.accent.withValues(alpha: 0.4), width: 1),
            ),
          ),
          onChanged: (v) {
            setState(() {});
            ref.read(searchQueryProvider.notifier).state = v;
          },
        ),
      ),
    );
  }
}

// ── Native vibrancy sidebar ───────────────────────────────────────────────────

class SidebarWidget extends StatelessWidget {
  const SidebarWidget({super.key});

  @override
  Widget build(BuildContext context) {
    if (Platform.isMacOS) {
      return const TransparentMacOSSidebar(
        material: NSVisualEffectViewMaterial.sidebar,
        state: NSVisualEffectViewState.active,
        child: _SidebarContent(),
      );
    }
    return const _SidebarContent();
  }
}

class _SidebarContent extends ConsumerWidget {
  const _SidebarContent();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(selectedSectionProvider);
    final playlists = ref.watch(playlistsProvider);
    final device = ref.watch(selectedDeviceProvider);
    final devices = ref.watch(connectedDevicesProvider).valueOrNull ?? [];
    return Container(
      width: AppConstants.sidebarWidth,
      color: ColorTokens.sidebarOverlay,
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          const _SearchBar(),
          const _ServerSwitcherHeader(),
          _SectionHeader('LIBRARY'),
          _SidebarTile(
            icon: Icons.album_outlined,
            label: 'Recently Added',
            section: SidebarSection.recentlyAdded,
            selected: selected,
            ref: ref,
          ),
          _SidebarTile(
            icon: Icons.person_outline,
            label: 'Artists',
            section: SidebarSection.artists,
            selected: selected,
            ref: ref,
          ),
          _SidebarTile(
            icon: Icons.library_music_outlined,
            label: 'Albums',
            section: SidebarSection.albums,
            selected: selected,
            ref: ref,
            onTap: () {
              ref.read(selectedSectionProvider.notifier).state =
                  SidebarSection.albums;
              ref.read(selectedArtistIdProvider.notifier).state = null;
              ref.read(selectedAlbumIdProvider.notifier).state = null;
            },
          ),
          _SidebarTile(
            icon: Icons.music_note_outlined,
            label: 'Songs',
            section: SidebarSection.songs,
            selected: selected,
            ref: ref,
          ),
          _SidebarTile(
            icon: Icons.category_outlined,
            label: 'Genres',
            section: SidebarSection.genres,
            selected: selected,
            ref: ref,
            onTap: () {
              ref.read(searchQueryProvider.notifier).state = '';
              ref.read(selectedSectionProvider.notifier).state =
                  SidebarSection.genres;
              // Clearing the drill-down state ensures we land on the genre
              // list rather than a stale album from another section.
              ref.read(selectedAlbumIdProvider.notifier).state = null;
              ref.read(selectedGenreProvider.notifier).state = null;
            },
          ),
          const SizedBox(height: 16),
          _PlaylistsSectionHeader(ref: ref),
          playlists.when(
            data: (list) => Column(
              children: list
                  .map((p) => _PlaylistTile(
                        label: p.name,
                        playlistId: p.id,
                        selected: selected,
                        ref: ref,
                      ))
                  .toList(),
            ),
            loading: () => const Padding(
              padding: EdgeInsets.all(16),
              child: LinearProgressIndicator(),
            ),
            error: (_, __) => const SizedBox.shrink(),
          ),
          const SizedBox(height: 16),
          _LidarrSectionHeader(selected: selected, ref: ref),
          const SizedBox(height: 16),
          _SectionHeader('DEVICE'),
          if (devices.isEmpty)
            const _NoDeviceTile()
          else
            ...devices.map((d) => _DeviceItemTile(
                  device: d,
                  isSelected: selected == SidebarSection.device &&
                      device?.path == d.path,
                  ref: ref,
                )),
          const Divider(height: 32, color: ColorTokens.glassBorder),
          _SidebarTile(
            icon: Icons.settings_outlined,
            label: 'Settings',
            section: SidebarSection.settings,
            selected: selected,
            ref: ref,
          ),
        ],
      ),
    );
  }
}

class _ServerSwitcherHeader extends ConsumerWidget {
  const _ServerSwitcherHeader();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final servers = ref.watch(serversProvider);
    final active = ref.watch(selectedServerProvider);

    if (servers.isEmpty) return const SizedBox.shrink();

    return GestureDetector(
      onTapDown: (details) => _showMenu(context, ref, details.globalPosition, servers, active),
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        margin: const EdgeInsets.fromLTRB(8, 4, 8, 0),
        child: Row(
          children: [
            const Icon(Icons.dns_outlined, size: 13, color: ColorTokens.textSecondary),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                active?.name ?? 'No Server',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: active != null
                      ? ColorTokens.textPrimary
                      : ColorTokens.textSecondary,
                ),
              ),
            ),
            const Icon(Icons.unfold_more, size: 12, color: ColorTokens.textSecondary),
          ],
        ),
      ),
    );
  }

  void _showMenu(
    BuildContext context,
    WidgetRef ref,
    Offset position,
    List<NavidromeServer> servers,
    NavidromeServer? active,
  ) async {
    final items = <PopupMenuEntry<String>>[
      for (final s in servers)
        PopupMenuItem<String>(
          value: s.id,
          child: Row(
            children: [
              if (s.id == active?.id)
                const Icon(Icons.check, size: 13, color: ColorTokens.accent)
              else
                const SizedBox(width: 13),
              const SizedBox(width: 8),
              Text(s.name,
                  style: TextStyle(
                    fontSize: 13,
                    color: s.id == active?.id
                        ? ColorTokens.accent
                        : ColorTokens.textPrimary,
                  )),
            ],
          ),
        ),
    ];

    final result = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
          position.dx, position.dy, position.dx, position.dy),
      color: ColorTokens.surface,
      items: items,
    );

    if (result != null && result != active?.id) {
      unawaited(ref.read(selectedServerIdProvider.notifier).select(result));
    }
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: ColorTokens.textSecondary,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

class _PlaylistsSectionHeader extends ConsumerWidget {
  const _PlaylistsSectionHeader({required this.ref});
  final WidgetRef ref;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 4),
      child: Row(
        children: [
          const Expanded(
            child: Text(
              'PLAYLISTS',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: ColorTokens.textSecondary,
                letterSpacing: 0.8,
              ),
            ),
          ),
          GestureDetector(
            onTap: () => _createPlaylist(context, ref),
            child: const Icon(Icons.add,
                size: 14, color: ColorTokens.textSecondary),
          ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }

  void _createPlaylist(BuildContext context, WidgetRef ref) async {
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: ColorTokens.surface,
        title: const Text('New Playlist',
            style: TextStyle(color: ColorTokens.textPrimary)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: const TextStyle(color: ColorTokens.textPrimary),
          decoration: InputDecoration(
            hintText: 'Playlist name',
            hintStyle: const TextStyle(color: ColorTokens.textSecondary),
            filled: true,
            fillColor: ColorTokens.surfaceVariant,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide.none,
            ),
          ),
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(context, ctrl.text),
            style:
                FilledButton.styleFrom(backgroundColor: ColorTokens.accent),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    if (name != null && name.trim().isNotEmpty) {
      unawaited(ref
          .read(playlistActionsProvider.notifier)
          .createPlaylist(name.trim()));
    }
  }
}

class _SidebarTile extends StatelessWidget {
  const _SidebarTile({
    required this.icon,
    required this.label,
    required this.section,
    required this.selected,
    required this.ref,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final SidebarSection section;
  final SidebarSection selected;
  final WidgetRef ref;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final isSelected = selected == section;
    return InkWell(
      onTap: onTap ??
          () {
            ref.read(searchQueryProvider.notifier).state = '';
            ref.read(selectedSectionProvider.notifier).state = section;
          },
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: isSelected
            ? BoxDecoration(
                color: ColorTokens.selectionBackground,
                borderRadius: BorderRadius.circular(6),
              )
            : null,
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
        child: Row(
          children: [
            Icon(
              icon,
              size: 16,
              color:
                  isSelected ? ColorTokens.accent : ColorTokens.textSecondary,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: isSelected
                    ? ColorTokens.textPrimary
                    : ColorTokens.textSecondary,
                fontWeight: isSelected ? FontWeight.w500 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlaylistTile extends StatelessWidget {
  const _PlaylistTile({
    required this.label,
    required this.playlistId,
    required this.selected,
    required this.ref,
  });

  final String label;
  final String playlistId;
  final SidebarSection selected;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    final isSelected = selected == SidebarSection.playlists &&
        ref.read(selectedPlaylistIdProvider) == playlistId;
    return InkWell(
      onTap: () {
        ref.read(searchQueryProvider.notifier).state = '';
        ref.read(selectedPlaylistIdProvider.notifier).state = playlistId;
        ref.read(selectedSectionProvider.notifier).state =
            SidebarSection.playlists;
      },
      child: Container(
        height: 28,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
        decoration: isSelected
            ? BoxDecoration(
                color: ColorTokens.selectionBackground,
                borderRadius: BorderRadius.circular(6),
              )
            : null,
        child: Row(
          children: [
            const Icon(Icons.queue_music,
                size: 14, color: ColorTokens.textSecondary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  color: isSelected
                      ? ColorTokens.textPrimary
                      : ColorTokens.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DeviceItemTile extends StatelessWidget {
  const _DeviceItemTile({
    required this.device,
    required this.isSelected,
    required this.ref,
  });

  final ConnectedDevice device;
  final bool isSelected;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {
        ref.read(searchQueryProvider.notifier).state = '';
        ref.read(selectedDeviceProvider.notifier).state = device;
        ref.read(selectedSectionProvider.notifier).state = SidebarSection.device;
      },
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
        decoration: isSelected
            ? BoxDecoration(
                color: ColorTokens.selectionBackground,
                borderRadius: BorderRadius.circular(6),
              )
            : null,
        child: Row(
          children: [
            Icon(
              device.protocol == DeviceProtocol.mtp
                  ? Icons.phone_android
                  : Icons.usb,
              size: 16,
              color:
                  isSelected ? ColorTokens.accent : ColorTokens.textSecondary,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                device.label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  color: isSelected
                      ? ColorTokens.textPrimary
                      : ColorTokens.textSecondary,
                  fontWeight: isSelected ? FontWeight.w500 : FontWeight.normal,
                ),
              ),
            ),
            // Eject button. Tap is consumed here so the InkWell row tap
            // (which selects the device) doesn't also fire.
            InkWell(
              borderRadius: BorderRadius.circular(4),
              onTap: () => ejectConnectedDevice(context, ref, device.path),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(
                  Icons.eject_outlined,
                  size: 14,
                  color: isSelected
                      ? ColorTokens.textPrimary
                      : ColorTokens.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LidarrSectionHeader extends ConsumerWidget {
  const _LidarrSectionHeader({required this.selected, required this.ref});
  final SidebarSection selected;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final instance = ref.watch(selectedLidarrInstanceProvider);
    if (instance == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader('LIDARR'),
        _SidebarTile(
          icon: Icons.queue_music_outlined,
          label: instance.name,
          section: SidebarSection.lidarr,
          selected: selected,
          ref: ref,
        ),
      ],
    );
  }
}

class _NoDeviceTile extends StatelessWidget {
  const _NoDeviceTile();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      child: Row(
        children: [
          Icon(
            Icons.usb_off_outlined,
            size: 16,
            color: ColorTokens.textSecondary.withValues(alpha: 0.4),
          ),
          const SizedBox(width: 8),
          Text(
            'No device',
            style: TextStyle(
              fontSize: 13,
              color: ColorTokens.textSecondary.withValues(alpha: 0.4),
            ),
          ),
        ],
      ),
    );
  }
}
