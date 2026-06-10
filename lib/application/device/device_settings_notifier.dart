import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database/app_database.dart';
import '../../domain/models/device_settings.dart';
import '../providers/providers.dart';

class DeviceSettingsNotifier extends FamilyNotifier<DeviceSettings, String> {
  @override
  DeviceSettings build(String devicePath) {
    _loadFromDb(devicePath);
    return DeviceSettings(devicePath: devicePath);
  }

  Future<void> _loadFromDb(String devicePath) async {
    final db = ref.read(appDatabaseProvider);
    final row = await db.getDeviceSettings(devicePath);
    if (row == null) return;
    state = fromRow(row);
  }

  Future<void> save(DeviceSettings settings) async {
    state = settings;
    final db = ref.read(appDatabaseProvider);
    await db.upsertDeviceSettings(DeviceSettingsTableCompanion(
      devicePath: Value(settings.devicePath),
      musicRootFolder: Value(settings.musicRootFolder),
      playlistFolder: Value(settings.playlistFolder),
      folderStructure: Value(settings.folderStructure.name),
      filenameFormat: Value(settings.filenameFormat.name),
      includeYear: Value(settings.includeYear),
      overwriteExisting: Value(settings.overwriteExisting),
      transcodeFormat: Value(settings.transcodeFormat.name),
      transcodeMaxBitRate: Value(settings.transcodeMaxBitRate),
      useZipDownload: Value(settings.useZipDownload),
      customFilenameTemplate: Value(settings.customFilenameTemplate),
      customFolderTemplate: Value(settings.customFolderTemplate),
    ));
  }

  static DeviceSettings fromRow(DeviceSettingsTableData row) => DeviceSettings(
        devicePath: row.devicePath,
        musicRootFolder: row.musicRootFolder,
        playlistFolder: row.playlistFolder,
        folderStructure: FolderStructure.values.firstWhere(
          (e) => e.name == row.folderStructure,
          orElse: () => FolderStructure.artistAlbum,
        ),
        filenameFormat: FilenameFormat.values.firstWhere(
          (e) => e.name == row.filenameFormat,
          orElse: () => FilenameFormat.discTrack,
        ),
        includeYear: row.includeYear,
        overwriteExisting: row.overwriteExisting,
        transcodeFormat: TranscodeFormat.values.firstWhere(
          (e) => e.name == row.transcodeFormat,
          orElse: () => TranscodeFormat.original,
        ),
        transcodeMaxBitRate: row.transcodeMaxBitRate,
        useZipDownload: row.useZipDownload,
        customFilenameTemplate: row.customFilenameTemplate,
        customFolderTemplate: row.customFolderTemplate,
      );
}

// Provider declared here so device_settings_notifier is self-contained.
// The appDatabaseProvider is declared in providers.dart and read via ref.
final deviceSettingsProvider =
    NotifierProvider.family<DeviceSettingsNotifier, DeviceSettings, String>(
  DeviceSettingsNotifier.new,
);
