import 'package:freezed_annotation/freezed_annotation.dart';

part 'device_settings.freezed.dart';

enum FolderStructure {
  artistAlbum,      // Artist / Album / track
  artistAlbumYear,  // Artist / Year - Album / track
  artistOnly,       // Artist / track
  flat,             // track (all in music root)
}

enum FilenameFormat {
  none,       // title.ext
  track,      // 01 title.ext
  discTrack,  // 1-01 - title.ext
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
  }) = _DeviceSettings;

  const DeviceSettings._();

  String get resolvedMusicRoot {
    if (musicRootFolder.isEmpty) return devicePath;
    return '$devicePath/$musicRootFolder';
  }

  bool get isTranscoding => transcodeFormat != TranscodeFormat.original;
}
