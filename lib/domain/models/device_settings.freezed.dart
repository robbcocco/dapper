// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'device_settings.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
  'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models',
);

/// @nodoc
mixin _$DeviceSettings {
  String get devicePath => throw _privateConstructorUsedError;
  String get musicRootFolder => throw _privateConstructorUsedError;
  String get playlistFolder => throw _privateConstructorUsedError;
  FolderStructure get folderStructure => throw _privateConstructorUsedError;
  FilenameFormat get filenameFormat => throw _privateConstructorUsedError;
  bool get includeYear => throw _privateConstructorUsedError;
  bool get overwriteExisting => throw _privateConstructorUsedError;
  TranscodeFormat get transcodeFormat => throw _privateConstructorUsedError;

  /// kbps cap passed as `maxBitRate` to Subsonic. Null = no cap (server
  /// decides). Only meaningful when [transcodeFormat] != original.
  int? get transcodeMaxBitRate => throw _privateConstructorUsedError;

  /// Bulk-download mode: fetches a single zip per album from
  /// `/rest/download` and extracts locally instead of one HTTP request per
  /// song. Only honoured when [transcodeFormat] is original — the bulk
  /// endpoint does not accept transcoding parameters.
  bool get useZipDownload => throw _privateConstructorUsedError;

  /// Template string used when [filenameFormat] is [FilenameFormat.custom].
  /// Supported tokens: `{track}`, `{disc}`, `{title}`, `{artist}`,
  /// `{albumArtist}`, `{album}`, `{year}`. Numeric tokens accept a width
  /// suffix: `{track:02}` → `01`, `{disc:02}` → `02`. The file extension is
  /// always appended automatically — don't include `.ext` in the template.
  String get customFilenameTemplate => throw _privateConstructorUsedError;

  /// Template string used when [folderStructure] is [FolderStructure.custom].
  /// Slashes separate path components; each component is sanitised
  /// independently. Same tokens as [customFilenameTemplate], minus
  /// `{title}` (a folder per song would defeat the purpose).
  String get customFolderTemplate => throw _privateConstructorUsedError;

  /// Create a copy of DeviceSettings
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $DeviceSettingsCopyWith<DeviceSettings> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $DeviceSettingsCopyWith<$Res> {
  factory $DeviceSettingsCopyWith(
    DeviceSettings value,
    $Res Function(DeviceSettings) then,
  ) = _$DeviceSettingsCopyWithImpl<$Res, DeviceSettings>;
  @useResult
  $Res call({
    String devicePath,
    String musicRootFolder,
    String playlistFolder,
    FolderStructure folderStructure,
    FilenameFormat filenameFormat,
    bool includeYear,
    bool overwriteExisting,
    TranscodeFormat transcodeFormat,
    int? transcodeMaxBitRate,
    bool useZipDownload,
    String customFilenameTemplate,
    String customFolderTemplate,
  });
}

/// @nodoc
class _$DeviceSettingsCopyWithImpl<$Res, $Val extends DeviceSettings>
    implements $DeviceSettingsCopyWith<$Res> {
  _$DeviceSettingsCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of DeviceSettings
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? devicePath = null,
    Object? musicRootFolder = null,
    Object? playlistFolder = null,
    Object? folderStructure = null,
    Object? filenameFormat = null,
    Object? includeYear = null,
    Object? overwriteExisting = null,
    Object? transcodeFormat = null,
    Object? transcodeMaxBitRate = freezed,
    Object? useZipDownload = null,
    Object? customFilenameTemplate = null,
    Object? customFolderTemplate = null,
  }) {
    return _then(
      _value.copyWith(
            devicePath: null == devicePath
                ? _value.devicePath
                : devicePath // ignore: cast_nullable_to_non_nullable
                      as String,
            musicRootFolder: null == musicRootFolder
                ? _value.musicRootFolder
                : musicRootFolder // ignore: cast_nullable_to_non_nullable
                      as String,
            playlistFolder: null == playlistFolder
                ? _value.playlistFolder
                : playlistFolder // ignore: cast_nullable_to_non_nullable
                      as String,
            folderStructure: null == folderStructure
                ? _value.folderStructure
                : folderStructure // ignore: cast_nullable_to_non_nullable
                      as FolderStructure,
            filenameFormat: null == filenameFormat
                ? _value.filenameFormat
                : filenameFormat // ignore: cast_nullable_to_non_nullable
                      as FilenameFormat,
            includeYear: null == includeYear
                ? _value.includeYear
                : includeYear // ignore: cast_nullable_to_non_nullable
                      as bool,
            overwriteExisting: null == overwriteExisting
                ? _value.overwriteExisting
                : overwriteExisting // ignore: cast_nullable_to_non_nullable
                      as bool,
            transcodeFormat: null == transcodeFormat
                ? _value.transcodeFormat
                : transcodeFormat // ignore: cast_nullable_to_non_nullable
                      as TranscodeFormat,
            transcodeMaxBitRate: freezed == transcodeMaxBitRate
                ? _value.transcodeMaxBitRate
                : transcodeMaxBitRate // ignore: cast_nullable_to_non_nullable
                      as int?,
            useZipDownload: null == useZipDownload
                ? _value.useZipDownload
                : useZipDownload // ignore: cast_nullable_to_non_nullable
                      as bool,
            customFilenameTemplate: null == customFilenameTemplate
                ? _value.customFilenameTemplate
                : customFilenameTemplate // ignore: cast_nullable_to_non_nullable
                      as String,
            customFolderTemplate: null == customFolderTemplate
                ? _value.customFolderTemplate
                : customFolderTemplate // ignore: cast_nullable_to_non_nullable
                      as String,
          )
          as $Val,
    );
  }
}

