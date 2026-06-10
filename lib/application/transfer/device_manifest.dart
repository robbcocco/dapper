import 'dart:convert';
import 'dart:developer' as dev;
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
    } catch (e) {
      dev.log('removeMacOSSidecar: could not delete ${sidecar.path} — $e');
    }
  }
  try {
    final result = await Process.run('xattr', ['-c', filePath]);
    if (result.exitCode != 0) {
      // Common on read-only volumes; without this the OS will recreate the
      // sidecar next time the file is read.
      dev.log(
          'removeMacOSSidecar: xattr -c $filePath exited ${result.exitCode}: '
          '${result.stderr}');
    }
  } catch (e) {
    dev.log('removeMacOSSidecar: failed to invoke xattr on $filePath — $e');
  }
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

// In-memory cache of parsed manifests keyed by absolute folder path. Hit by
// every song-row and album-card on every transfer-status change; without it
// the UI thread reads + parses .dapper.json hundreds of times per second
// during active transfers. Writers (writeManifest / addSongToManifest*) update
// the cache atomically with disk so reads stay consistent.
//
// Cache entry sentinel: a key present with a null value means "we already
// checked and the file does not exist". This avoids repeated negative-lookup
// syscalls when many rows ask about an album that's not on the device.
//
// Both caches are LinkedHashMap (Dart's default Map insertion-order semantics)
// + capped via promote-on-read so that very large libraries can't grow the
// caches without bound. The cap is generous — most users won't hit it — but
// stops a 50,000-album scan from leaking memory permanently.
const _kManifestCacheCap = 4096;
const _kFolderExistsCacheCap = 8192;
final _manifestCache = <String, AlbumManifest?>{};
// Mirror cache for album-folder Directory.existsSync() — same access pattern,
// same hot path inside albumSyncOnDevice.
final _folderExistsCache = <String, bool>{};

void _putManifest(String key, AlbumManifest? value) {
  _manifestCache.remove(key);
  _manifestCache[key] = value;
  if (_manifestCache.length > _kManifestCacheCap) {
    _manifestCache.remove(_manifestCache.keys.first);
  }
}

void _putFolderExists(String key, bool value) {
  _folderExistsCache.remove(key);
  _folderExistsCache[key] = value;
  if (_folderExistsCache.length > _kFolderExistsCacheCap) {
    _folderExistsCache.remove(_folderExistsCache.keys.first);
  }
}

AlbumManifest? readManifest(String folderPath) {
  if (_manifestCache.containsKey(folderPath)) {
    // LRU promote-on-read so frequently-touched albums stay hot when the cap
    // is reached.
    final v = _manifestCache.remove(folderPath);
    _manifestCache[folderPath] = v;
    return v;
  }
  final file = File(p.join(folderPath, _kManifestFilename));
  if (!file.existsSync()) {
    _putManifest(folderPath, null);
    return null;
  }
  try {
    final m = AlbumManifest.fromJson(
        jsonDecode(file.readAsStringSync()) as Map<String, dynamic>);
    _putManifest(folderPath, m);
    return m;
  } catch (_) {
    _putManifest(folderPath, null);
    return null;
  }
}

/// Cached `Directory(folderPath).existsSync()`. The cache is invalidated when
/// we write a manifest into that folder (since a write implies the directory
/// now exists), and globally on device replug via [clearDeviceCaches].
bool folderExistsCached(String folderPath) {
  final cached = _folderExistsCache[folderPath];
  if (cached != null) {
    // Promote-on-read for the same reason as the manifest cache.
    _folderExistsCache.remove(folderPath);
    _folderExistsCache[folderPath] = cached;
    return cached;
  }
  final exists = Directory(folderPath).existsSync();
  _putFolderExists(folderPath, exists);
  return exists;
}

/// Clears the in-memory manifest / folder-exists caches. Call this on device
/// plug-out / change so stale entries from a previous device don't bleed into
/// the new one (different mount path coincidentally reusing the same root).
void clearDeviceCaches() {
  _manifestCache.clear();
  _folderExistsCache.clear();
}

// Atomic write: serialise to a sibling .tmp file then rename over the target.
// `rename` is atomic on a single filesystem (POSIX, NTFS, FAT32) so a crash or
// unplug between write and rename leaves the previous manifest intact rather
// than half-written.
void writeManifest(String folderPath, AlbumManifest manifest) {
  final target = File(p.join(folderPath, _kManifestFilename));
  final tmp = File(p.join(folderPath, '$_kManifestFilename.tmp'));
  tmp.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(manifest.toJson()),
      flush: true);
  tmp.renameSync(target.path);
  _putManifest(folderPath, manifest);
  _putFolderExists(folderPath, true);
}

Future<void> _writeManifestAtomic(
    String folderPath, AlbumManifest manifest) async {
  final target = File(p.join(folderPath, _kManifestFilename));
  final tmp = File(p.join(folderPath, '$_kManifestFilename.tmp'));
  await tmp.writeAsString(
      const JsonEncoder.withIndent('  ').convert(manifest.toJson()),
      flush: true);
  await tmp.rename(target.path);
  _putManifest(folderPath, manifest);
  _putFolderExists(folderPath, true);
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
  await addSongsToManifestAsync(folderPath, [
    (song: song, filename: filename),
  ], expectedSongCount: expectedSongCount);
}

/// Reads the manifest once, replaces any existing entries by id, appends every
/// new song, and writes once. Batches an arbitrary number of songs into a
/// single read+write cycle — when a full album's worth of files land at once
/// (zip extract), this is dramatically faster than calling
/// [addSongToManifestAsync] per song.
Future<void> addSongsToManifestAsync(
  String folderPath,
  List<({Song song, String? filename})> entries, {
  int? expectedSongCount,
}) async {
  if (entries.isEmpty) return;
  final file = File(p.join(folderPath, _kManifestFilename));
  AlbumManifest? existing;
  if (await file.exists()) {
    try {
      existing = AlbumManifest.fromJson(
          jsonDecode(await file.readAsString()) as Map<String, dynamic>);
    } catch (_) {}
  }
  final newIds = {for (final e in entries) e.song.id};
  final songs =
      existing?.songs.where((s) => !newIds.contains(s.id)).toList() ?? [];
  for (final e in entries) {
    songs.add(ManifestSong(
      id: e.song.id,
      title: e.song.title,
      artist: e.song.albumArtist ?? e.song.artist,
      album: e.song.album,
      filename: e.filename,
    ));
  }
  await _writeManifestAtomic(
    folderPath,
    AlbumManifest(
      songs: songs,
      expectedSongCount: expectedSongCount ?? existing?.expectedSongCount,
    ),
  );
}
