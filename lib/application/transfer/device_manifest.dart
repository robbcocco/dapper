import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../domain/models/song.dart';

const _kManifestFilename = '.dapper.json';

const _kAudioExtensions = {
  '.mp3', '.flac', '.m4a', '.aac', '.ogg', '.wav',
  '.opus', '.wma', '.ape', '.aiff', '.dsf', '.dff',
};

bool isAudioFile(File f) {
  final name = p.basename(f.path);
  if (name.startsWith('._')) return false;
  return _kAudioExtensions.contains(p.extension(f.path).toLowerCase());
}

const _kPlaylistExtensions = {'.m3u', '.m3u8'};

bool isPlaylistFile(File f) {
  final name = p.basename(f.path);
  if (name.startsWith('._')) return false;
  return _kPlaylistExtensions.contains(p.extension(f.path).toLowerCase());
}

/// On macOS, removes the AppleDouble sidecar (._filename) that the OS writes
/// when storing extended attributes on FAT32/exFAT volumes, then strips all
/// xattrs from the file so the sidecar is not recreated.
Future<void> removeMacOSSidecar(String filePath) async {
  if (!Platform.isMacOS) return;
  final sidecar =
      File(p.join(p.dirname(filePath), '._${p.basename(filePath)}'));
  if (await sidecar.exists()) {
    try {
      await sidecar.delete();
    } catch (_) {}
  }
  await Process.run('xattr', ['-c', filePath]);
}

class ManifestSong {
  const ManifestSong({
    required this.id,
    required this.title,
    this.artist,
    this.album,
    this.filename,
  });
  final String id;
  final String title;
  final String? artist;
  final String? album;
  /// Exact filename (basename) as written to disk, used for reliable deletion during prune.
  final String? filename;

  factory ManifestSong.fromJson(Map<String, dynamic> j) => ManifestSong(
        id: j['id'] as String,
        title: j['title'] as String,
        artist: j['artist'] as String?,
        album: j['album'] as String?,
        filename: j['filename'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        if (artist != null) 'artist': artist,
        if (album != null) 'album': album,
        if (filename != null) 'filename': filename,
      };
}

class AlbumManifest {
  const AlbumManifest({required this.songs, this.expectedSongCount});
  final List<ManifestSong> songs;

  /// Total number of songs the album should have according to the library.
  /// Written at transfer time (when a full album is enqueued) or during scan.
  /// Used by artistSyncProvider to assess sync completeness without having to
  /// paginate through all albums.
  final int? expectedSongCount;

  factory AlbumManifest.fromJson(Map<String, dynamic> j) {
    final rawSongs = j['songs'];
    if (rawSongs is! List) return const AlbumManifest(songs: []);
    return AlbumManifest(
      songs: rawSongs
          .whereType<Map<String, dynamic>>()
          .map(ManifestSong.fromJson)
          .toList(),
      expectedSongCount: j['expectedSongCount'] as int?,
    );
  }

  Map<String, dynamic> toJson() => {
        'version': 1,
        if (expectedSongCount != null) 'expectedSongCount': expectedSongCount,
        'songs': songs.map((s) => s.toJson()).toList(),
      };
}

AlbumManifest? readManifest(String folderPath) {
  final file = File(p.join(folderPath, _kManifestFilename));
  if (!file.existsSync()) return null;
  try {
    return AlbumManifest.fromJson(
        jsonDecode(file.readAsStringSync()) as Map<String, dynamic>);
  } catch (_) {
    return null;
  }
}

void writeManifest(String folderPath, AlbumManifest manifest) {
  final file = File(p.join(folderPath, _kManifestFilename));
  file.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(manifest.toJson()));
}

void addSongToManifest(String folderPath, Song song,
    {int? expectedSongCount, String? filename}) {
  final existing = readManifest(folderPath);
  final songs = existing?.songs.where((s) => s.id != song.id).toList() ?? [];
  songs.add(ManifestSong(
    id: song.id,
    title: song.title,
    artist: song.albumArtist ?? song.artist,
    album: song.album,
    filename: filename,
  ));
  writeManifest(folderPath, AlbumManifest(
    songs: songs,
    // Prefer the explicitly passed count; fall back to whatever was already stored.
    expectedSongCount: expectedSongCount ?? existing?.expectedSongCount,
  ));
}

Future<void> addSongToManifestAsync(String folderPath, Song song,
    {int? expectedSongCount, String? filename}) async {
  final file = File(p.join(folderPath, _kManifestFilename));
  AlbumManifest? existing;
  if (await file.exists()) {
    try {
      existing = AlbumManifest.fromJson(
          jsonDecode(await file.readAsString()) as Map<String, dynamic>);
    } catch (_) {}
  }
  final songs = existing?.songs.where((s) => s.id != song.id).toList() ?? [];
  songs.add(ManifestSong(
    id: song.id,
    title: song.title,
    artist: song.albumArtist ?? song.artist,
    album: song.album,
    filename: filename,
  ));
  await file.writeAsString(const JsonEncoder.withIndent('  ').convert(
    AlbumManifest(
      songs: songs,
      expectedSongCount: expectedSongCount ?? existing?.expectedSongCount,
    ).toJson(),
  ));
}