/// @nodoc
abstract class _$$DeviceSettingsImplCopyWith<$Res>
    implements $DeviceSettingsCopyWith<$Res> {
  factory _$$DeviceSettingsImplCopyWith(
    _$DeviceSettingsImpl value,
    $Res Function(_$DeviceSettingsImpl) then,
  ) = __$$DeviceSettingsImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({
    String devicePath,
    String musicRootFolder,
    String playlistFolder,
    FolderStructure folderStructure,
    FilenameFormat filenameFormat,
    bool includeYear,
    bool overwriteExisting,
    TranscodeFormat transcodeFormat,
    int? transcodeMaxBitRate,
    bool useZipDownload,
    String customFilenameTemplate,
    String customFolderTemplate,
  });
}

/// @nodoc
class __$$DeviceSettingsImplCopyWithImpl<$Res>
    extends _$DeviceSettingsCopyWithImpl<$Res, _$DeviceSettingsImpl>
    implements _$$DeviceSettingsImplCopyWith<$Res> {
  __$$DeviceSettingsImplCopyWithImpl(
    _$DeviceSettingsImpl _value,
    $Res Function(_$DeviceSettingsImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of DeviceSettings
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? devicePath = null,
    Object? musicRootFolder = null,
    Object? playlistFolder = null,
    Object? folderStructure = null,
    Object? filenameFormat = null,
    Object? includeYear = null,
    Object? overwriteExisting = null,
    Object? transcodeFormat = null,
    Object? transcodeMaxBitRate = freezed,
    Object? useZipDownload = null,
    Object? customFilenameTemplate = null,
    Object? customFolderTemplate = null,
  }) {
    return _then(
      _$DeviceSettingsImpl(
        devicePath: null == devicePath
            ? _value.devicePath
            : devicePath // ignore: cast_nullable_to_non_nullable
                  as String,
        musicRootFolder: null == musicRootFolder
            ? _value.musicRootFolder
            : musicRootFolder // ignore: cast_nullable_to_non_nullable
                  as String,
        playlistFolder: null == playlistFolder
            ? _value.playlistFolder
            : playlistFolder // ignore: cast_nullable_to_non_nullable
                  as String,
        folderStructure: null == folderStructure
            ? _value.folderStructure
            : folderStructure // ignore: cast_nullable_to_non_nullable
                  as FolderStructure,
        filenameFormat: null == filenameFormat
            ? _value.filenameFormat
            : filenameFormat // ignore: cast_nullable_to_non_nullable
                  as FilenameFormat,
        includeYear: null == includeYear
            ? _value.includeYear
            : includeYear // ignore: cast_nullable_to_non_nullable
                  as bool,
        overwriteExisting: null == overwriteExisting
            ? _value.overwriteExisting
            : overwriteExisting // ignore: cast_nullable_to_non_nullable
                  as bool,
        transcodeFormat: null == transcodeFormat
            ? _value.transcodeFormat
            : transcodeFormat // ignore: cast_nullable_to_non_nullable
                  as TranscodeFormat,
        transcodeMaxBitRate: freezed == transcodeMaxBitRate
            ? _value.transcodeMaxBitRate
            : transcodeMaxBitRate // ignore: cast_nullable_to_non_nullable
                  as int?,
        useZipDownload: null == useZipDownload
            ? _value.useZipDownload
            : useZipDownload // ignore: cast_nullable_to_non_nullable
                  as bool,
        customFilenameTemplate: null == customFilenameTemplate
            ? _value.customFilenameTemplate
            : customFilenameTemplate // ignore: cast_nullable_to_non_nullable
                  as String,
        customFolderTemplate: null == customFolderTemplate
            ? _value.customFolderTemplate
            : customFolderTemplate // ignore: cast_nullable_to_non_nullable
                  as String,
      ),
    );
  }
}

