# Dapper — Claude Code Guide

A cross-platform Flutter desktop app (macOS + Windows) that connects to a Navidrome server via the Subsonic REST API, browses the music library, and transfers music files to connected USB devices (SD cards, DAPs). UI is iTunes-inspired: sidebar + main grid + bottom player/status bar.

## Build & run

Flutter binary lives at `/opt/homebrew/bin/flutter` (3.44.x via Homebrew cask).

```bash
flutter pub get
flutter run -d macos                       # dev (macOS)
flutter run -d windows                     # dev (Windows)
flutter build macos --debug                # build (macOS, debug)
flutter build macos --release              # build (macOS, release)
flutter build windows --release            # build (Windows, release)
flutter analyze                            # lint + type check
flutter test                               # run tests
```

**Code generation** (must re-run after any `@freezed`, `@JsonSerializable`, or Drift table change):

```bash
flutter pub run build_runner build --delete-conflicting-outputs
# or, while iterating:
flutter pub run build_runner watch --delete-conflicting-outputs
```

Forgetting this produces "part ... was not found" errors. Generated files (`*.freezed.dart`, `*.g.dart`) are committed.

macOS-specific prerequisites (first build only):

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -license accept
```

## Architecture

Four-layer Riverpod app with a clear data flow: **UI → application (notifiers) → domain (models/contracts) → data (repositories → API/DB)**.

### Directory layout

- [lib/main.dart](lib/main.dart) — entry. Initializes `WindowManipulator` (macOS vibrancy), `windowManager`, and overrides `appSupportDirProvider` from `getApplicationSupportDirectory()`.
- [lib/application/](lib/application/) — Riverpod notifiers and derived state.
  - [providers/providers.dart](lib/application/providers/providers.dart) — central provider hub (~30 providers). Read this first.
  - `library/`, `transfer/`, `device/`, `playback/`, `settings/`, `lidarr/` — one folder per feature; each holds its notifier(s) and supporting helpers.
- [lib/data/](lib/data/) — concrete data layer.
  - `datasources/remote/` — Dio HTTP clients: `subsonic_client.dart`, `subsonic_api.dart`, `navidrome_client.dart`, `lidarr_client.dart`, `musicbrainz_client.dart`.
  - `datasources/remote/dto/` — `@freezed` + `@JsonSerializable` DTOs that map Subsonic JSON shapes.
  - `database/` — Drift (SQLite). `app_database.dart` declares schema v3 + migrations. Tables in `database/tables/`.
  - `repositories/` — `LibraryRepositoryImpl`, `ServerRepository`, `LidarrRepository`. DTO → domain model mapping happens here.
- [lib/domain/](lib/domain/) — pure Dart: `models/` (mostly `@freezed`) and `repositories/` (interfaces).
- [lib/ui/](lib/ui/) — Flutter widgets.
  - `shell/` — `app_shell.dart` (main layout), `sidebar/`, `bottom_bar/`, `artist_tree/`.
  - `pages/<feature>/` — one folder per section (albums, artists, songs, playlists, device, lidarr, search, settings, setup).
  - `widgets/` — shared widgets (`cover_art_image.dart`, `song_row.dart`, dialogs).
- [lib/core/](lib/core/) — `constants/` (API endpoints, UI dimensions), `theme/`, `errors/app_exception.dart`, `extensions/string_extensions.dart`.
- [lib/platform/drive_detector.dart](lib/platform/drive_detector.dart) — abstract `DriveDetector` + macOS (EventChannel → Swift) and Windows (Win32 FFI polling) impls.
- [macos/Runner/DriveDetectorPlugin.swift](macos/Runner/DriveDetectorPlugin.swift) — native macOS drive detection via `NSWorkspace` mount/unmount.

### Layering rules

- **DTO → domain mapping** lives in the repository implementation, not the API client. `SubsonicApi` returns `SongDto`; `LibraryRepositoryImpl` converts to `Song`.
- **Repositories are abstract**: `LibraryRepository` (in `domain/repositories/`) defines the contract; the impl lives in `data/repositories/`. UI never imports `data/`.
- **Stream/download/cover-art URIs** are built directly by `SubsonicClient.buildUri()` — these are passed as `Uri Function(String)` callbacks (`repo.streamUri`, `repo.downloadUri`) so consumers don't need the client.

### Riverpod conventions

- Single provider hub: [lib/application/providers/providers.dart](lib/application/providers/providers.dart). New top-level providers go there unless they're feature-local.
- Naming: `SomethingNotifier extends Notifier<T>` paired with `final somethingProvider = NotifierProvider<SomethingNotifier, T>(SomethingNotifier.new);`.
- `FutureProvider` for fetch-only data (artists, albums, playlists, search). Recompute on dep change.
- `StateProvider` for trivial UI state (`selectedSectionProvider`, `selectedDeviceProvider`, `searchQueryProvider`, `transferProgressProvider`).
- `AsyncNotifier` for persisted async state (e.g. `SelectedServerNotifier`, `SelectedLidarrInstanceNotifier`).
- **No router**: navigation is `SidebarSection` enum + `selectedSectionProvider` driving `app_shell.dart`. Do not add `go_router`.
- `appSupportDirProvider` throws by default and is overridden in `main()`. Anything that needs the support dir reads it via `ref.watch(appSupportDirProvider)`.

### Subsonic auth

API version `1.16.1`, client name `dapper`, format `json`. The auth interceptor (in [subsonic_client.dart](lib/data/datasources/remote/subsonic_client.dart)) adds `u`, `t`, `s`, `v`, `c`, `f` to every request:

- `s` (salt) = `DateTime.now().millisecondsSinceEpoch.toRadixString(36)`
- `t` (token) = `md5(password + salt)`
- Errors with code 40/41 → `AuthException`; other failed responses → `SubsonicException`.

`SubsonicClient.buildUri()` constructs signed URLs directly (used for `getCoverArt`, `stream`, `download`); these are passed to `CachedNetworkImage`, `just_audio`, and `Dio.download` respectively.

### Persistence

- **App settings** (`transferConcurrency`) → `app_settings.json` in app support dir. See [app_settings_notifier.dart](lib/application/settings/app_settings_notifier.dart).
- **Server / Lidarr URLs + usernames** → drift DB or secure storage (see `ServerRepository`, `LidarrRepository`).
- **Passwords / API keys** → `flutter_secure_storage` (platform keychains). One-time migration from legacy single-server keys (`server_url`/`username`/`password`) lives in `ServersNotifier._load()`.
- **Transfer queue** → `transfer_queue.json`. Saved only when task **status** changes (not on every byte-progress tick). In-progress tasks at app close are reset to `queued` on next launch.
- **Device settings** (folder structure, filename format, music root) → Drift `device_settings` table, one row per `devicePath`.
- **Device manifest** (which songs are on the device) → `.dapper.json` written inside each album folder on the device. See [device_manifest.dart](lib/application/transfer/device_manifest.dart).

### Transfer engine

The heart of the app. [transfer_queue_notifier.dart](lib/application/transfer/transfer_queue_notifier.dart):

- `_runEngine(devicePath, downloadUri)` is one engine per device; pulls up to `appSettings.transferConcurrency` tasks in parallel using a `Completer` slot pattern.
- Path layout is computed by `buildSongPath` ([transfer_path_resolver.dart](lib/application/transfer/transfer_path_resolver.dart)) based on `DeviceSettings.folderStructure` (`artistAlbum`, `artistAlbumYear`, `artistOnly`, `flat`) and `filenameFormat` (`none`, `track`, `discTrack`).
- Filenames are sanitized via `String.toSafeFilename()` ([string_extensions.dart](lib/core/extensions/string_extensions.dart)): path separators → `-`, FAT32-illegal chars dropped, leading/trailing dots stripped (which is what blocks `..` traversal).
- After each download completes the album folder gets an updated `.dapper.json` manifest via `_appendManifest` (chained per-folder so writes serialise).
- M3U playlists are written **only after every song in the group has finished** — see `_pendingPlaylistWrites` + `_onGroupTaskDone`.
- `transferProgressProvider` is a separate `StateProvider<Map<taskId, (received, total)>>` updated at most every 200 ms, so byte-tick rebuilds don't churn the main task list.
- On macOS the engine post-processes each file with `removeMacOSSidecar` to strip `._*` AppleDouble sidecars and xattrs (FAT32/exFAT volumes).

### Drive detection

- **macOS**: `MacosDriveDetector` listens to `EventChannel('com.dapper/drive_detector')`. The Swift plugin (`DriveDetectorPlugin.swift`) observes `NSWorkspace.didMountNotification` / `didUnmountNotification` and pushes drive lists.
- **Windows**: `WindowsDriveDetector` polls every 2 s via `GetLogicalDrives` / `GetDriveType` / `GetVolumeInformation` (Win32 FFI). Filters to `DRIVE_REMOVABLE`.

## macOS specifics

- [main.dart](lib/main.dart) calls `WindowManipulator` (`setMaterial(underWindowBackground)`, transparent titlebar, full-size content view) to get the vibrancy look. Glass-style refinement is a known deferred task.
- Entitlements: `network.client` + `files.user-selected.read-write` enabled in both `macos/Runner/DebugProfile.entitlements` and `Release.entitlements`. Without these, drives won't be writable and Navidrome calls will fail in release builds.

## External integrations

- **Navidrome (Subsonic API)** — primary backend. URL + username/password supplied by the user; multi-server supported via `ServersNotifier`.
- **Lidarr** — optional. Used to add artists discovered via MusicBrainz lookup.
- **MusicBrainz + Cover Art Archive** — used to find release groups and fetch album art when manually fixing album metadata. See [musicbrainz_client.dart](lib/data/datasources/remote/musicbrainz_client.dart). Static `Dio` instances are reused.

## House style

- Match the existing terse style. Lots of one-line `final foo = ...` providers; comments only where the why is non-obvious (e.g. the throttle/sidecar/manifest chaining).
- Keep generated files (`*.g.dart`, `*.freezed.dart`) checked in.
- One feature folder per page under `lib/ui/pages/`. Dialogs live next to the page that owns them.
- Avoid adding new top-level dependencies without justification — the app currently builds quickly with the existing set.
- Lint config in [analysis_options.yaml](analysis_options.yaml) silences `invalid_annotation_target` (freezed false-positive) and `unnecessary_underscores`.

## Gotchas worth remembering

- After editing any `@freezed` or `@JsonSerializable` class, **re-run build_runner** — `flutter analyze` errors that look like missing parts almost always trace back to this.
- `SubsonicClient` is rebuilt whenever credentials change; the old `Dio` instance is not explicitly closed.
- The Subsonic auth interceptor and `buildUri()` both regenerate salts independently — they don't share state.
- Cover-art `CachedNetworkImage` keys include both `serverId` and `coverArtId` to prevent cross-server cache pollution.
- Device folder structure is effectively immutable after sync — changing `DeviceSettings.folderStructure` mid-library would orphan the existing files.
- macOS drive detector is event-driven (`async*` from EventChannel); Windows is a polling `async*` that runs forever once started — there is no explicit cancellation.
