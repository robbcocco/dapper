import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../application/library/library_notifier.dart';
import '../../../application/library/playlist_actions_notifier.dart';
import '../../../application/library/sidebar_state.dart';
import '../../../application/providers/providers.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/color_tokens.dart';
import '../../../domain/models/connected_device.dart';

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
    // Sync text field when the query is cleared from outside (e.g., search result nav).
    ref.listen(searchQueryProvider, (_, next) {
      if (next.isEmpty && _ctrl.text.isNotEmpty) {
        _ctrl.clear();
        setState(() {});
      }
    });

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
      child: SizedBox(
        height: 28,
        child: TextField(
          controller: _ctrl,
          style: const TextStyle(fontSize: 12, color: ColorTokens.textPrimary),
          decoration: InputDecoration(
            hintText: 'Search…',
            hintStyle: const TextStyle(
                fontSize: 12, color: ColorTokens.textSecondary),
            prefixIcon: const Icon(Icons.search,
                size: 14, color: ColorTokens.textSecondary),
            prefixIconConstraints:
                const BoxConstraints(minWidth: 28, minHeight: 28),
            suffixIcon: _ctrl.text.isNotEmpty
                ? GestureDetector(
                    onTap: () {
                      _ctrl.clear();
                      ref.read(searchQueryProvider.notifier).state = '';
                      setState(() {});
                    },
                    child: const Icon(Icons.close,
                        size: 12, color: ColorTokens.textSecondary),
                  )
                : null,
            suffixIconConstraints:
                const BoxConstraints(minWidth: 24, minHeight: 24),
            filled: true,
            fillColor: ColorTokens.surfaceVariant,
            contentPadding: EdgeInsets.zero,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: BorderSide.none,
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

class SidebarWidget extends ConsumerWidget {
  const SidebarWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(selectedSectionProvider);
    final playlists = ref.watch(playlistsProvider);
    final device = ref.watch(selectedDeviceProvider);
    final devices = ref.watch(connectedDevicesProvider).valueOrNull ?? [];

    return Container(
      width: AppConstants.sidebarWidth,
      color: ColorTokens.sidebar,
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          const _SearchBar(),
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
            error: (err, st) => const SizedBox.shrink(),
          ),
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
          const Divider(height: 32),
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
            hintStyle:
                const TextStyle(color: ColorTokens.textSecondary),
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
      ref
          .read(playlistActionsProvider.notifier)
          .createPlaylist(name.trim());
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
      onTap: onTap ?? () {
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
              color: isSelected
                  ? ColorTokens.accent
                  : ColorTokens.textSecondary,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: isSelected
                    ? ColorTokens.textPrimary
                    : ColorTokens.textSecondary,
                fontWeight:
                    isSelected ? FontWeight.w500 : FontWeight.normal,
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
            const Icon(Icons.queue_music, size: 14, color: ColorTokens.textSecondary),
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
              Icons.usb,
              size: 16,
              color: isSelected ? ColorTokens.accent : ColorTokens.textSecondary,
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
          ],
        ),
      ),
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
