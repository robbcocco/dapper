import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../data/database/app_database.dart';
import '../../data/datasources/remote/lidarr_client.dart';
import '../../data/datasources/remote/subsonic_api.dart';
import '../../data/datasources/remote/subsonic_client.dart';
import '../../data/repositories/library_repository_impl.dart';
import '../../domain/models/connected_device.dart';
import '../../domain/models/device_settings.dart';
import '../../domain/models/transfer_task.dart';
import '../../domain/repositories/library_repository.dart';
import '../../platform/drive_detector.dart';
import '../device/device_settings_notifier.dart';
import '../transfer/transfer_queue_notifier.dart';

// ── Database ──────────────────────────────────────────────────────────────────

final appDatabaseProvider = Provider<AppDatabase>((_) => AppDatabase());

// ── Credentials ──────────────────────────────────────────────────────────────

final secureStorageProvider = Provider<FlutterSecureStorage>(
  (_) => const FlutterSecureStorage(),
);

final serverCredentialsProvider = FutureProvider<_ServerCredentials?>((ref) async {
  final storage = ref.watch(secureStorageProvider);
  final url = await storage.read(key: 'server_url');
  final username = await storage.read(key: 'username');
  final password = await storage.read(key: 'password');
  if (url == null || username == null || password == null) return null;
  return _ServerCredentials(url: url, username: username, password: password);
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
}

// ── Subsonic layer ────────────────────────────────────────────────────────────

final subsonicClientProvider = Provider<SubsonicClient?>((ref) {
  final creds = ref.watch(serverCredentialsProvider).valueOrNull;
  if (creds == null) return null;
  return SubsonicClient(
    baseUrl: creds.url,
    username: creds.username,
    password: creds.password,
  );
});

final subsonicApiProvider = Provider<SubsonicApi?>((ref) {
  final client = ref.watch(subsonicClientProvider);
  if (client == null) return null;
  return SubsonicApi(client);
});

// ── Repository ────────────────────────────────────────────────────────────────

final libraryRepositoryProvider = Provider<LibraryRepository?>((ref) {
  final api = ref.watch(subsonicApiProvider);
  if (api == null) return null;
  return LibraryRepositoryImpl(api);
});

// ── Device detection ──────────────────────────────────────────────────────────

final driveDetectorProvider = Provider<DriveDetector>(
  (_) => createDriveDetector(),
);

final connectedDevicesProvider = StreamProvider<List<ConnectedDevice>>((ref) {
  final detector = ref.watch(driveDetectorProvider);
  return detector.watchDrives();
});

// ── Device selection ──────────────────────────────────────────────────────────

final selectedDeviceProvider = StateProvider<ConnectedDevice?>((_) => null);

// ── Transfer queue ────────────────────────────────────────────────────────────

final transferQueueProvider =
    NotifierProvider<TransferQueueNotifier, List<TransferTask>>(
  TransferQueueNotifier.new,
);

// ── All stored device settings ────────────────────────────────────────────────

final allStoredDeviceSettingsProvider = FutureProvider<List<DeviceSettings>>((ref) async {
  final db = ref.watch(appDatabaseProvider);
  final rows = await db.getAllDeviceSettings();
  return rows.map(DeviceSettingsNotifier.fromRow).toList();
});

// ── Lidarr credentials ────────────────────────────────────────────────────────

final lidarrCredentialsProvider =
    FutureProvider<_LidarrCredentials?>((ref) async {
  final storage = ref.watch(secureStorageProvider);
  final url = await storage.read(key: 'lidarr_url');
  final apiKey = await storage.read(key: 'lidarr_api_key');
  if (url == null || apiKey == null) return null;
  return _LidarrCredentials(url: url, apiKey: apiKey);
});

class _LidarrCredentials {
  const _LidarrCredentials({required this.url, required this.apiKey});
  final String url;
  final String apiKey;
}

final lidarrClientProvider = Provider<LidarrClient?>((ref) {
  final creds = ref.watch(lidarrCredentialsProvider).valueOrNull;
  if (creds == null) return null;
  return LidarrClient(baseUrl: creds.url, apiKey: creds.apiKey);
});
