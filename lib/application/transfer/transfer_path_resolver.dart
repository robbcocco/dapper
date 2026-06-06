import 'dart:io';

import 'package:path/path.dart' as p;

import '../../core/extensions/string_extensions.dart';
import '../../domain/models/device_settings.dart';
import '../../domain/models/song.dart';
import 'device_manifest.dart';

// FAT32 limit: 255 UTF-16 code units per path component.
const _kMaxPathComponent = 255;

String _trunc(String s, [int max = _kMaxPathComponent]) =>
    s.length > max ? s.substring(0, max) : s;

/// Computes the absolute target path for a song on the device.
String buildSongPath(Song song, DeviceSettings settings) {
  final artist =
      _trunc((song.albumArtist ?? song.artist ?? 'Unknown Artist').toSafeFilename());
  final rawAlbum = _trunc((song.album ?? 'Unknown Album').toSafeFilename());
  final year = song.year;
  final forceYear = settings.folderStructure == FolderStructure.artistAlbumYear;
  final addYear = (forceYear || settings.includeYear) && year != null && year > 0;
  final albumFolder = _trunc(addYear ? '$year - $rawAlbum' : rawAlbum);

  // When transcoding, the file extension follows the target format rather
  // than the source song's suffix (a FLAC sent as MP3 must be named .mp3).
  final ext = settings.transcodeFormat.fileExtension ?? song.suffix ?? 'mp3';
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
  final prefixPart = prefix.isNotEmpty ? '$prefix$sep' : '';
  final dotExt = '.$ext';
  final maxTitle = (_kMaxPathComponent - prefixPart.length - dotExt.length)
      .clamp(1, _kMaxPathComponent);
  final title = _trunc(song.title.toSafeFilename(), maxTitle);
  final filename = '$prefixPart$title$dotExt';

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
  final artist = _trunc((albumArtist ?? 'Unknown Artist').toSafeFilename());
  final rawAlbum = _trunc(albumName.toSafeFilename());
  final forceYear = settings.folderStructure == FolderStructure.artistAlbumYear;
  final addYear = (forceYear || settings.includeYear) && year != null && year > 0;
  final albumFolder = _trunc(addYear ? '$year - $rawAlbum' : rawAlbum);
  return p.join(settings.resolvedMusicRoot, artist, albumFolder);
}

enum AlbumSyncStatus { absent, partial, full }

/// Returns the sync status of an album on the device.
/// [songCount] is the library's expected number of songs.
/// Reads the manifest if present (prefers manifest.expectedSongCount over [songCount]);
/// falls back to audio file count when no manifest exists.
AlbumSyncStatus albumSyncOnDevice(
    String? albumArtist, String albumName, int? year, int songCount, DeviceSettings settings) {
  final folder = buildAlbumFolder(albumArtist, albumName, year, settings);
  if (folder == null) return AlbumSyncStatus.absent;
  if (!folderExistsCached(folder)) return AlbumSyncStatus.absent;

  final manifest = readManifest(folder);
  if (manifest != null) {
    final count = manifest.songs.length;
    if (count == 0) return AlbumSyncStatus.absent;
    final expected = manifest.expectedSongCount ?? songCount;
    if (expected > 0 && count >= expected) return AlbumSyncStatus.full;
    return AlbumSyncStatus.partial;
  }

  // No manifest: scan the directory. This is the slow path, only hit for
  // pre-manifest albums or external file-management cases.
  final fileCount = Directory(folder)
      .listSync()
      .whereType<File>()
      .where(isAudioFile)
      .length;
  if (fileCount == 0) return AlbumSyncStatus.absent;
  if (songCount > 0 && fileCount >= songCount) return AlbumSyncStatus.full;
  return AlbumSyncStatus.partial;
}

/// True if the album folder exists and contains at least one audio file.
bool albumExistsOnDevice(
    String? albumArtist, String albumName, int? year, DeviceSettings settings) {
  final folder = buildAlbumFolder(albumArtist, albumName, year, settings);
  if (folder == null) return false;
  if (!folderExistsCached(folder)) return false;
  final manifest = readManifest(folder);
  if (manifest != null) return manifest.songs.isNotEmpty;
  return Directory(folder).listSync().whereType<File>().any(isAudioFile);
}

/// True if the song is present on the device.
/// Checks the album folder manifest by song ID first (reliable even when the
/// filename differs from the expected pattern); falls back to the file path.
bool songExistsOnDevice(Song song, DeviceSettings settings) {
  final folder = buildAlbumFolder(
    song.albumArtist ?? song.artist,
    song.album ?? 'Unknown Album',
    song.year,
    settings,
  );
  if (folder != null) {
    final manifest = readManifest(folder);
    if (manifest != null) {
      return manifest.songs.any((s) => s.id == song.id);
    }
  }
  return File(buildSongPath(song, settings)).existsSync();
}

/// True if the artist folder exists on device (meaningless for flat structure).
/// Use this as a fallback for structures that don't produce per-album folders.
bool artistFolderExistsOnDevice(String artistName, DeviceSettings settings) {
  if (settings.folderStructure == FolderStructure.flat) return false;
  final dir = Directory(
      p.join(settings.resolvedMusicRoot, artistName.toSafeFilename()));
  return dir.existsSync();
}
