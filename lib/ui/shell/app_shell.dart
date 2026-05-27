import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/library/sidebar_state.dart';
import '../../application/providers/providers.dart';
import '../pages/albums/albums_page.dart';
import '../pages/artists/artists_page.dart';
import '../pages/device/device_page.dart';
import '../pages/playlists/playlists_page.dart';
import '../pages/search/search_page.dart';
import '../pages/settings/settings_page.dart';
import '../pages/songs/songs_page.dart';
import 'bottom_bar/bottom_bar_widget.dart';
import 'sidebar/sidebar_widget.dart';

class AppShell extends ConsumerWidget {
  const AppShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final creds = ref.watch(serverCredentialsProvider);

    // Clear stale device selection when a device is disconnected.
    ref.listen(connectedDevicesProvider, (_, next) {
      final devices = next.valueOrNull ?? [];
      final selected = ref.read(selectedDeviceProvider);
      if (selected != null && !devices.any((d) => d.path == selected.path)) {
        ref.read(selectedDeviceProvider.notifier).state = null;
      }
    });

    if (creds.valueOrNull == null) {
      return const Scaffold(body: SettingsPage());
    }

    return Scaffold(
      body: Column(
        children: [
          Expanded(
            child: Row(
              children: [
                const SidebarWidget(),
                const VerticalDivider(width: 1),
                Expanded(child: _MainPanel()),
              ],
            ),
          ),
          const BottomBarWidget(),
        ],
      ),
    );
  }
}

class _MainPanel extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query = ref.watch(searchQueryProvider);
    final section = ref.watch(selectedSectionProvider);

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 150),
      child: query.isNotEmpty
          ? const SearchPage()
          : switch (section) {
              SidebarSection.recentlyAdded =>
                const AlbumsPage(mode: AlbumsPageMode.recent),
              SidebarSection.artists => const ArtistsPage(),
              SidebarSection.albums =>
                const AlbumsPage(mode: AlbumsPageMode.all),
              SidebarSection.songs => const SongsPage(),
              SidebarSection.playlists => const PlaylistsPage(),
              SidebarSection.device => const DevicePage(),
              SidebarSection.settings => const SettingsPage(),
            },
    );
  }
}
