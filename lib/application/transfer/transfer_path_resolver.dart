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
  final dotExt = '.$ext';
  final filename = _composeFilename(song, settings, dotExt);

  final root = settings.resolvedMusicRoot;
  return switch (settings.folderStructure) {
    FolderStructure.artistAlbum => p.join(root, artist, albumFolder, filename),
    FolderStructure.artistAlbumYear =>
      p.join(root, artist, albumFolder, filename),
    FolderStructure.artistOnly => p.join(root, artist, filename),
    FolderStructure.flat => p.join(root, filename),
    FolderStructure.custom => p.joinAll([
        root,
        ..._renderFolderTemplate(settings.customFolderTemplate, song),
        filename,
      ]),
  };
}

/// Splits [template] on `/` separators, renders each component via
/// [renderFilenameTemplate], sanitises and truncates to FAT32-safe lengths.
/// Empty components (e.g. trailing slash) are dropped.
List<String> _renderFolderTemplate(String template, Song song) {
  if (template.trim().isEmpty) return const [];
  return template
      .replaceAll('\\', '/')
      .split('/')
      // Drop empty segments BEFORE rendering — an empty template segment
      // would otherwise fall through to renderFilenameTemplate's title
      // fallback and accidentally inject the track title as a folder name.
      .where((segment) => segment.trim().isNotEmpty)
      .map((segment) => renderFilenameTemplate(segment, song))
      .map((s) => _trunc(s.toSafeFilename()))
      .where((s) => s.isNotEmpty)
      .toList();
}

/// Validates a user-entered folder template. Returns null when usable.
String? validateFolderTemplate(String template) {
  final trimmed = template.trim();
  if (trimmed.isEmpty) return 'Template cannot be empty';
  // Must reference at least one varying token so siblings don't collide; we
  // pick {album} as the minimum since {artist} alone would group everything
  // by artist (artistOnly preset already does that).
  if (!trimmed.contains('{album}') && !trimmed.contains('{artist}')) {
    return 'Template must include {album} or {artist}';
  }
  if (trimmed.contains('{title}')) {
    return 'Folder template cannot include {title}';
  }
  return null;
}

String _composeFilename(Song song, DeviceSettings settings, String dotExt) {
  final trackNum = song.track;
  final disc = song.discNumber ?? 1;

  if (settings.filenameFormat == FilenameFormat.custom) {
    final rendered = renderFilenameTemplate(
        settings.customFilenameTemplate, song);
    // Sanitize the whole rendered string as a single component, then clip to
    // fit the FAT32 component cap (extension included).
    final safe = rendered.toSafeFilename();
    final maxBase = (_kMaxPathComponent - dotExt.length)
        .clamp(1, _kMaxPathComponent);
    return '${_trunc(safe.isEmpty ? song.title.toSafeFilename() : safe, maxBase)}$dotExt';
  }

  final prefix = switch (settings.filenameFormat) {
    FilenameFormat.none => '',
    FilenameFormat.track =>
      trackNum != null ? trackNum.toString().padLeft(2, '0') : '',
    FilenameFormat.discTrack =>
      trackNum != null ? '$disc-${trackNum.toString().padLeft(2, '0')}' : '',
    FilenameFormat.custom => '', // unreachable, handled above
  };
  final sep = settings.filenameFormat == FilenameFormat.discTrack ? ' - ' : ' ';
  final prefixPart = prefix.isNotEmpty ? '$prefix$sep' : '';
  final maxTitle = (_kMaxPathComponent - prefixPart.length - dotExt.length)
      .clamp(1, _kMaxPathComponent);
  final title = _trunc(song.title.toSafeFilename(), maxTitle);
  return '$prefixPart$title$dotExt';
}

final _kTemplateToken = RegExp(r'\{(\w+)(?::(\d+))?\}');

