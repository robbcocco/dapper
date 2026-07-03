import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:uuid/uuid.dart';

import '../../data/database/app_database.dart';
import '../../data/datasources/local/credential_store.dart';
import '../../data/datasources/remote/lidarr_client.dart';
import '../../data/datasources/remote/subsonic_api.dart';
import '../../data/datasources/remote/subsonic_client.dart';
import '../../data/repositories/library_repository_impl.dart';
import '../../data/repositories/lidarr_repository.dart';
import '../../data/repositories/server_repository.dart';
import '../../domain/models/app_settings.dart';
import '../../domain/models/connected_device.dart';
import '../../domain/models/device_settings.dart';
import '../../domain/models/lidarr_instance.dart';
import '../../domain/models/navidrome_server.dart';
import '../../domain/models/transfer_task.dart';
import '../../domain/repositories/library_repository.dart';
import '../../platform/drive_detector.dart';
import '../device/device_settings_notifier.dart';
import '../settings/app_settings_notifier.dart';
import '../transfer/transfer_queue_notifier.dart';

// ── App support directory ─────────────────────────────────────────────────────

/// Overridden in main() with the real path from getApplicationSupportDirectory().
final appSupportDirProvider = Provider<String>(
  (_) => throw UnimplementedError('appSupportDirProvider not initialized'),
);

// ── Database ──────────────────────────────────────────────────────────────────

final appDatabaseProvider = Provider<AppDatabase>((_) => AppDatabase());

// ── Secure storage ────────────────────────────────────────────────────────────

// Returns a Keychain → file fallback store. The macOS Keychain can return
// errSecMissingEntitlement (-34018) depending on signing / translocation state
// even when the entitlement is declared; the fallback persists credentials to
// a 600-mode JSON file in the app support directory so the app never blocks
// on saving the server.
final secureStorageProvider = Provider<CredentialStore>((ref) {
  final supportDir = ref.watch(appSupportDirProvider);
  return buildDefaultCredentialStore(supportDir);
});

// ── Server repository ─────────────────────────────────────────────────────────

final serverRepositoryProvider = Provider<ServerRepository>((ref) {
  return ServerRepository(ref.watch(secureStorageProvider));
});

// ── Server list ───────────────────────────────────────────────────────────────

class ServersNotifier extends Notifier<List<NavidromeServer>> {
  static const _uuid = Uuid();

  @override
  List<NavidromeServer> build() {
    _load();
    return [];
  }

  Future<void> _load() async {
    final repo = ref.read(serverRepositoryProvider);
    var servers = await repo.loadAll();

    // One-time migration from the legacy single-server credential keys.
    if (servers.isEmpty) {
      final storage = ref.read(secureStorageProvider);
      final url = await storage.read(key: 'server_url');
      final username = await storage.read(key: 'username');
      final password = await storage.read(key: 'password');
      if (url != null && username != null && password != null) {
        final migrated = NavidromeServer(
          id: _uuid.v4(),
          name: 'My Server',
          url: url,
          username: username,
        );
        await repo.upsert(migrated);
        await repo.savePassword(migrated.id, password);
        await repo.saveSelectedId(migrated.id);
        await Future.wait([
          storage.delete(key: 'server_url'),
          storage.delete(key: 'username'),
          storage.delete(key: 'password'),
        ]);
        servers = [migrated];
      }
    }

    state = servers;
    // Reload selectedServerIdProvider so it picks up any migration changes.
    ref.invalidate(selectedServerIdProvider);
  }

  Future<void> add(NavidromeServer server, String password) async {
    final repo = ref.read(serverRepositoryProvider);
    await repo.upsert(server);
    await repo.savePassword(server.id, password);
    state = [...state, server];
    // Auto-select if this is the first server.
    if (state.length == 1) {
      await ref.read(selectedServerIdProvider.notifier).select(server.id);
    }
  }

