import 'dart:io';

import 'package:path/path.dart' as p;

import '../../core/extensions/string_extensions.dart';
import '../../domain/models/device_settings.dart';
import '../../domain/models/song.dart';

/// Computes the absolute target path for a song on the device.
String buildSongPath(Song song, DeviceSettings settings) {
  final artist =
      (song.albumArtist ?? song.artist ?? 'Unknown Artist').toSafeFilename();
  final rawAlbum = (song.album ?? 'Unknown Album').toSafeFilename();
  final year = song.year;
  final forceYear = settings.folderStructure == FolderStructure.artistAlbumYear;
  final addYear = (forceYear || settings.includeYear) && year != null && year > 0;
  final albumFolder = addYear ? '$year - $rawAlbum' : rawAlbum;

  final ext = song.suffix ?? 'mp3';
  final title = song.title.toSafeFilename();
  final trackNum = song.track;
  final disc = song.discNumber ?? 1;
  final prefix = switch (settings.filenameFormat) {
    FilenameFormat.none => '',
    FilenameFormat.track =>
      trackNum != null ? trackNum.toString().padLeft(2, '0') : '',
    FilenameFormat.discTrack =>
      trackNum != null ? '$disc-${trackNum.toString().padLeft(2, '0')}' : '',
  };
  final sep = settings.filenameFormat == FilenameFormat.discTrack ? ' - ' : ' ';
  final filename =
      prefix.isNotEmpty ? '$prefix$sep$title.$ext' : '$title.$ext';

  final root = settings.resolvedMusicRoot;
  return switch (settings.folderStructure) {
    FolderStructure.artistAlbum => p.join(root, artist, albumFolder, filename),
    FolderStructure.artistAlbumYear =>
      p.join(root, artist, albumFolder, filename),
    FolderStructure.artistOnly => p.join(root, artist, filename),
    FolderStructure.flat => p.join(root, filename),
  };
}

/// Returns the expected directory for an album on the device.
/// Returns null for structures that don't produce a distinct per-album folder
/// (flat, artistOnly), since we can't reliably detect per-album sync there.
String? buildAlbumFolder(
    String? albumArtist, String albumName, int? year, DeviceSettings settings) {
  if (settings.folderStructure == FolderStructure.flat ||
      settings.folderStructure == FolderStructure.artistOnly) {
    return null;
  }
  final artist = (albumArtist ?? 'Unknown Artist').toSafeFilename();
  final rawAlbum = albumName.toSafeFilename();
  final forceYear = settings.folderStructure == FolderStructure.artistAlbumYear;
  final addYear = (forceYear || settings.includeYear) && year != null && year > 0;
  final albumFolder = addYear ? '$year - $rawAlbum' : rawAlbum;
  return p.join(settings.resolvedMusicRoot, artist, albumFolder);
}

/// True if the album folder exists and contains at least one file.
bool albumExistsOnDevice(
    String? albumArtist, String albumName, int? year, DeviceSettings settings) {
  final folder = buildAlbumFolder(albumArtist, albumName, year, settings);
  if (folder == null) return false;
  final dir = Directory(folder);
  if (!dir.existsSync()) return false;
  return dir.listSync().any((e) => e is File);
}

/// True if the song file already exists at its expected device path.
bool songExistsOnDevice(Song song, DeviceSettings settings) =>
    File(buildSongPath(song, settings)).existsSync();