/// Renders [template] with tokens substituted from [song]. Unknown tokens are
/// kept verbatim so a typo is visible in the preview. The result is NOT
/// sanitized — callers should run [String.toSafeFilename] before writing.
///
/// Supported tokens:
///   - `{track}`, `{track:N}` — track number, optionally zero-padded to N digits
///   - `{disc}`,  `{disc:N}`  — disc number
///   - `{year}`,  `{year:N}`  — year
///   - `{title}`              — song title
///   - `{artist}`             — song artist (falls back to album artist)
///   - `{albumArtist}`        — album artist (falls back to artist)
///   - `{album}`              — album name
String renderFilenameTemplate(String template, Song song) {
  if (template.isEmpty) return song.title;
  return template.replaceAllMapped(_kTemplateToken, (m) {
    final key = m.group(1)!;
    final width = m.group(2);
    final raw = _tokenValue(key, song);
    if (raw == null) return m.group(0)!;
    if (width != null) {
      final n = int.tryParse(raw);
      if (n != null) {
        final w = int.parse(width);
        return n.toString().padLeft(w, '0');
      }
    }
    return raw;
  });
}

String? _tokenValue(String key, Song song) {
  switch (key) {
    case 'track':
      return song.track?.toString();
    case 'disc':
      return (song.discNumber ?? 1).toString();
    case 'year':
      return song.year?.toString();
    case 'title':
      return song.title;
    case 'artist':
      return song.artist ?? song.albumArtist;
    case 'albumArtist':
      return song.albumArtist ?? song.artist;
    case 'album':
      return song.album;
    default:
      return null;
  }
}

