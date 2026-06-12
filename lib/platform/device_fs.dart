import '../domain/models/device_settings.dart';

/// Protocol family of a connected device.
///
/// Used to discriminate between mounted filesystem volumes (`/Volumes/...`,
/// `E:\`) and MTP devices accessed via a native plugin. Drives every layering
/// decision downstream — `DeviceFs` impl selection, concurrency cap,
/// availability of in-place rewrites, sidecar handling, etc.
enum DeviceProtocol { filesystem, mtp }

/// A directory entry yielded by [DeviceFs.list].
///
/// [path] is the same kind of string the caller passed to `list()` — for
/// filesystem devices a normal absolute path; for MTP devices a synthetic
/// path under the device's pseudo-root. Callers do not interpret it beyond
/// passing it back to other `DeviceFs` methods.
class DeviceFsEntry {
  const DeviceFsEntry({
    required this.path,
    required this.isDir,
    required this.size,
    this.modified,
  });

  final String path;
  final bool isDir;

  /// File size in bytes, or `0` for directories. `-1` when unknown (MTP
  /// devices may not report sizes during enumeration).
  final int size;

  final DateTime? modified;
}

/// A write session for a single file on the device.
///
/// Always created via [DeviceFs.openWrite] or [DeviceFs.openAtomicReplace].
/// The contract is one of:
///   - call [write] any number of times, then [close]
///   - call [abort] at any point to discard the partial write
///
/// Implementations must guarantee that after [close] the bytes are durable
/// and the file is visible at its target path; for atomic-replace handles
/// this includes the rename step. After [abort] no partial file should be
/// visible at the target path.
abstract class WriteHandle {
  Future<void> write(List<int> chunk);
  Future<void> close();
  Future<void> abort();
}

/// Port for everything the transfer engine, manifest, scrobble importer,
/// prune, and scan layers do against a device's filesystem.
///
/// Two impls today:
///   - `LocalDeviceFs` — wraps `dart:io` for mounted volumes. Identical
///     behavior to the pre-abstraction direct calls (atomic `.tmp`+rename,
///     macOS sidecar/xattr cleanup, etc.).
///   - `MtpDeviceFs` (future) — wraps a `MethodChannel` to a native plugin
///     (Swift+libmtp on macOS, C++/WPD COM on Windows). Constrains the
///     interface to operations expressible over MTP: no append/seek,
///     single-session concurrency, no rename.
///
/// Notes for callers:
///   - All operations are async. Callers that previously used sync
///     `*.existsSync()` / `Directory.listSync()` either become async or
///     keep a sync cache facade backed by async warming.
///   - [maxConcurrentTransfers] is the per-device concurrency cap the
///     transfer engine should honour: filesystem returns the user's global
///     `transferConcurrency`; MTP forces 1.
abstract class DeviceFs {
  DeviceProtocol get protocol;

  /// Maximum number of in-flight transfers the engine should run against
  /// this device. Filesystem: typically the user's `transferConcurrency`
  /// setting. MTP: 1 (single-session protocol).
  int get maxConcurrentTransfers;

  /// True if the entry at [path] exists. Returns false on any access error.
  Future<bool> exists(String path);

  /// True if the entry at [path] exists and is a directory.
  Future<bool> isDir(String path);

  /// Size of the file at [path] in bytes, or null when the entry is missing
  /// or its size cannot be determined.
  Future<int?> sizeOf(String path);

  /// Creates [dir] and every missing parent. No-op when it already exists.
  Future<void> mkdirp(String dir);

  /// Non-recursive listing of [dir]. Returns an empty list when [dir] is
  /// missing rather than throwing.
  Future<List<DeviceFsEntry>> list(String dir);

  /// Deletes a single file or empty directory at [path]. No-op when the
  /// entry is already missing.
  Future<void> delete(String path);

  /// Deletes [dir] and everything beneath it. No-op when [dir] is missing.
  Future<void> deleteRecursive(String dir);

  /// Opens a streaming write of [path]. Optional [totalBytes] hint helps
  /// MTP impls pre-allocate or report progress; pass it when known.
  ///
  /// The returned handle must be either [WriteHandle.close]'d (commit) or
  /// [WriteHandle.abort]'d (discard). Callers should treat the handle as
  /// exclusive and not interleave other writes to the same path until it
  /// resolves.
  Future<WriteHandle> openWrite(String path, {int? totalBytes});

  /// Opens a streaming read of [path]. Throws when [path] is missing.
  Future<Stream<List<int>>> openRead(String path);

  /// Atomic file replacement.
  ///
  /// Filesystem impl: writes to a sibling `.tmp` then renames over [path];
  /// concurrent readers either see the old file or the new file, never a
  /// truncated one. Used for `.dapper.json` manifest writes where crash
  /// safety matters.
  ///
  /// MTP impl: deletes any existing object at [path] before opening a fresh
  /// write — MTP has no rename, so this is the best approximation
  /// available. Callers tolerant of a brief absence (manifests) should be
  /// fine; anything that genuinely requires atomicity over MTP needs a
  /// different design.
  Future<WriteHandle> openAtomicReplace(String path, {int? totalBytes});

  /// Empties the file at [path] without deleting it.
  ///
  /// Filesystem: `writeAsString('', flush:true)` — preserves the inode so
  /// DAPs that append to the same file handle keep working.
  ///
  /// MTP: deletes the object and creates a new empty one with the same
  /// name. No append-semantics guarantee on MTP, so this is the closest
  /// available match.
  Future<void> truncate(String path);

  /// Strips macOS AppleDouble sidecars (`._filename`) and extended
  /// attributes from [path].
  ///
  /// Filesystem on macOS: removes the sidecar if present and runs
  /// `xattr -c` so the sidecar isn't recreated.
  /// Filesystem on other platforms: no-op.
  /// MTP: no-op (MTP devices don't materialise AppleDouble sidecars).
  Future<void> removeSidecar(String path);

  /// Free bytes available on the device volume, or null when the platform
  /// query failed. Treat null as "skip the precheck", not "device full".
  Future<int?> freeBytes();

  /// Joins [settings.devicePath] with [settings.musicRootFolder] into a
  /// canonical absolute path on this device. Filesystem impl uses platform
  /// path joining; MTP impl uses forward-slash joining over the synthetic
  /// pseudo-path. Always non-null; falls back to `devicePath` when the
  /// configured music-root subfolder is empty.
  String resolveMusicRoot(DeviceSettings settings);

  /// Releases any background resources (open sessions, native handles).
  /// Safe to call multiple times.
  Future<void> dispose();
}