  Future<void> update(NavidromeServer server, {String? newPassword}) async {
    final repo = ref.read(serverRepositoryProvider);
    await repo.upsert(server);
    if (newPassword != null && newPassword.isNotEmpty) {
      await repo.savePassword(server.id, newPassword);
    }
    state = [for (final s in state) s.id == server.id ? server : s];
  }

  Future<void> remove(String id) async {
    final repo = ref.read(serverRepositoryProvider);
    await repo.delete(id);
    state = state.where((s) => s.id != id).toList();
    if (ref.read(selectedServerIdProvider).value == id) {
      await ref
          .read(selectedServerIdProvider.notifier)
          .select(state.isEmpty ? null : state.first.id);
    }
  }

  static String newId() => _uuid.v4();
}

final serversProvider =
    NotifierProvider<ServersNotifier, List<NavidromeServer>>(
  ServersNotifier.new,
);

// ── Active server selection ───────────────────────────────────────────────────

class SelectedServerNotifier extends AsyncNotifier<String?> {
  @override
  Future<String?> build() async {
    return ref.read(serverRepositoryProvider).loadSelectedId();
  }

  Future<void> select(String? id) async {
    await ref.read(serverRepositoryProvider).saveSelectedId(id);
    state = AsyncData(id);
  }
}

final selectedServerIdProvider =
    AsyncNotifierProvider<SelectedServerNotifier, String?>(
  SelectedServerNotifier.new,
);

/// The currently active [NavidromeServer], or null if none is selected.
final selectedServerProvider = Provider<NavidromeServer?>((ref) {
  final id = ref.watch(selectedServerIdProvider).value;
  if (id == null) return null;
  return ref.watch(serversProvider).where((s) => s.id == id).firstOrNull;
});

// ── Credentials (derived from active server) ──────────────────────────────────

final serverCredentialsProvider =
    FutureProvider<_ServerCredentials?>((ref) async {
  final server = ref.watch(selectedServerProvider);
  if (server == null) return null;
  final password =
      await ref.watch(serverRepositoryProvider).loadPassword(server.id);
  if (password == null) return null;
  return _ServerCredentials(
      url: server.url, username: server.username, password: password);
});

class _ServerCredentials {
  const _ServerCredentials({
    required this.url,
    required this.username,
    required this.password,
  });
  final String url;
  final String username;
  final String password;

  // Value equality so libraryRepositoryProvider's invalidation guard
  // (`prev?.value == next.value`) only rebuilds the Subsonic stack when the
  // credentials actually change — not on every unrelated upstream recompute,
  // which would needlessly close the Dio pool and drop in-flight requests.
  @override
  bool operator ==(Object other) =>
      other is _ServerCredentials &&
      other.url == url &&
      other.username == username &&
      other.password == password;

  @override
  int get hashCode => Object.hash(url, username, password);
}

// ── Repository ────────────────────────────────────────────────────────────────
//
// One sync Provider builds the whole Subsonic stack from credentials. The
// upstream FutureProvider (serverCredentialsProvider) is consumed via
// `ref.listen` + microtask-deferred `invalidateSelf` rather than `ref.watch`
// so that the AsyncLoading → AsyncData transition does not trigger
// setState-during-build inside Riverpod 3.3.x's scheduler when a downstream
// FutureProvider mounts mid-build.

final libraryRepositoryProvider = Provider<LibraryRepository?>((ref) {
  ref.listen<AsyncValue<_ServerCredentials?>>(serverCredentialsProvider,
      (prev, next) {
    if (prev?.value == next.value) return;
    Future.microtask(() {
      if (ref.mounted) ref.invalidateSelf();
    });
  });

  final creds = ref.read(serverCredentialsProvider).value;
  if (creds == null) return null;
  final client = SubsonicClient(
    baseUrl: creds.url,
    username: creds.username,
    password: creds.password,
  );
  ref.onDispose(client.dispose);
  return LibraryRepositoryImpl(SubsonicApi(client));
});

