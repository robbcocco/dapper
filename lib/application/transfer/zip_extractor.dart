import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;

import '../../domain/models/device_settings.dart';
import '../../domain/models/song.dart';
import 'device_manifest.dart';
import 'transfer_path_resolver.dart';

// ── Isolate-boundary marshalling ──────────────────────────────────────────────
// Freezed objects can fail to cross an isolate boundary on some Dart runtime
// configurations ("Illegal argument in isolate" / "Invalid argument(s)"). We
// avoid the issue entirely by serialising the inputs to Map<String, dynamic>
// before crossing, and rebuilding plain Dart objects inside the isolate.

Map<String, dynamic> songToMap(Song s) => {
      'id': s.id,
      'title': s.title,
      if (s.albumId != null) 'albumId': s.albumId,
      if (s.artistId != null) 'artistId': s.artistId,
      if (s.album != null) 'album': s.album,
      if (s.artist != null) 'artist': s.artist,
      if (s.duration != null) 'duration': s.duration,
      if (s.bitRate != null) 'bitRate': s.bitRate,
      if (s.contentType != null) 'contentType': s.contentType,
      if (s.suffix != null) 'suffix': s.suffix,
      if (s.size != null) 'size': s.size,
      if (s.coverArtId != null) 'coverArtId': s.coverArtId,
      if (s.track != null) 'track': s.track,
      if (s.discNumber != null) 'discNumber': s.discNumber,
      if (s.year != null) 'year': s.year,
      if (s.genre != null) 'genre': s.genre,
      if (s.albumArtist != null) 'albumArtist': s.albumArtist,
      if (s.userRating != null) 'userRating': s.userRating,
    };

Song songFromMap(Map<String, dynamic> m) => Song(
      id: m['id'] as String,
      title: m['title'] as String,
      albumId: m['albumId'] as String?,
      artistId: m['artistId'] as String?,
      album: m['album'] as String?,
      artist: m['artist'] as String?,
      duration: m['duration'] as int?,
      bitRate: m['bitRate'] as int?,
      contentType: m['contentType'] as String?,
      suffix: m['suffix'] as String?,
      size: m['size'] as int?,
      coverArtId: m['coverArtId'] as String?,
      track: m['track'] as int?,
      discNumber: m['discNumber'] as int?,
      year: m['year'] as int?,
      genre: m['genre'] as String?,
      albumArtist: m['albumArtist'] as String?,
      userRating: m['userRating'] as int?,
    );

Map<String, dynamic> settingsToMap(DeviceSettings s) => {
      'devicePath': s.devicePath,
      'musicRootFolder': s.musicRootFolder,
      'playlistFolder': s.playlistFolder,
      'folderStructure': s.folderStructure.name,
      'filenameFormat': s.filenameFormat.name,
      'includeYear': s.includeYear,
      'overwriteExisting': s.overwriteExisting,
      'transcodeFormat': s.transcodeFormat.name,
      'transcodeMaxBitRate': s.transcodeMaxBitRate,
      'useZipDownload': s.useZipDownload,
      'customFilenameTemplate': s.customFilenameTemplate,
      'customFolderTemplate': s.customFolderTemplate,
    };

DeviceSettings settingsFromMap(Map<String, dynamic> m) => DeviceSettings(
      devicePath: m['devicePath'] as String,
      musicRootFolder: (m['musicRootFolder'] as String?) ?? '',
      playlistFolder: (m['playlistFolder'] as String?) ?? 'Playlists',
      folderStructure: FolderStructure.values.firstWhere(
          (e) => e.name == m['folderStructure'],
          orElse: () => FolderStructure.artistAlbum),
      filenameFormat: FilenameFormat.values.firstWhere(
          (e) => e.name == m['filenameFormat'],
          orElse: () => FilenameFormat.discTrack),
      includeYear: (m['includeYear'] as bool?) ?? false,
      overwriteExisting: (m['overwriteExisting'] as bool?) ?? false,
      transcodeFormat: TranscodeFormat.values.firstWhere(
          (e) => e.name == m['transcodeFormat'],
          orElse: () => TranscodeFormat.original),
      transcodeMaxBitRate: m['transcodeMaxBitRate'] as int?,
      useZipDownload: (m['useZipDownload'] as bool?) ?? true,
      customFilenameTemplate: (m['customFilenameTemplate'] as String?) ?? '',
      customFolderTemplate: (m['customFolderTemplate'] as String?) ?? '',
    );

/// Isolate-entry wrapper that takes & returns only Map/List/String/int/bool
/// values so the `Isolate.run` boundary never has to serialise a Freezed
/// class. The engine calls this; the rest of the code base uses
/// [extractAlbumZip] directly.
Future<Map<String, dynamic>> extractAlbumZipMarshalled(
    Map<String, dynamic> args) async {
  final songs = (args['songs'] as List)
      .cast<Map>()
      .map((m) => songFromMap(Map<String, dynamic>.from(m)))
      .toList();
  final settings =
      settingsFromMap(Map<String, dynamic>.from(args['settings'] as Map));
  final r = await extractAlbumZip(
    zipPath: args['zipPath'] as String,
    expectedSongs: songs,
    settings: settings,
    removeMacosSidecars: (args['removeMacosSidecars'] as bool?) ?? false,
  );
  return {
    'extracted': [
      for (final e in r.extracted)
        {
          'songId': e.songId,
          'targetPath': e.targetPath,
          if (e.expectedCount != null) 'expectedCount': e.expectedCount,
        }
    ],
    'skipped': r.skipped,
  };
}

