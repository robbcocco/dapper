import 'dart:io';

import 'package:path/path.dart' as p;

import '../../core/extensions/string_extensions.dart';
import '../../domain/models/device_settings.dart';
import '../../domain/models/song.dart';
import '../../domain/repositories/library_repository.dart';
import '../transfer/device_manifest.dart';
import '../transfer/transfer_path_resolver.dart';

/// A song ID that was found in two or more album folders (cross-folder duplicate).
class DeviceDuplicate {
  const DeviceDuplicate({
    required this.songId,
    required this.title,
    required this.folderPaths,
  });
  final String songId;
  final String title;
  final List<String> folderPaths;
}

/// Multiple audio files sharing the same track-number prefix in one folder.
/// [correctFilename] is the file whose title matches the manifest — null when
/// the correct file cannot be determined automatically.
class FileDuplicate {
  const FileDuplicate({
    required this.folderPath,
    required this.filenames,
    this.correctFilename,
  });
  final String folderPath;
  final List<String> filenames;
  final String? correctFilename;

  bool get canResolve => correctFilename != null;

  List<String> get deletable => correctFilename == null
      ? []
      : filenames.where((f) => f != correctFilename).toList();
}

class DeviceScanResult {
  const DeviceScanResult({
    required this.albumsScanned,
    required this.albumsMatched,
    required this.songsMatched,
    required this.songsTotal,
    required this.manifestDuplicates,
    required this.fileDuplicates,
  });
  final int albumsScanned;
  final int albumsMatched;
  final int songsMatched;

  /// Distinct Subsonic song IDs present on the device after the scan
  /// (existing manifest entries + newly matched).
  final int songsTotal;

  /// Same Subsonic song ID present in multiple album folders.
  final List<DeviceDuplicate> manifestDuplicates;

  /// Multiple audio files with the same track-number prefix in one folder.
  final List<FileDuplicate> fileDuplicates;

  bool get hasDuplicates =>
      manifestDuplicates.isNotEmpty || fileDuplicates.isNotEmpty;

  DeviceScanResult withoutFileDuplicate(FileDuplicate dup) => DeviceScanResult(
        albumsScanned: albumsScanned,
        albumsMatched: albumsMatched,
        songsMatched: songsMatched,
        songsTotal: songsTotal,
        manifestDuplicates: manifestDuplicates,
        fileDuplicates: fileDuplicates.where((d) => d != dup).toList(),
      );
}

Future<DeviceScanResult> scanDevice(
  DeviceSettings settings,
  LibraryRepository repo, {
  void Function(String)? onProgress,
}) async {
  // Phase 1: library-aware scan (manifest building + cross-folder duplicates).
  final songFolders = <String, List<String>>{};
  final songTitles = <String, String>{};
  int albumsScanned = 0;
  int albumsMatched = 0;
  int songsMatched = 0;

  if (settings.folderStructure != FolderStructure.flat &&
      settings.folderStructure != FolderStructure.artistOnly) {
    void trackSong(ManifestSong ms, String folder) {
      songTitles.putIfAbsent(ms.id, () => ms.title);
      songFolders.putIfAbsent(ms.id, () => []).add(folder);
    }

    int offset = 0;
    while (true) {
      onProgress?.call('Loading albums… ($offset loaded)');
      final albums = await repo.getAllAlbums(size: 100, offset: offset);
      if (albums.isEmpty) break;
      offset += albums.length;

      for (final album in albums) {
        albumsScanned++;
        final folder =
            buildAlbumFolder(album.artist, album.name, album.year, settings);
        if (folder == null) continue;
        if (!Directory(folder).existsSync()) continue;

        final existing = readManifest(folder);
        for (final ms in existing?.songs ?? <ManifestSong>[]) {
          trackSong(ms, folder);
        }

        final existingIds = existing?.songs.map((s) => s.id).toSet() ?? {};

        final audioFiles = Directory(folder)
            .listSync()
            .whereType<File>()
            .where(isAudioFile)
            .map((f) => p.basenameWithoutExtension(f.path))
            .toSet();

        if (audioFiles.isEmpty) continue;
        albumsMatched++;

        if (existingIds.length < album.songCount) {
          onProgress?.call('Scanning "${album.name}"…');
          try {
            final fullAlbum = await repo.getAlbum(album.id);
            final newEntries = <ManifestSong>[];

            for (final song in fullAlbum.songs) {
              if (existingIds.contains(song.id)) continue;
              if (audioFiles.contains(_filenameWithoutExt(song, settings))) {
                final ms = ManifestSong(
                  id: song.id,
                  title: song.title,
                  artist: song.albumArtist ?? song.artist,
                  album: song.album,
                );
                newEntries.add(ms);
                trackSong(ms, folder);
              }
            }

            if (newEntries.isNotEmpty) {
              writeManifest(
                folder,
                AlbumManifest(
                  songs: [
                    ...existing?.songs ?? <ManifestSong>[],
                    ...newEntries,
                  ],
                  expectedSongCount: album.songCount,
                ),
              );
              songsMatched += newEntries.length;
            } else if (existing != null &&
                existing.expectedSongCount != album.songCount) {
              // Manifest exists but lacks the expected count — update it.
              writeManifest(
                folder,
                AlbumManifest(
                  songs: existing.songs,
                  expectedSongCount: album.songCount,
                ),
              );
            }
          } catch (_) {
            // Skip albums that fail to load from the server.
          }
        }
      }
    }
  }

  final manifestDuplicates = songFolders.entries
      .where((e) => e.value.length > 1)
      .map((e) => DeviceDuplicate(
            songId: e.key,
            title: songTitles[e.key] ?? e.key,
            folderPaths: e.value,
          ))
      .toList();

  // Phase 2: filesystem walk — detect intra-folder duplicates by track prefix.
  onProgress?.call('Checking for file duplicates…');
  final fileDuplicates = <FileDuplicate>[];
  final root = Directory(settings.resolvedMusicRoot);
  if (root.existsSync()) {
    _collectFileDuplicates(root, fileDuplicates, settings);
  }

  return DeviceScanResult(
    albumsScanned: albumsScanned,
    albumsMatched: albumsMatched,
    songsMatched: songsMatched,
    songsTotal: songFolders.length,
    manifestDuplicates: manifestDuplicates,
    fileDuplicates: fileDuplicates,
  );
}

