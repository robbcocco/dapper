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

  @override
  Set<Column> get primaryKey => {devicePath};
}
