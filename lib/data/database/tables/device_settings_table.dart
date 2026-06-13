import 'package:drift/drift.dart';

class DeviceSettingsTable extends Table {
  TextColumn get devicePath => text()();
  TextColumn get musicRootFolder => text().withDefault(const Constant(''))();
  TextColumn get playlistFolder =>
      text().withDefault(const Constant('Playlists'))();
  TextColumn get folderStructure =>
      text().withDefault(const Constant('artistAlbum'))();
  // v3: replaces includeTrackNumber bool
  TextColumn get filenameFormat =>
      text().withDefault(const Constant('discTrack'))();
  BoolColumn get includeYear =>
      boolean().withDefault(const Constant(false))();
  BoolColumn get overwriteExisting =>
      boolean().withDefault(const Constant(false))();
  // v4: per-device transcoding target.
  TextColumn get transcodeFormat =>
      text().withDefault(const Constant('original'))();
  IntColumn get transcodeMaxBitRate => integer().nullable()();
  // v5: bulk-zip download mode. Default-on as of v8 — faster for most setups.
  BoolColumn get useZipDownload =>
      boolean().withDefault(const Constant(true))();
  // v6: custom filename template (only honoured when filenameFormat == custom).
  TextColumn get customFilenameTemplate =>
      text().withDefault(const Constant(''))();
  // v7: custom folder template (only honoured when folderStructure == custom).
  TextColumn get customFolderTemplate =>
      text().withDefault(const Constant(''))();
  // v8: post-transfer FLAC sanitiser + cover-art shrink toggles.
  BoolColumn get autoCleanMetadata =>
      boolean().withDefault(const Constant(true))();
  BoolColumn get autoShrinkCoverArt =>
      boolean().withDefault(const Constant(true))();

  @override
  Set<Column> get primaryKey => {devicePath};
}
