import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:macos_window_utils/macos_window_utils.dart';

import '../../application/library/library_notifier.dart';
import '../../application/library/sidebar_state.dart';
import '../../application/library/starred_notifier.dart';
import '../../application/playback/scrobble_importer.dart';
import '../../application/providers/providers.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/color_tokens.dart';
import '../pages/albums/albums_page.dart';
import '../pages/artists/artists_page.dart';
import '../pages/device/device_page.dart';
import '../pages/genres/genres_page.dart';
import '../pages/lidarr/lidarr_page.dart';
import '../pages/playlists/playlists_page.dart';
import '../pages/search/search_page.dart';
import '../pages/settings/settings_page.dart';
import '../pages/setup/setup_page.dart';
import '../pages/songs/songs_page.dart';
import '../pages/spotify_import/spotify_import_page.dart';
import 'app_shortcuts.dart';
import 'bottom_bar/bottom_bar_widget.dart';
import 'sidebar/sidebar_widget.dart';

class AppShell extends ConsumerWidget {
  const AppShell({super.key});

  // Gap between floating cards and window edges / each other.
  static const double _m = 8.0;
  // Corner radius for floating cards.
  static const double _r = 12.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final creds = ref.watch(serverCredentialsProvider);

    ref.listen(connectedDevicesProvider, (_, next) {
      final devices = next.valueOrNull ?? [];
      final selected = ref.read(selectedDeviceProvider);

      if (selected != null) {
        final stillPresent = devices.any((d) => d.path == selected.path);
        if (!stillPresent) {
          ref.read(selectedDeviceProvider.notifier).state = null;
          // Navigate away so the sidebar doesn't orphan its selection highlight.
          if (ref.read(selectedSectionProvider) == SidebarSection.device) {
            ref.read(selectedSectionProvider.notifier).state =
                SidebarSection.recentlyAdded;
          }
        } else {
          // Refresh stored object so availableBytes etc. stay current.
          final fresh = devices.firstWhere((d) => d.path == selected.path);
          if (fresh != selected) {
            ref.read(selectedDeviceProvider.notifier).state = fresh;
          }
        }
      } else if (devices.length == 1) {
        ref.read(selectedDeviceProvider.notifier).state = devices.first;
      }

      // Best-effort scrobble-log import for newly mounted devices. The
      // listener internally de-dupes by path so a flapping mount doesn't
      // submit the same plays twice in a session.
      unawaited(
          ref.read(scrobbleImportListenerProvider).handle(devices));
    });

    if (creds.isLoading) {
      return const Scaffold(backgroundColor: ColorTokens.background);
    }

    if (creds.valueOrNull == null) {
      return const Scaffold(
        backgroundColor: ColorTokens.background,
        body: SetupPage(),
      );
    }

    const sW = AppConstants.sidebarWidth;
    const bH = AppConstants.bottomBarHeight;

    final stack = Stack(
      children: [
            // ── Main content ───────────────────────────────────────────────
            // Fills all the way to the window bottom so content flows behind
            // the floating bar naturally (bar overlays, not clips).
            Positioned(
              left: sW + _m * 2,
              right: 0,
              top: 0,
              bottom: 0,
              child: Material(
                color: ColorTokens.background,
                child: const _MainPanel(),
              ),
            ),

            // ── Floating sidebar — full height ─────────────────────────────
            Positioned(
              left: _m,
              top: _m,
              bottom: _m,
              width: sW,
              child: const _FloatingCard(
                radius: _r,
                child: SidebarWidget(),
              ),
            ),

            // ── Floating bottom bar — centered in the right area ───────────
            // Width is 65 % of the available space, clamped so all controls
            // always fit (the bar needs ~600 px minimum).
            Positioned(
              left: sW + _m * 2,
              right: _m,
              bottom: _m,
              height: bH,
              child: LayoutBuilder(
                builder: (_, constraints) {
                  final w =
                      (constraints.maxWidth * 0.65).clamp(620.0, 1000.0);
                  return Center(
                    child: SizedBox(
                      width: w,
                      child: const _FloatingCard(
                        radius: _r + 2,
                        child: BottomBarWidget(),
                      ),
                    ),
                  );
                },
              ),
            ),
      ],
    );
    final body = Platform.isMacOS ? TitlebarSafeArea(child: stack) : stack;
    return Scaffold(
      backgroundColor: ColorTokens.background,
      body: AppShortcuts(child: body),
    );
  }
}

// ── Floating card wrapper ─────────────────────────────────────────────────────

class _FloatingCard extends StatelessWidget {
  const _FloatingCard({required this.radius, required this.child});

  final double radius;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final br = BorderRadius.circular(radius);
    return DecoratedBox(
      // Background layer — shadow only, no fill (content provides its own bg).
      decoration: BoxDecoration(
        borderRadius: br,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.28),
            blurRadius: 18,
            spreadRadius: -2,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: DecoratedBox(
        // Foreground layer — glass border on top of content.
        decoration: BoxDecoration(
          borderRadius: br,
          border: Border.all(color: ColorTokens.glassBorder),
        ),
        position: DecorationPosition.foreground,
        child: ClipRRect(borderRadius: br, child: child),
      ),
    );
  }
}

// ── Main panel ────────────────────────────────────────────────────────────────

class _MainPanel extends ConsumerWidget {
  const _MainPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query = ref.watch(searchQueryProvider);
    final section = ref.watch(selectedSectionProvider);

    // Re-fetch library data whenever the user switches to a content tab.
    // FutureProviders keep old data visible via skipLoadingOnRefresh (default).
    // NotifierProviders keep old data because refresh() doesn't clear state.
    ref.listen(selectedSectionProvider, (prev, next) {
      if (prev == next) return;
      switch (next) {
        case SidebarSection.artists:
          ref.invalidate(artistsProvider);
          ref.invalidate(albumsByArtistProvider); // refresh all artist drill-downs
        case SidebarSection.recentlyAdded:
          ref.invalidate(recentAlbumsProvider);
        case SidebarSection.albums:
          ref.read(allAlbumsProvider.notifier).refresh();
        case SidebarSection.songs:
          ref.read(allSongsProvider.notifier).refresh();
          ref.invalidate(starredProvider); // pick up stars changed on other clients
        case SidebarSection.genres:
          ref.invalidate(genresProvider);
        default:
          break;
      }
    });

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
              SidebarSection.genres => const GenresPage(),
              SidebarSection.playlists => const PlaylistsPage(),
              SidebarSection.spotifyImport => const SpotifyImportPage(),
              SidebarSection.lidarr => const LidarrPage(),
              SidebarSection.device => const DevicePage(),
              SidebarSection.settings => const SettingsPage(),
            },
    );
  }
}
