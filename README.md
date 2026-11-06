# Dapper

Desktop app (macOS + Windows) that connects to a Navidrome server via the Subsonic REST API, browses and plays the music library, and transfers tracks to connected USB devices (SD cards, DAPs). UI is iTunes-inspired: sidebar + main grid + bottom player/status bar.

Built with Rust (all logic, `app/crates`), Tauri 2 (window) and Svelte 5 (view layer, `app/ui`). The previous Flutter implementation (v1.2.2) is archived on the `archive/flutter-v1.2.2` branch.

## Install

Download the `.dmg` (macOS, Apple Silicon) or the `.msi`/`-setup.exe` (Windows) from [Releases](https://github.com/robbcocco/dapper/releases).

The macOS app is ad-hoc signed, not notarized by Apple, so the first launch is blocked with "Apple could not verify 'Dapper'…". After dragging it to Applications, either:

- open **System Settings → Privacy & Security**, scroll to the message about Dapper and click **Open Anyway**; or
- run `xattr -dr com.apple.quarantine /Applications/Dapper.app` once.

After each update macOS also asks once to let Dapper read its saved passwords from the keychain — choose **Always Allow**.

## Build & run

Requirements: Rust (stable, via rustup) and Node 22.

```bash
cd app
npm --prefix ui ci

# Run in dev
npm --prefix ui exec -- tauri dev

# Build release bundles (.app/.dmg on macOS, .msi/.exe on Windows)
npm --prefix ui exec -- tauri build

# Lint + test
cargo clippy --workspace --all-targets -- -D warnings
cargo test --workspace
npm --prefix ui run check
```

## Configuration

Server URL, username and password are entered at first launch; passwords and API keys go to the login keychain on macOS (works for unsigned builds; after each update macOS asks once to allow access — choose "Always Allow") and to Credential Manager on Windows, with a 0600 `credentials.v2.json` as fallback if the keychain is unavailable. Multiple Navidrome servers and Lidarr instances can be added from Settings. On first launch, data from the Flutter version (servers, device settings, transfer queue, app settings) is imported once.

App data lives in the OS app-data directory (`~/Library/Application Support/com.dapper.dapper` on macOS, `%APPDATA%\com.dapper.dapper` on Windows): `app.db`, `settings.json`, `queue.json`, the per-server library cache under `library/`, and cover art under `covers/`. Set `DAPPER_DATA_DIR` to use another directory.

## Project layout

See [CLAUDE.md](CLAUDE.md) for the architecture, crate responsibilities and conventions.

## License

Personal project; no license declared.