/// Validates a user-entered filename template. Returns null when usable, or a
/// human-readable reason. The template must yield distinct filenames across a
/// typical album — enforced by requiring `{title}` or `{track}` somewhere.
String? validateFilenameTemplate(String template) {
  final trimmed = template.trim();
  if (trimmed.isEmpty) return 'Template cannot be empty';
  if (!trimmed.contains('{title}') && !trimmed.contains('{track')) {
    return 'Template must include {title} or {track} to avoid collisions';
  }
  if (trimmed.contains('/') || trimmed.contains(r'\')) {
    return 'Template cannot contain path separators';
  }
  return null;
}

/// Returns the expected directory for an album on the device.
/// Returns null for structures that don't produce a distinct per-album folder
/// (flat, artistOnly), since we can't reliably detect per-album sync there.
/// For [FolderStructure.custom] returns the rendered template — the caller
/// gets a partial sync only if the template references `{album}` (the
/// [validateFolderTemplate] requires this).
String? buildAlbumFolder(
    String? albumArtist, String albumName, int? year, DeviceSettings settings) {
  if (settings.folderStructure == FolderStructure.flat ||
      settings.folderStructure == FolderStructure.artistOnly) {
    return null;
  }
  if (settings.folderStructure == FolderStructure.custom) {
    // Synthesise a Song carrying only the fields the folder template uses,
    // so this lookup matches what buildSongPath would render for any song
    // in this album.
    final synthetic = Song(
      id: '__album__',
      title: '',
      album: albumName,
      artist: albumArtist,
      albumArtist: albumArtist,
      year: year,
    );
    final parts =
        _renderFolderTemplate(settings.customFolderTemplate, synthetic);
    if (parts.isEmpty) return null;
    return p.joinAll([settings.resolvedMusicRoot, ...parts]);
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

/// True if the song's audio file is on disk at its expected target path.
/// Always hits the filesystem — bypasses the manifest cache so a stale
/// manifest entry (file deleted, manifest left over) can't trick a skip-this-
/// download decision into firing. Use this for transfer-engine decisions;
/// use [songExistsOnDevice] for UI indicators where the manifest's
/// performance is worth the trust trade-off.
///
/// MTP devices: `dart:io.File("mtp://...").existsSync()` silently returns
/// false (no crash). Until an async-warmed sync facade lands, MTP devices
/// will report "absent" here even when the file is present. The transfer
/// engine's overwrite-skip decision uses async `fs.exists` so this only
/// affects UI badges, not correctness.
bool songFileExistsOnDevice(Song song, DeviceSettings settings) =>
    File(buildSongPath(song, settings)).existsSync();

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
  // For custom templates we can't know which path component represents the
  // artist without parsing — give up rather than guess wrong.
  if (settings.folderStructure == FolderStructure.custom) return false;
  final dir = Directory(
      p.join(settings.resolvedMusicRoot, artistName.toSafeFilename()));
  return dir.existsSync();
}

/// Matches a zip entry's archive path against the expected song list.
///
/// Track number in the filename is authoritative: if any expected song has
/// a `track` value that appears as a numeric token in the basename, the
/// match must come from that subset — title overlap can't override it.
/// Title overlap is only consulted to tie-break candidates with the same
/// track, or to handle filenames that carry no track number at all.
///
/// Reasoning:
///   * Server-rendered filenames like `Artist - Album - 11 - Title.flac`
///     carry the track in the middle. Earlier "leading digit" parsing missed
///     it; now any digit run in the basename counts.
///   * Earlier interludes share prefixes with later ones ("Interlude II" is
///     a prefix of "Interlude III"). Letting the track number trump title
///     similarity stops the III file from being routed to the II song.
Song? matchZipEntry(String entryPath, List<Song> expected) {
  if (expected.isEmpty) return null;
  final basename = p.basenameWithoutExtension(entryPath);
  final normFull = _normaliseTitle(basename);
  if (normFull.isEmpty) return null;
  final tokens = _allNumericTokens(basename);

  // Track-first: build the subset of candidates whose track number is in the
  // basename. If only one matches, that's the answer regardless of title.
  final byTrack = <Song>[];
  for (final song in expected) {
    final t = song.track;
    if (t != null && t > 0 && tokens.contains(t)) byTrack.add(song);
  }

  if (byTrack.length == 1) return byTrack.first;

  if (byTrack.length > 1) {
    // Multi-track collisions (multi-disc albums, or coincidental token hits):
    // narrow by disc number when the filename also references it, then fall
    // back to title overlap inside the narrowed pool.
    final byDisc = byTrack.where((s) {
      final d = s.discNumber ?? 1;
      return d > 0 && tokens.contains(d);
    }).toList();
    final pool = byDisc.length == 1 ? byDisc : byTrack;
    return _bestTitleOverlap(pool, normFull);
  }

  // No song's track number appears in the basename — title overlap is all
  // we've got.
  return _bestTitleOverlap(expected, normFull);
}

Song? _bestTitleOverlap(List<Song> candidates, String normFull) {
  Song? best;
  var bestScore = 0;
  for (final s in candidates) {
    final norm = _normaliseTitle(s.title);
    if (norm.isEmpty) continue;
    final int score;
    if (norm == normFull) {
      // Exact match: stop scanning — nothing beats this.
      return s;
    } else if (normFull.contains(norm)) {
      score = norm.length;
    } else if (norm.contains(normFull)) {
      // Filename shorter than song title — credit half so titles inside the
      // expected list don't randomly win on tiny basenames.
      score = normFull.length ~/ 2;
    } else {
      continue;
    }
    if (score > bestScore) {
      bestScore = score;
      best = s;
    }
  }
  return best;
}

String _normaliseTitle(String s) {
  final lower = s.toLowerCase();
  final buf = StringBuffer();
  for (final r in lower.runes) {
    if ((r >= 0x30 && r <= 0x39) ||
        (r >= 0x61 && r <= 0x7a) ||
        r > 0x7f) {
      buf.writeCharCode(r);
    }
  }
  return buf.toString();
}

/// All decimal-digit runs in [s] parsed as ints. Used to cheaply check if
/// a song's (track, disc) numbers appear anywhere in the entry name — works
/// whether the track is at the start ("01 - Title"), in the middle
/// ("Artist - Album - 01 - Title"), or zero-padded.
List<int> _allNumericTokens(String s) {
  final result = <int>[];
  var i = 0;
  while (i < s.length) {
    if (!_isAsciiDigit(s.codeUnitAt(i))) {
      i++;
      continue;
    }
    var n = 0;
    while (i < s.length && _isAsciiDigit(s.codeUnitAt(i))) {
      n = n * 10 + (s.codeUnitAt(i) - 0x30);
      i++;
    }
    result.add(n);
  }
  return result;
}

bool _isAsciiDigit(int c) => c >= 0x30 && c <= 0x39;
