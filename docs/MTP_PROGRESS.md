# MTP support — progress + remaining work

Snapshot of the MTP (Media Transfer Protocol) device-support effort so a
later session can resume without spelunking.

## Status

**Dart layer**: complete. Every device-side I/O call routes through
`DeviceFs`. Filesystem devices unchanged. MTP devices use `MtpDeviceFs`
backed by `MtpClient` (MethodChannel → native plugin).

**macOS native plugin**: complete + linked. Real libmtp transfers via
Swift + Objective-C bridge. Dylibs embed automatically on every build
(`embed_libmtp.sh` runs as a Run Script build phase). Entitlements set.
**Not verified against a physical device.**

**Windows native plugin**: full WPD COM impl written. **Never compiled on
Windows** (no Windows machine available during the session). Should be
close to working but expect first-compile fixes.

**Tests**: 253/253 green. `flutter analyze` clean. `flutter build macos
--debug` clean.

## What works locally

```bash
flutter analyze              # clean
flutter test                 # 253/253
flutter build macos --debug  # ✓ links libmtp, embeds dylibs in app
otool -L build/macos/Build/Products/Debug/dapper.app/Contents/MacOS/dapper.debug.dylib | grep mtp
# → @rpath/libmtp.9.dylib
```

## File map

### Dart (lib/)

| File | Purpose |
|---|---|
| [platform/device_fs.dart](../lib/platform/device_fs.dart) | `DeviceFs` port: `WriteHandle`, `DeviceFsEntry`, `DeviceProtocol` |
| [platform/local_device_fs.dart](../lib/platform/local_device_fs.dart) | `dart:io` impl |
| [platform/mtp_device_fs.dart](../lib/platform/mtp_device_fs.dart) | MTP impl over `MtpClient` |
| [platform/mtp_client.dart](../lib/platform/mtp_client.dart) | MethodChannel + EventChannel wrapper |
| [platform/mtp_drive_detector.dart](../lib/platform/mtp_drive_detector.dart) | Detector emitting `mtp://<id>` paths |
| [platform/composite_drive_detector.dart](../lib/platform/composite_drive_detector.dart) | Merges FS + MTP |
| [application/transfer/device_cache_warm.dart](../lib/application/transfer/device_cache_warm.dart) | Warm manifest cache on MTP device select |
| [application/transfer/transfer_queue_notifier.dart](../lib/application/transfer/transfer_queue_notifier.dart) | `_streamedDownload` MTP branch via WriteHandle |

### macOS (macos/)

| File | Purpose |
|---|---|
| [Runner/MtpPlugin.swift](../macos/Runner/MtpPlugin.swift) | FlutterPlugin + EventChannel + serial DispatchQueue |
| [Runner/MtpBridge.h](../macos/Runner/MtpBridge.h) | ObjC interface (NS_SWIFT_NAME pinned) |
| [Runner/MtpBridge.m](../macos/Runner/MtpBridge.m) | libmtp impl: enumerate, sessions, list, mkdir, delete, freeSpace, pipe-based put/get streaming |
| [Runner/Runner-Bridging-Header.h](../macos/Runner/Runner-Bridging-Header.h) | Swift↔ObjC bridge |
| [Runner/DebugProfile.entitlements](../macos/Runner/DebugProfile.entitlements) + [Runner/Release.entitlements](../macos/Runner/Release.entitlements) | `cs.disable-library-validation` + `device.usb` |
| [scripts/embed_libmtp.sh](../macos/scripts/embed_libmtp.sh) | Copies+rewrites+codesigns dylibs into the .app |
| [scripts/build_libmtp.sh](../macos/scripts/build_libmtp.sh) | (Optional) builds universal libmtp+libusb from source |
| [Runner.xcodeproj/project.pbxproj](../macos/Runner.xcodeproj/project.pbxproj) | Bridging header + HEADER/LIBRARY_SEARCH_PATHS + `OTHER_LDFLAGS=-lmtp` + Run Script phase "Embed libmtp + libusb" |

### Windows (windows/)

| File | Purpose |
|---|---|
| [runner/mtp_plugin.h](../windows/runner/mtp_plugin.h) | Plugin class + Session/Stream structs |
| [runner/mtp_plugin.cpp](../windows/runner/mtp_plugin.cpp) | Full WPD impl: enumerate, sessions, list, mkdir, delete, freeSpace, IStream put/get |
| [runner/CMakeLists.txt](../windows/runner/CMakeLists.txt) | Links `portabledeviceguids.lib`, `propsys.lib`, `ole32.lib`, `oleaut32.lib` |

### Tests

| File | Purpose |
|---|---|
| [test/platform/local_device_fs_test.dart](../test/platform/local_device_fs_test.dart) | Parity tests for FS impl |
| [test/platform/mtp_device_fs_test.dart](../test/platform/mtp_device_fs_test.dart) | Path cache, mutex, atomic-replace via fake MtpClient |
| [test/platform/composite_drive_detector_test.dart](../test/platform/composite_drive_detector_test.dart) | Merge + eject dispatch |

## Remaining work

### P0 — physical device verification

Code is unverified. First device plug will surface bugs. Workflow:

