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
  }) = _DeviceSettings;

  const DeviceSettings._();

  String get resolvedMusicRoot {
    if (musicRootFolder.isEmpty) return devicePath;
    return '$devicePath/$musicRootFolder';
  }
}
