import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'tables/albums_table.dart';
import 'tables/artists_table.dart';
import 'tables/device_settings_table.dart';
import 'tables/songs_table.dart';

part 'app_database.g.dart';

@DriftDatabase(tables: [ArtistsTable, AlbumsTable, SongsTable, DeviceSettingsTable])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  @override
  int get schemaVersion => 8;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        onUpgrade: (m, from, to) async {
          if (from < 2) await m.createTable(deviceSettingsTable);
          if (from < 3) {
            // Adds filenameFormat; old includeTrackNumber column stays in DB
            // but is no longer read by Drift (ignored extra column).
            await m.addColumn(
                deviceSettingsTable, deviceSettingsTable.filenameFormat);
          }
          if (from < 4) {
            // Per-device transcoding target.
            await m.addColumn(
                deviceSettingsTable, deviceSettingsTable.transcodeFormat);
            await m.addColumn(
                deviceSettingsTable, deviceSettingsTable.transcodeMaxBitRate);
          }
          if (from < 5) {
            await m.addColumn(
                deviceSettingsTable, deviceSettingsTable.useZipDownload);
          }
          if (from < 6) {
            await m.addColumn(deviceSettingsTable,
                deviceSettingsTable.customFilenameTemplate);
          }
          if (from < 7) {
            await m.addColumn(deviceSettingsTable,
                deviceSettingsTable.customFolderTemplate);
          }
          if (from < 8) {
            await m.addColumn(deviceSettingsTable,
                deviceSettingsTable.autoCleanMetadata);
            await m.addColumn(deviceSettingsTable,
                deviceSettingsTable.autoShrinkCoverArt);
          }
        },
      );

  // ── Artists ──────────────────────────────────────────────────────────────

  Future<void> upsertArtists(List<ArtistsTableCompanion> rows) async {
    await batch((b) {
      b.insertAllOnConflictUpdate(artistsTable, rows);
    });
  }

  Future<List<ArtistsTableData>> getAllArtists() =>
      select(artistsTable).get();

  // ── Albums ───────────────────────────────────────────────────────────────

  Future<void> upsertAlbums(List<AlbumsTableCompanion> rows) async {
    await batch((b) {
      b.insertAllOnConflictUpdate(albumsTable, rows);
    });
  }

  Future<List<AlbumsTableData>> getAlbumsByArtist(String artistId) =>
      (select(albumsTable)..where((t) => t.artistId.equals(artistId))).get();

  // ── Songs ─────────────────────────────────────────────────────────────────

  Future<void> upsertSongs(List<SongsTableCompanion> rows) async {
    await batch((b) {
      b.insertAllOnConflictUpdate(songsTable, rows);
    });
  }

  Future<List<SongsTableData>> getSongsByAlbum(String albumId) =>
      (select(songsTable)..where((t) => t.albumId.equals(albumId))).get();

  // ── Device settings ───────────────────────────────────────────────────────

  Future<DeviceSettingsTableData?> getDeviceSettings(String devicePath) =>
      (select(deviceSettingsTable)
            ..where((t) => t.devicePath.equals(devicePath)))
          .getSingleOrNull();

  Future<List<DeviceSettingsTableData>> getAllDeviceSettings() =>
      select(deviceSettingsTable).get();

  Future<void> upsertDeviceSettings(DeviceSettingsTableCompanion row) =>
      into(deviceSettingsTable).insertOnConflictUpdate(row);
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dir = await getApplicationSupportDirectory();
    final file = File(p.join(dir.path, 'dapper.db'));
    return NativeDatabase.createInBackground(file);
  });
}