// ── Device detection ──────────────────────────────────────────────────────────

final driveDetectorProvider = Provider<DriveDetector>((ref) {
  final detector = createDriveDetector();
  ref.onDispose(detector.dispose);
  return detector;
});

final connectedDevicesProvider = StreamProvider<List<ConnectedDevice>>((ref) {
  final detector = ref.watch(driveDetectorProvider);
  return detector.watchDrives();
});

// ── Device selection ──────────────────────────────────────────────────────────

final selectedDeviceProvider = StateProvider<ConnectedDevice?>((_) => null);

// ── App settings ──────────────────────────────────────────────────────────────

final appSettingsProvider =
    NotifierProvider<AppSettingsNotifier, AppSettings>(
  AppSettingsNotifier.new,
);

// ── Transfer queue ────────────────────────────────────────────────────────────

final transferQueueProvider =
    NotifierProvider<TransferQueueNotifier, List<TransferTask>>(
  TransferQueueNotifier.new,
);

/// Live download progress: taskId → (bytesReceived, totalBytes).
/// Separate from [transferQueueProvider] so that 200 ms byte-tick updates
/// only rebuild the progress indicator, not every visible song row.
final transferProgressProvider =
    StateProvider<Map<String, (int, int)>>((ref) => const {});

/// Transient user-facing error message, surfaced as a SnackBar by AppShell.
/// Set by background actions that would otherwise fail silently (playlist
/// edits, etc.). AppShell resets it to null once shown.
final actionErrorProvider = StateProvider<String?>((ref) => null);

/// Monotonic counter bumped whenever a device .dapper.json manifest is
/// written. Widgets that derive "is this song on the device?" from the
/// manifest read this provider so they rebuild after a transfer completes.
/// Cheap to watch — the value is ignored, only the change matters.
final manifestRevisionProvider = StateProvider<int>((ref) => 0);

// ── All stored device settings ────────────────────────────────────────────────

final allStoredDeviceSettingsProvider =
    FutureProvider<List<DeviceSettings>>((ref) async {
  final db = ref.watch(appDatabaseProvider);
  final rows = await db.getAllDeviceSettings();
  return rows.map(DeviceSettingsNotifier.fromRow).toList();
});

// ── Lidarr repository ─────────────────────────────────────────────────────────

final lidarrRepositoryProvider = Provider<LidarrRepository>((ref) {
  return LidarrRepository(ref.watch(secureStorageProvider));
});

// ── Lidarr instance list ──────────────────────────────────────────────────────

class LidarrInstancesNotifier extends Notifier<List<LidarrInstance>> {
  static const _uuid = Uuid();

  @override
  List<LidarrInstance> build() {
    _load();
    return [];
  }

  Future<void> _load() async {
    final repo = ref.read(lidarrRepositoryProvider);
    var instances = await repo.loadAll();

    // One-time migration from legacy single-instance keys.
    if (instances.isEmpty) {
      final storage = ref.read(secureStorageProvider);
      final url = await storage.read(key: 'lidarr_url');
      final apiKey = await storage.read(key: 'lidarr_api_key');
      if (url != null && apiKey != null) {
        final rfId = await storage.read(key: 'lidarr_root_folder_id');
        final rfPath = await storage.read(key: 'lidarr_root_folder_path');
        final qpId = await storage.read(key: 'lidarr_quality_profile_id');
        final qpName = await storage.read(key: 'lidarr_quality_profile_name');
        final migrated = LidarrInstance(
          id: _uuid.v4(),
          name: 'Lidarr',
          url: url,
          defaultRootFolderId: rfId != null ? int.tryParse(rfId) : null,
          defaultRootFolderPath: rfPath,
          defaultQualityProfileId: qpId != null ? int.tryParse(qpId) : null,
          defaultQualityProfileName: qpName,
        );
        await repo.upsert(migrated);
        await repo.saveApiKey(migrated.id, apiKey);
        await repo.saveSelectedId(migrated.id);
        await Future.wait([
          storage.delete(key: 'lidarr_url'),
          storage.delete(key: 'lidarr_api_key'),
          storage.delete(key: 'lidarr_root_folder_id'),
          storage.delete(key: 'lidarr_root_folder_path'),
          storage.delete(key: 'lidarr_quality_profile_id'),
          storage.delete(key: 'lidarr_quality_profile_name'),
        ]);
        instances = [migrated];
      }
    }

    state = instances;
    ref.invalidate(selectedLidarrInstanceIdProvider);
  }