1. macOS: plug Android phone (MTP mode) or DAP. Run `flutter run -d macos`.
   - Verify sidebar shows phone icon + label.
   - Verify "MTP — transfers run sequentially" banner.
   - Transfer one album. Check device via OpenMTP (or Android Files app).
   - Verify `.dapper.json` written.
   - Cancel mid-transfer. Verify partial object cleaned up (or stranded).
2. Windows: same matrix. First fix any C++ compile errors.

Known suspects:
- libmtp's serial-number-as-deviceId — some devices return empty; fallback
  `bus_N_dev_M` doesn't survive replug. May need PnP-ID-style fingerprint.
- Cancel propagation: close-pipe + thread exit untested.
- Non-ASCII filenames — libmtp says UTF-8, devices vary.
- Multi-storage devices: Bridge always picks `dev->storage->id` (first).
  Internal + SD card phones only expose internal. Need per-storage selection
  in DeviceSettings.

### P1 — Windows first-compile

`mtp_plugin.cpp` is structurally correct but never built. Likely failures:

- `IPortableDeviceContent::Transfer` returns `IPortableDeviceResources` —
  verify signature against current Windows SDK headers.
- `PROPVARIANT` extraction for `WPD_OBJECT_DATE_MODIFIED` may need to handle
  more VT_* types depending on device firmware.
- `IPortableDeviceDataStream` cast from `IStream*` may need explicit
  `QueryInterface` instead of `ComPtr::As` on some SDKs.
- COM apartment: currently MTA. If Flutter binder thread is STA, may need
  marshalling — would surface as `RPC_E_WRONG_THREAD` on first method call.

### P1 — Sync UI selectors for MTP (pre-warm)

`transfer_path_resolver.dart` sync selectors (`songFileExistsOnDevice`,
`albumSyncOnDevice`, etc.) return false for MTP paths before
`warmDeviceManifestCache` runs (fires on device select). Edge case: very
first frame after device select shows "not on device" badges until warm
completes. Acceptable. Real fix: async-warmed sync cache facade.

### P1 — UX gaps

- No "Connecting to MTP device…" spinner during session open
- No retry-after-fail action in transfer queue UI for MTP-specific errors
- Android-side "Trust this computer" prompt not surfaced — if user
  declines, enumerate returns 0 devices silently
- Per-storage picker (Internal vs SD card) in device settings

### P2 — Polish

- macOS hotplug: 2s poll → IOKit `IOServiceAddMatchingNotification` for
  lower latency
- Windows hotplug: 2s poll → `RegisterDeviceNotification(GUID_DEVINTERFACE_WPD)`
- macOS deployment target: bump from 11.0 to 14.0 to silence libmtp dylib
  version mismatch warning
- Windows IStream::Write/Read: honour `optimal_size` returned by
  `CreateObjectWithPropertiesAndData` / `GetStream` for throughput
- Zip extractor isolate for MTP: extract-to-local-temp + per-file upload
  (currently falls back to per-song via `_convertGroupToSongTasks`)
- FLAC tag sanitizer for MTP: streaming rewriter instead of skip (per
  earlier user decision — currently skipped, leave as is)
- Tests: integration test for `_streamedDownload` MTP branch via
  MethodChannel mock + fake Dio response
- macOS notarisation: untested. First `notarytool submit` will likely flag
  the unsigned libmtp+libusb dylibs (`ad-hoc` signature won't satisfy
  notarisation). Replace `-` with team ID in `embed_libmtp.sh` for release.

## How to resume

```bash
# 1. Build + run on macOS with an MTP device plugged in
flutter build macos --debug
open build/macos/Build/Products/Debug/dapper.app

# 2. Plug an Android phone (USB → MTP mode) or DAP
# 3. Check the sidebar for a phone icon + device label
# 4. Try transferring one song
# 5. Note every bug

# 6. When ready to ship: replace `-` in embed_libmtp.sh's codesign call
#    with your Developer ID, then:
flutter build macos --release
xcrun notarytool submit build/macos/Build/Products/Release/dapper.app \
  --apple-id ... --team-id ... --password ...
xcrun stapler staple build/macos/Build/Products/Release/dapper.app
```

For Windows, find a Windows machine first.

## Design decisions worth not re-litigating

- Hand-rolled native plugins (no third-party MTP package). Chosen over
  `flutter_mtp_picker` due to unverified maintainer + unclear write API.
- Single big PR vs. phased PRs — went with single. Total ~25 file edits
  + 13 new files. Reviewable but big.
- Skip FLAC tag sanitize for MTP devices. Decided early; engine already
  gates on `fs.protocol == filesystem`.
- Object IDs: libmtp returns `uint32_t`, WPD uses wide strings. Both map
  to `int64` in the Dart contract via per-session in-memory mapping.
- MTP devicePath scheme: `mtp://<deviceId>`. Stable across mounts (uses
  serial number). Drift schema accepts it alongside filesystem paths,
  no migration needed.
- Per-device concurrency cap: `DeviceFs.maxConcurrentTransfers`.
  Filesystem = `appSettings.transferConcurrency`; MTP = 1.
- Sync UI selectors: kept sync filesystem fast path; MTP populated via
  warm walk on device select. Acceptable trade-off; full async-warmed
  facade deferred.
- Atomic manifest writes via `openAtomicReplace`. Filesystem uses
  `.tmp`+rename; MTP uses delete+write (no rename available).
