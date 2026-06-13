import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:path/path.dart' as p;

part 'device_settings.freezed.dart';

enum FolderStructure {
  artistAlbum,      // Artist / Album / track
  artistAlbumYear,  // Artist / Year - Album / track
  artistOnly,       // Artist / track
  flat,             // track (all in music root)
  custom,           // user template, see [DeviceSettings.customFolderTemplate]
}

enum FilenameFormat {
  none,       // title.ext
  track,      // 01 title.ext
  discTrack,  // 1-01 - title.ext
  custom,     // user template, see [DeviceSettings.customFilenameTemplate]
}

/// Per-device transcoding target. `original` means "ship whatever the server
/// has" — used for DAPs that can play FLAC/Opus/etc. directly. The other
/// values request that Subsonic transcode on the fly during the transfer.
enum TranscodeFormat {
  original,
  mp3,
  opus,
  aac,
}

extension TranscodeFormatX on TranscodeFormat {
  /// Subsonic API `format` parameter value. `original` returns null so the
  /// caller knows to use the plain /rest/download endpoint instead.
  String? get apiName => switch (this) {
        TranscodeFormat.original => null,
        TranscodeFormat.mp3 => 'mp3',
        TranscodeFormat.opus => 'opus',
        TranscodeFormat.aac => 'aac',
      };

  /// File extension applied to the transferred filename. Returning null
  /// signals "use the source song's own suffix" — only relevant for
  /// [TranscodeFormat.original].
  String? get fileExtension => switch (this) {
        TranscodeFormat.original => null,
        TranscodeFormat.mp3 => 'mp3',
        TranscodeFormat.opus => 'opus',
        TranscodeFormat.aac => 'm4a',
      };

  String get label => switch (this) {
        TranscodeFormat.original => 'Original',
        TranscodeFormat.mp3 => 'MP3',
        TranscodeFormat.opus => 'Opus',
        TranscodeFormat.aac => 'AAC',
      };
}

@freezed
class DeviceSettings with _$DeviceSettings {
  const factory DeviceSettings({
    required String devicePath,
    @Default('') String musicRootFolder,
    @Default('Playlists') String playlistFolder,
    @Default(FolderStructure.artistAlbum) FolderStructure folderStructure,
    @Default(FilenameFormat.discTrack) FilenameFormat filenameFormat,
    @Default(false) bool includeYear,
    @Default(false) bool overwriteExisting,
    @Default(TranscodeFormat.original) TranscodeFormat transcodeFormat,
    /// kbps cap passed as `maxBitRate` to Subsonic. Null = no cap (server
    /// decides). Only meaningful when [transcodeFormat] != original.
    int? transcodeMaxBitRate,
    /// Bulk-download mode: fetches a single zip per album from
    /// `/rest/download` and extracts locally instead of one HTTP request per
    /// song. Only honoured when [transcodeFormat] is original — the bulk
    /// endpoint does not accept transcoding parameters.
    @Default(true) bool useZipDownload,
    /// Template string used when [filenameFormat] is [FilenameFormat.custom].
    /// Supported tokens: `{track}`, `{disc}`, `{title}`, `{artist}`,
    /// `{albumArtist}`, `{album}`, `{year}`. Numeric tokens accept a width
    /// suffix: `{track:02}` → `01`, `{disc:02}` → `02`. The file extension is
    /// always appended automatically — don't include `.ext` in the template.
    @Default('') String customFilenameTemplate,
    /// Template string used when [folderStructure] is [FolderStructure.custom].
    /// Slashes separate path components; each component is sanitised
    /// independently. Same tokens as [customFilenameTemplate], minus
    /// `{title}` (a folder per song would defeat the purpose).
    @Default('') String customFolderTemplate,
    /// Strip embedded-DAP-parser-hostile tags (multi-line LYRICS, duplicate
    /// GENRE, leaked ffmpeg container atoms) from every FLAC as it lands.
    @Default(true) bool autoCleanMetadata,
    /// Shrink embedded album art to a 320 px longest edge (Shanling M-series
    /// screen height) on transfer. Saves several MB per album; lossless audio
    /// stream is untouched.
    @Default(true) bool autoShrinkCoverArt,
  }) = _DeviceSettings;

  const DeviceSettings._();

  /// Absolute path to the music directory on the device. [musicRootFolder]
  /// can be a single folder name (e.g. `Music`) or a nested relative path
  /// (e.g. `Music/FLAC/Library` or `Music\FLAC\Library` on Windows); both
  /// forward and back slashes are accepted and normalised to the platform's
  /// native separator via [p.joinAll].
  String get resolvedMusicRoot {
    final trimmed = musicRootFolder.trim();
    if (trimmed.isEmpty) return devicePath;
    final parts = p.split(trimmed.replaceAll('\\', '/'))
        .where((s) => s.isNotEmpty && s != '.')
        .toList();
    if (parts.isEmpty) return devicePath;
    return p.joinAll([devicePath, ...parts]);
  }

  bool get isTranscoding => transcodeFormat != TranscodeFormat.original;
}

/// Validates a user-entered music-root path. Returns null when valid, or a
/// human-readable reason when invalid (used to render inline error text).
String? validateMusicRootPath(String input) {
  final trimmed = input.trim();
  if (trimmed.isEmpty) return null;
  // Absolute paths would escape the device root.
  if (trimmed.startsWith('/') || trimmed.startsWith('\\')) {
    return 'Use a relative path (no leading slash)';
  }
  if (trimmed.length >= 2 && trimmed[1] == ':') {
    return 'Use a relative path (no drive letter)';
  }
  final segments = trimmed.replaceAll('\\', '/').split('/');
  for (final seg in segments) {
    if (seg == '..') return r"Path cannot contain '..'";
  }
  return null;
}