  Future<void> add(LidarrInstance instance, String apiKey) async {
    final repo = ref.read(lidarrRepositoryProvider);
    await repo.upsert(instance);
    await repo.saveApiKey(instance.id, apiKey);
    state = [...state, instance];
    if (state.length == 1) {
      await ref.read(selectedLidarrInstanceIdProvider.notifier).select(instance.id);
    }
  }

  Future<void> update(LidarrInstance instance, {String? newApiKey}) async {
    final repo = ref.read(lidarrRepositoryProvider);
    await repo.upsert(instance);
    if (newApiKey != null && newApiKey.isNotEmpty) {
      await repo.saveApiKey(instance.id, newApiKey);
    }
    state = [for (final i in state) i.id == instance.id ? instance : i];
  }

  Future<void> remove(String id) async {
    final repo = ref.read(lidarrRepositoryProvider);
    await repo.delete(id);
    state = state.where((i) => i.id != id).toList();
    if (ref.read(selectedLidarrInstanceIdProvider).value == id) {
      await ref
          .read(selectedLidarrInstanceIdProvider.notifier)
          .select(state.isEmpty ? null : state.first.id);
    }
  }

  static String newId() => _uuid.v4();
}

final lidarrInstancesProvider =
    NotifierProvider<LidarrInstancesNotifier, List<LidarrInstance>>(
  LidarrInstancesNotifier.new,
);

// ── Active Lidarr instance selection ─────────────────────────────────────────

class SelectedLidarrInstanceNotifier extends AsyncNotifier<String?> {
  @override
  Future<String?> build() async {
    return ref.read(lidarrRepositoryProvider).loadSelectedId();
  }

  Future<void> select(String? id) async {
    await ref.read(lidarrRepositoryProvider).saveSelectedId(id);
    state = AsyncData(id);
  }
}

final selectedLidarrInstanceIdProvider =
    AsyncNotifierProvider<SelectedLidarrInstanceNotifier, String?>(
  SelectedLidarrInstanceNotifier.new,
);

final selectedLidarrInstanceProvider = Provider<LidarrInstance?>((ref) {
  final id = ref.watch(selectedLidarrInstanceIdProvider).value;
  if (id == null) return null;
  return ref.watch(lidarrInstancesProvider).where((i) => i.id == id).firstOrNull;
});

// ── Lidarr credentials ────────────────────────────────────────────────────────

final lidarrCredentialsProvider =
    FutureProvider<_LidarrCredentials?>((ref) async {
  final instance = ref.watch(selectedLidarrInstanceProvider);
  if (instance == null) return null;
  final apiKey =
      await ref.watch(lidarrRepositoryProvider).loadApiKey(instance.id);
  if (apiKey == null) return null;
  return _LidarrCredentials(url: instance.url, apiKey: apiKey);
});

class _LidarrCredentials {
  const _LidarrCredentials({required this.url, required this.apiKey});
  final String url;
  final String apiKey;
}

final lidarrClientProvider = Provider<LidarrClient?>((ref) {
  final creds = ref.watch(lidarrCredentialsProvider).value;
  if (creds == null) return null;
  final client = LidarrClient(baseUrl: creds.url, apiKey: creds.apiKey);
  ref.onDispose(client.dispose);
  return client;
});
