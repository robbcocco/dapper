# Dapper

Cross-platform Flutter desktop app (macOS + Windows) that connects to a Navidrome server via the Subsonic REST API, browses the music library, and transfers tracks to connected USB devices (SD cards, DAPs). UI is iTunes-inspired: sidebar + main grid + bottom player/status bar.

## Status

Phase 1 (library browsing) and Phase 2 (transfer engine) are functional. Phase 3 (playback polish, playlist sync) is in progress.

Supported targets:
- macOS — primary development target; signed for distribution.
- Windows — supported; drive detection via Win32 FFI.

## Build & run

Flutter 3.12+ is required. On macOS this project uses `/opt/homebrew/bin/flutter`.

```bash
flutter pub get

# Run in dev
flutter run -d macos
flutter run -d windows

# Build release
flutter build macos --release
flutter build windows --release

# Lint + test
flutter analyze
flutter test
```

After editing any `@freezed` model, `@JsonSerializable` DTO, or Drift table, re-run code generation:

```bash
flutter pub run build_runner build --delete-conflicting-outputs
```

First-time macOS setup may also need:

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -license accept
```

## Configuration

Server URL, username, and password are entered at first launch and stored in the platform keychain via `flutter_secure_storage`. Multiple Navidrome servers can be added from Settings. Lidarr instances (for artist add-from-MusicBrainz) are configured the same way.

App support files (transfer queue, settings, drift DB) live under the OS-standard app support directory (`~/Library/Application Support/dapper/` on macOS).

## Project layout

See [CLAUDE.md](CLAUDE.md) for an architecture overview, layer-by-layer responsibilities, and conventions used throughout the codebase.

## License

Personal project; no license declared.