/// @nodoc

class _$DeviceSettingsImpl extends _DeviceSettings {
  const _$DeviceSettingsImpl({
    required this.devicePath,
    this.musicRootFolder = '',
    this.playlistFolder = 'Playlists',
    this.folderStructure = FolderStructure.artistAlbum,
    this.filenameFormat = FilenameFormat.discTrack,
    this.includeYear = false,
    this.overwriteExisting = false,
    this.transcodeFormat = TranscodeFormat.original,
    this.transcodeMaxBitRate,
    this.useZipDownload = true,
    this.customFilenameTemplate = '',
    this.customFolderTemplate = '',
  }) : super._();

  @override
  final String devicePath;
  @override
  @JsonKey()
  final String musicRootFolder;
  @override
  @JsonKey()
  final String playlistFolder;
  @override
  @JsonKey()
  final FolderStructure folderStructure;
  @override
  @JsonKey()
  final FilenameFormat filenameFormat;
  @override
  @JsonKey()
  final bool includeYear;
  @override
  @JsonKey()
  final bool overwriteExisting;
  @override
  @JsonKey()
  final TranscodeFormat transcodeFormat;

  /// kbps cap passed as `maxBitRate` to Subsonic. Null = no cap (server
  /// decides). Only meaningful when [transcodeFormat] != original.
  @override
  final int? transcodeMaxBitRate;

  /// Bulk-download mode: fetches a single zip per album from
  /// `/rest/download` and extracts locally instead of one HTTP request per
  /// song. Only honoured when [transcodeFormat] is original — the bulk
  /// endpoint does not accept transcoding parameters.
  @override
  @JsonKey()
  final bool useZipDownload;

  /// Template string used when [filenameFormat] is [FilenameFormat.custom].
  /// Supported tokens: `{track}`, `{disc}`, `{title}`, `{artist}`,
  /// `{albumArtist}`, `{album}`, `{year}`. Numeric tokens accept a width
  /// suffix: `{track:02}` → `01`, `{disc:02}` → `02`. The file extension is
  /// always appended automatically — don't include `.ext` in the template.
  @override
  @JsonKey()
  final String customFilenameTemplate;

  /// Template string used when [folderStructure] is [FolderStructure.custom].
  /// Slashes separate path components; each component is sanitised
  /// independently. Same tokens as [customFilenameTemplate], minus
  /// `{title}` (a folder per song would defeat the purpose).
  @override
  @JsonKey()
  final String customFolderTemplate;