/// One song successfully written by [extractAlbumZip].
class ExtractedSong {
  const ExtractedSong({
    required this.songId,
    required this.targetPath,
    this.expectedCount,
  });
  final String songId;
  final String targetPath;
  final int? expectedCount;
}

/// Result of [extractAlbumZip]. [extracted] is every song that landed on
/// disk (with its final path); [skipped] carries human-readable reasons for
/// entries that didn't make it (parent traversal, no match, write failures).
class ZipExtractResult {
  ZipExtractResult({
    required this.extracted,
    required this.skipped,
  });
  final List<ExtractedSong> extracted;
  final List<String> skipped;

  Set<String> get matchedSongIds =>
      {for (final e in extracted) e.songId};
}

/// Pure extract phase of the bulk-zip transfer pipeline. No callbacks, no
/// state — designed so the engine can drop the whole thing inside an
/// `Isolate.run` and unblock the UI during decompression.
///
/// Streams [zipPath] from disk, matches each entry to an expected song,
/// writes to `buildSongPath(song, settings)`, and (optionally) strips macOS
/// AppleDouble sidecars inline. Returns the per-entry outcome so the caller
/// can update task state and write manifests on the main isolate.
///
/// Why all-or-nothing instead of streaming via callbacks: passing a
/// `void Function(...)` across an isolate boundary isn't allowed. Granular
/// per-song UI feedback during extract is sacrificed in exchange for not
/// blocking the main isolate during decompression — the extract phase is
/// short compared to the download phase, so this trade is a net win.
Future<ZipExtractResult> extractAlbumZip({
  required String zipPath,
  required List<Song> expectedSongs,
  required DeviceSettings settings,
  bool removeMacosSidecars = false,
  bool Function()? isCancelled,
}) async {
  // Per-album-folder expected count: every song slots into the album folder
  // its (artist, album, year) resolves to. Album-zip collapses to one
  // folder; artist-zip carries multiple. Written into each .dapper.json so
  // artistSyncProvider can tell partial from full syncs.
  final expectedPerFolder = <String, int>{};
  for (final song in expectedSongs) {
    final folder = buildAlbumFolder(
      song.albumArtist ?? song.artist,
      song.album ?? 'Unknown Album',
      song.year,
      settings,
    );
    if (folder == null) continue;
    expectedPerFolder[folder] = (expectedPerFolder[folder] ?? 0) + 1;
  }

  final extracted = <ExtractedSong>[];
  final skipped = <String>[];
  final rootNorm = p.normalize(settings.resolvedMusicRoot);
  final matchedIds = <String>{};

  // InputFileStream MUST stay open across the entry loop: each entry
  // decompresses lazily from it during writeContent.
  final input = InputFileStream(zipPath);
  try {
    final archive = ZipDecoder().decodeBuffer(input);

    for (final entry in archive) {
      if (isCancelled?.call() ?? false) break;
      if (!entry.isFile) continue;
      final name = entry.name;
      if (name.contains('..')) {
        skipped.add('parent traversal: $name');
        continue;
      }

      final song = matchZipEntry(name, expectedSongs);
      if (song == null) {
        skipped.add('no match: $name');
        continue;
      }
      if (matchedIds.contains(song.id)) continue;

      final target = buildSongPath(song, settings);
      if (!p.isWithin(rootNorm, p.normalize(target))) {
        skipped.add('escaped music root: $target');
        continue;
      }
      final expectedCount = expectedPerFolder[p.dirname(target)];

      // Skip-if-exists: when the user has not opted into overwriting,
      // existing files are accepted as already-transferred so we don't
      // overwrite a tag-edited file with the server's untouched copy.
      if (!settings.overwriteExisting && await File(target).exists()) {
        matchedIds.add(song.id);
        extracted.add(ExtractedSong(
          songId: song.id,
          targetPath: target,
          expectedCount: expectedCount,
        ));
        continue;
      }

      await Directory(p.dirname(target)).create(recursive: true);
      final output = OutputFileStream(target);
      var ok = false;
      try {
        entry.writeContent(output);
        ok = true;
      } catch (e) {
        // Corrupt entry, archive package range error, etc.: log + skip
        // rather than abort the whole group. Other songs still extract.
        skipped.add('write failed for ${entry.name}: $e');
      }
      await output.close();
      if (!ok) {
        try {
          final f = File(target);
          if (await f.exists()) await f.delete();
        } catch (_) {}
        continue;
      }
      if (removeMacosSidecars) {
        await removeMacOSSidecar(target);
      }

      matchedIds.add(song.id);
      extracted.add(ExtractedSong(
        songId: song.id,
        targetPath: target,
        expectedCount: expectedCount,
      ));
    }
  } finally {
    await input.close();
  }

  return ZipExtractResult(extracted: extracted, skipped: skipped);
}
