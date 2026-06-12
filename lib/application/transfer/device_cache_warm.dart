import 'dart:async';
import 'dart:developer' as dev;

import '../../domain/models/device_settings.dart';
import '../../platform/device_fs.dart';
import 'device_manifest.dart';

/// Walks the device's music root via [DeviceFs] up to 3 levels deep,
/// reading every `.dapper.json` into the in-memory manifest cache and
/// marking every visited folder as existing.
///
/// Why this exists: the sync UI selectors in [transfer_path_resolver]
/// (`songFileExistsOnDevice`, `albumSyncOnDevice`, etc.) probe via
/// `dart:io.File.existsSync()` for performance. That works for filesystem
/// devices but silently returns false for `mtp://` paths. A single warming
/// pass populates [_manifestCache] / [_folderExistsCache] so the subsequent
/// sync selectors return correct answers on MTP without changing their
/// signatures.
///
/// Idempotent: re-running just re-fills the same cache entries. Should be
/// invoked when an MTP device is selected (see the listener in
/// `TransferQueueNotifier`).
///
/// Returns the number of manifests parsed, for diagnostic logging.
Future<int> warmDeviceManifestCache(
    DeviceFs fs, DeviceSettings settings) async {
  final root = fs.resolveMusicRoot(settings);
  if (!await folderExistsAsync(root, fs)) return 0;

  var parsed = 0;

  Future<void> visit(String folder) async {
    final manifest = await readManifestAsync(folder, fs);
    if (manifest != null) parsed++;
  }

  try {
    final lvl1 = await fs.list(root);
    for (final e1 in lvl1) {
      if (!e1.isDir) continue;
      await visit(e1.path);
      try {
        final lvl2 = await fs.list(e1.path);
        for (final e2 in lvl2) {
          if (!e2.isDir) continue;
          await visit(e2.path);
          // One more level for disc-nested / custom-template layouts. Three
          // levels matches what scrobble_importer walks for similar reasons.
          try {
            final lvl3 = await fs.list(e2.path);
            for (final e3 in lvl3) {
              if (e3.isDir) await visit(e3.path);
            }
          } catch (_) {}
        }
      } catch (_) {}
    }
  } catch (e) {
    dev.log('warmDeviceManifestCache: walk of $root failed — $e');
  }
  return parsed;
}