  @override
  String toString() {
    return 'DeviceSettings(devicePath: $devicePath, musicRootFolder: $musicRootFolder, playlistFolder: $playlistFolder, folderStructure: $folderStructure, filenameFormat: $filenameFormat, includeYear: $includeYear, overwriteExisting: $overwriteExisting, transcodeFormat: $transcodeFormat, transcodeMaxBitRate: $transcodeMaxBitRate, useZipDownload: $useZipDownload, customFilenameTemplate: $customFilenameTemplate, customFolderTemplate: $customFolderTemplate)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$DeviceSettingsImpl &&
            (identical(other.devicePath, devicePath) ||
                other.devicePath == devicePath) &&
            (identical(other.musicRootFolder, musicRootFolder) ||
                other.musicRootFolder == musicRootFolder) &&
            (identical(other.playlistFolder, playlistFolder) ||
                other.playlistFolder == playlistFolder) &&
            (identical(other.folderStructure, folderStructure) ||
                other.folderStructure == folderStructure) &&
            (identical(other.filenameFormat, filenameFormat) ||
                other.filenameFormat == filenameFormat) &&
            (identical(other.includeYear, includeYear) ||
                other.includeYear == includeYear) &&
            (identical(other.overwriteExisting, overwriteExisting) ||
                other.overwriteExisting == overwriteExisting) &&
            (identical(other.transcodeFormat, transcodeFormat) ||
                other.transcodeFormat == transcodeFormat) &&
            (identical(other.transcodeMaxBitRate, transcodeMaxBitRate) ||
                other.transcodeMaxBitRate == transcodeMaxBitRate) &&
            (identical(other.useZipDownload, useZipDownload) ||
                other.useZipDownload == useZipDownload) &&
            (identical(other.customFilenameTemplate, customFilenameTemplate) ||
                other.customFilenameTemplate == customFilenameTemplate) &&
            (identical(other.customFolderTemplate, customFolderTemplate) ||
                other.customFolderTemplate == customFolderTemplate));
  }

  @override
  int get hashCode => Object.hash(
    runtimeType,
    devicePath,
    musicRootFolder,
    playlistFolder,
    folderStructure,
    filenameFormat,
    includeYear,
    overwriteExisting,
    transcodeFormat,
    transcodeMaxBitRate,
    useZipDownload,
    customFilenameTemplate,
    customFolderTemplate,
  );

  /// Create a copy of DeviceSettings
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$DeviceSettingsImplCopyWith<_$DeviceSettingsImpl> get copyWith =>
      __$$DeviceSettingsImplCopyWithImpl<_$DeviceSettingsImpl>(
        this,
        _$identity,
      );
}

abstract class _DeviceSettings extends DeviceSettings {
  const factory _DeviceSettings({
    required final String devicePath,
    final String musicRootFolder,
    final String playlistFolder,
    final FolderStructure folderStructure,
    final FilenameFormat filenameFormat,
    final bool includeYear,
    final bool overwriteExisting,
    final TranscodeFormat transcodeFormat,
    final int? transcodeMaxBitRate,
    final bool useZipDownload,
    final String customFilenameTemplate,
    final String customFolderTemplate,
  }) = _$DeviceSettingsImpl;
  const _DeviceSettings._() : super._();

  @override
  String get devicePath;
  @override
  String get musicRootFolder;
  @override
  String get playlistFolder;
  @override
  FolderStructure get folderStructure;
  @override
  FilenameFormat get filenameFormat;
  @override
  bool get includeYear;
  @override
  bool get overwriteExisting;
  @override
  TranscodeFormat get transcodeFormat;

  /// kbps cap passed as `maxBitRate` to Subsonic. Null = no cap (server
  /// decides). Only meaningful when [transcodeFormat] != original.
  @override
  int? get transcodeMaxBitRate;

  /// Bulk-download mode: fetches a single zip per album from
  /// `/rest/download` and extracts locally instead of one HTTP request per
  /// song. Only honoured when [transcodeFormat] is original — the bulk
  /// endpoint does not accept transcoding parameters.
  @override
  bool get useZipDownload;

  /// Template string used when [filenameFormat] is [FilenameFormat.custom].
  /// Supported tokens: `{track}`, `{disc}`, `{title}`, `{artist}`,
  /// `{albumArtist}`, `{album}`, `{year}`. Numeric tokens accept a width
  /// suffix: `{track:02}` → `01`, `{disc:02}` → `02`. The file extension is
  /// always appended automatically — don't include `.ext` in the template.
  @override
  String get customFilenameTemplate;

  /// Template string used when [folderStructure] is [FolderStructure.custom].
  /// Slashes separate path components; each component is sanitised
  /// independently. Same tokens as [customFilenameTemplate], minus
  /// `{title}` (a folder per song would defeat the purpose).
  @override
  String get customFolderTemplate;

  /// Create a copy of DeviceSettings
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$DeviceSettingsImplCopyWith<_$DeviceSettingsImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