void _collectFileDuplicates(
  Directory dir,
  List<FileDuplicate> out,
  DeviceSettings settings,
) {
  // Build set of manifest-known safe titles for this directory.
  final manifest = readManifest(dir.path);
  final manifestTitles =
      manifest?.songs.map((s) => s.title.toSafeFilename()).toSet() ??
          const <String>{};

  final prefixGroups = <String, List<String>>{};
  for (final entity in dir.listSync()) {
    if (entity is File && isAudioFile(entity)) {
      final base = p.basenameWithoutExtension(entity.path);
      final prefix = _trackPrefix(base);
      if (prefix != null) {
        prefixGroups
            .putIfAbsent(prefix, () => [])
            .add(p.basename(entity.path));
      }
    } else if (entity is Directory &&
        !p.basename(entity.path).startsWith('.')) {
      _collectFileDuplicates(entity, out, settings);
    }
  }

  for (final entry in prefixGroups.entries) {
    if (entry.value.length > 1) {
      // The correct file is the one whose title portion matches a manifest entry.
      String? correct;
      if (manifestTitles.isNotEmpty) {
        for (final filename in entry.value) {
          final baseNoExt = p.basenameWithoutExtension(filename);
          final titlePart = _stripTrackPrefix(baseNoExt, settings);
          if (titlePart != null && manifestTitles.contains(titlePart)) {
            correct = filename;
            break;
          }
        }
      }
      out.add(FileDuplicate(
        folderPath: dir.path,
        filenames: entry.value,
        correctFilename: correct,
      ));
    }
  }
}

/// Extracts the leading numeric track prefix, e.g. "1-06" or "06".
String? _trackPrefix(String filename) {
  final match = RegExp(r'^\d+(?:-\d+)?').firstMatch(filename);
  return match?.group(0);
}

/// Strips the track prefix (and separator) from a filename, returning just
/// the title portion. Returns null if the prefix cannot be stripped.
String? _stripTrackPrefix(String filename, DeviceSettings settings) {
  return switch (settings.filenameFormat) {
    FilenameFormat.discTrack => () {
        final m = RegExp(r'^\d+-\d+ - ').firstMatch(filename);
        return m != null ? filename.substring(m.end) : null;
      }(),
    FilenameFormat.track => () {
        final m = RegExp(r'^\d+ ').firstMatch(filename);
        return m != null ? filename.substring(m.end) : null;
      }(),
    FilenameFormat.none => filename,
    // Custom templates may put arbitrary content before the title; no reliable
    // strip pattern, fall back to returning the filename as-is.
    FilenameFormat.custom => filename,
  };
}

String _filenameWithoutExt(Song song, DeviceSettings settings) {
  if (settings.filenameFormat == FilenameFormat.custom) {
    final rendered =
        renderFilenameTemplate(settings.customFilenameTemplate, song);
    final safe = rendered.toSafeFilename();
    return safe.isEmpty ? song.title.toSafeFilename() : safe;
  }
  final title = song.title.toSafeFilename();
  final trackNum = song.track;
  final disc = song.discNumber ?? 1;
  final prefix = switch (settings.filenameFormat) {
    FilenameFormat.none => '',
    FilenameFormat.track =>
      trackNum != null ? trackNum.toString().padLeft(2, '0') : '',
    FilenameFormat.discTrack =>
      trackNum != null ? '$disc-${trackNum.toString().padLeft(2, '0')}' : '',
    FilenameFormat.custom => '', // unreachable, handled above
  };
  final sep =
      settings.filenameFormat == FilenameFormat.discTrack ? ' - ' : ' ';
  return prefix.isNotEmpty ? '$prefix$sep$title' : title;
}
