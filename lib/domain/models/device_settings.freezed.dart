// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'device_settings.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$DeviceSettings {

 String get devicePath; String get musicRootFolder; String get playlistFolder; FolderStructure get folderStructure; FilenameFormat get filenameFormat; bool get includeYear; bool get overwriteExisting; TranscodeFormat get transcodeFormat;/// kbps cap passed as `maxBitRate` to Subsonic. Null = no cap (server
/// decides). Only meaningful when [transcodeFormat] != original.
 int? get transcodeMaxBitRate;/// Bulk-download mode: fetches a single zip per album from
/// `/rest/download` and extracts locally instead of one HTTP request per
/// song. Only honoured when [transcodeFormat] is original — the bulk
/// endpoint does not accept transcoding parameters.
 bool get useZipDownload;/// Template string used when [filenameFormat] is [FilenameFormat.custom].
/// Supported tokens: `{track}`, `{disc}`, `{title}`, `{artist}`,
/// `{albumArtist}`, `{album}`, `{year}`. Numeric tokens accept a width
/// suffix: `{track:02}` → `01`, `{disc:02}` → `02`. The file extension is
/// always appended automatically — don't include `.ext` in the template.
 String get customFilenameTemplate;/// Template string used when [folderStructure] is [FolderStructure.custom].
/// Slashes separate path components; each component is sanitised
/// independently. Same tokens as [customFilenameTemplate], minus
/// `{title}` (a folder per song would defeat the purpose).
 String get customFolderTemplate;/// Strip embedded-DAP-parser-hostile tags (multi-line LYRICS, duplicate
/// GENRE, leaked ffmpeg container atoms) from every FLAC as it lands.
 bool get autoCleanMetadata;/// Shrink embedded album art to a 320 px longest edge (Shanling M-series
/// screen height) on transfer. Saves several MB per album; lossless audio
/// stream is untouched.
 bool get autoShrinkCoverArt;
/// Create a copy of DeviceSettings
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DeviceSettingsCopyWith<DeviceSettings> get copyWith => _$DeviceSettingsCopyWithImpl<DeviceSettings>(this as DeviceSettings, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is DeviceSettings&&(identical(other.devicePath, devicePath) || other.devicePath == devicePath)&&(identical(other.musicRootFolder, musicRootFolder) || other.musicRootFolder == musicRootFolder)&&(identical(other.playlistFolder, playlistFolder) || other.playlistFolder == playlistFolder)&&(identical(other.folderStructure, folderStructure) || other.folderStructure == folderStructure)&&(identical(other.filenameFormat, filenameFormat) || other.filenameFormat == filenameFormat)&&(identical(other.includeYear, includeYear) || other.includeYear == includeYear)&&(identical(other.overwriteExisting, overwriteExisting) || other.overwriteExisting == overwriteExisting)&&(identical(other.transcodeFormat, transcodeFormat) || other.transcodeFormat == transcodeFormat)&&(identical(other.transcodeMaxBitRate, transcodeMaxBitRate) || other.transcodeMaxBitRate == transcodeMaxBitRate)&&(identical(other.useZipDownload, useZipDownload) || other.useZipDownload == useZipDownload)&&(identical(other.customFilenameTemplate, customFilenameTemplate) || other.customFilenameTemplate == customFilenameTemplate)&&(identical(other.customFolderTemplate, customFolderTemplate) || other.customFolderTemplate == customFolderTemplate)&&(identical(other.autoCleanMetadata, autoCleanMetadata) || other.autoCleanMetadata == autoCleanMetadata)&&(identical(other.autoShrinkCoverArt, autoShrinkCoverArt) || other.autoShrinkCoverArt == autoShrinkCoverArt));
}


@override
int get hashCode => Object.hash(runtimeType,devicePath,musicRootFolder,playlistFolder,folderStructure,filenameFormat,includeYear,overwriteExisting,transcodeFormat,transcodeMaxBitRate,useZipDownload,customFilenameTemplate,customFolderTemplate,autoCleanMetadata,autoShrinkCoverArt);

@override
String toString() {
  return 'DeviceSettings(devicePath: $devicePath, musicRootFolder: $musicRootFolder, playlistFolder: $playlistFolder, folderStructure: $folderStructure, filenameFormat: $filenameFormat, includeYear: $includeYear, overwriteExisting: $overwriteExisting, transcodeFormat: $transcodeFormat, transcodeMaxBitRate: $transcodeMaxBitRate, useZipDownload: $useZipDownload, customFilenameTemplate: $customFilenameTemplate, customFolderTemplate: $customFolderTemplate, autoCleanMetadata: $autoCleanMetadata, autoShrinkCoverArt: $autoShrinkCoverArt)';
}


}

/// @nodoc
abstract mixin class $DeviceSettingsCopyWith<$Res>  {
  factory $DeviceSettingsCopyWith(DeviceSettings value, $Res Function(DeviceSettings) _then) = _$DeviceSettingsCopyWithImpl;
@useResult
$Res call({
 String devicePath, String musicRootFolder, String playlistFolder, FolderStructure folderStructure, FilenameFormat filenameFormat, bool includeYear, bool overwriteExisting, TranscodeFormat transcodeFormat, int? transcodeMaxBitRate, bool useZipDownload, String customFilenameTemplate, String customFolderTemplate, bool autoCleanMetadata, bool autoShrinkCoverArt
});




}
/// @nodoc
class _$DeviceSettingsCopyWithImpl<$Res>
    implements $DeviceSettingsCopyWith<$Res> {
  _$DeviceSettingsCopyWithImpl(this._self, this._then);

  final DeviceSettings _self;
  final $Res Function(DeviceSettings) _then;

/// Create a copy of DeviceSettings
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? devicePath = null,Object? musicRootFolder = null,Object? playlistFolder = null,Object? folderStructure = null,Object? filenameFormat = null,Object? includeYear = null,Object? overwriteExisting = null,Object? transcodeFormat = null,Object? transcodeMaxBitRate = freezed,Object? useZipDownload = null,Object? customFilenameTemplate = null,Object? customFolderTemplate = null,Object? autoCleanMetadata = null,Object? autoShrinkCoverArt = null,}) {
  return _then(_self.copyWith(
devicePath: null == devicePath ? _self.devicePath : devicePath // ignore: cast_nullable_to_non_nullable
as String,musicRootFolder: null == musicRootFolder ? _self.musicRootFolder : musicRootFolder // ignore: cast_nullable_to_non_nullable
as String,playlistFolder: null == playlistFolder ? _self.playlistFolder : playlistFolder // ignore: cast_nullable_to_non_nullable
as String,folderStructure: null == folderStructure ? _self.folderStructure : folderStructure // ignore: cast_nullable_to_non_nullable
as FolderStructure,filenameFormat: null == filenameFormat ? _self.filenameFormat : filenameFormat // ignore: cast_nullable_to_non_nullable
as FilenameFormat,includeYear: null == includeYear ? _self.includeYear : includeYear // ignore: cast_nullable_to_non_nullable
as bool,overwriteExisting: null == overwriteExisting ? _self.overwriteExisting : overwriteExisting // ignore: cast_nullable_to_non_nullable
as bool,transcodeFormat: null == transcodeFormat ? _self.transcodeFormat : transcodeFormat // ignore: cast_nullable_to_non_nullable
as TranscodeFormat,transcodeMaxBitRate: freezed == transcodeMaxBitRate ? _self.transcodeMaxBitRate : transcodeMaxBitRate // ignore: cast_nullable_to_non_nullable
as int?,useZipDownload: null == useZipDownload ? _self.useZipDownload : useZipDownload // ignore: cast_nullable_to_non_nullable
as bool,customFilenameTemplate: null == customFilenameTemplate ? _self.customFilenameTemplate : customFilenameTemplate // ignore: cast_nullable_to_non_nullable
as String,customFolderTemplate: null == customFolderTemplate ? _self.customFolderTemplate : customFolderTemplate // ignore: cast_nullable_to_non_nullable
as String,autoCleanMetadata: null == autoCleanMetadata ? _self.autoCleanMetadata : autoCleanMetadata // ignore: cast_nullable_to_non_nullable
as bool,autoShrinkCoverArt: null == autoShrinkCoverArt ? _self.autoShrinkCoverArt : autoShrinkCoverArt // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

}


/// Adds pattern-matching-related methods to [DeviceSettings].
extension DeviceSettingsPatterns on DeviceSettings {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _DeviceSettings value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _DeviceSettings() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _DeviceSettings value)  $default,){
final _that = this;
switch (_that) {
case _DeviceSettings():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _DeviceSettings value)?  $default,){
final _that = this;
switch (_that) {
case _DeviceSettings() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String devicePath,  String musicRootFolder,  String playlistFolder,  FolderStructure folderStructure,  FilenameFormat filenameFormat,  bool includeYear,  bool overwriteExisting,  TranscodeFormat transcodeFormat,  int? transcodeMaxBitRate,  bool useZipDownload,  String customFilenameTemplate,  String customFolderTemplate,  bool autoCleanMetadata,  bool autoShrinkCoverArt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _DeviceSettings() when $default != null:
return $default(_that.devicePath,_that.musicRootFolder,_that.playlistFolder,_that.folderStructure,_that.filenameFormat,_that.includeYear,_that.overwriteExisting,_that.transcodeFormat,_that.transcodeMaxBitRate,_that.useZipDownload,_that.customFilenameTemplate,_that.customFolderTemplate,_that.autoCleanMetadata,_that.autoShrinkCoverArt);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String devicePath,  String musicRootFolder,  String playlistFolder,  FolderStructure folderStructure,  FilenameFormat filenameFormat,  bool includeYear,  bool overwriteExisting,  TranscodeFormat transcodeFormat,  int? transcodeMaxBitRate,  bool useZipDownload,  String customFilenameTemplate,  String customFolderTemplate,  bool autoCleanMetadata,  bool autoShrinkCoverArt)  $default,) {final _that = this;
switch (_that) {
case _DeviceSettings():
return $default(_that.devicePath,_that.musicRootFolder,_that.playlistFolder,_that.folderStructure,_that.filenameFormat,_that.includeYear,_that.overwriteExisting,_that.transcodeFormat,_that.transcodeMaxBitRate,_that.useZipDownload,_that.customFilenameTemplate,_that.customFolderTemplate,_that.autoCleanMetadata,_that.autoShrinkCoverArt);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String devicePath,  String musicRootFolder,  String playlistFolder,  FolderStructure folderStructure,  FilenameFormat filenameFormat,  bool includeYear,  bool overwriteExisting,  TranscodeFormat transcodeFormat,  int? transcodeMaxBitRate,  bool useZipDownload,  String customFilenameTemplate,  String customFolderTemplate,  bool autoCleanMetadata,  bool autoShrinkCoverArt)?  $default,) {final _that = this;
switch (_that) {
case _DeviceSettings() when $default != null:
return $default(_that.devicePath,_that.musicRootFolder,_that.playlistFolder,_that.folderStructure,_that.filenameFormat,_that.includeYear,_that.overwriteExisting,_that.transcodeFormat,_that.transcodeMaxBitRate,_that.useZipDownload,_that.customFilenameTemplate,_that.customFolderTemplate,_that.autoCleanMetadata,_that.autoShrinkCoverArt);case _:
  return null;

}
}

}

/// @nodoc


class _DeviceSettings extends DeviceSettings {
  const _DeviceSettings({required this.devicePath, this.musicRootFolder = '', this.playlistFolder = 'Playlists', this.folderStructure = FolderStructure.artistAlbum, this.filenameFormat = FilenameFormat.discTrack, this.includeYear = false, this.overwriteExisting = false, this.transcodeFormat = TranscodeFormat.original, this.transcodeMaxBitRate, this.useZipDownload = true, this.customFilenameTemplate = '', this.customFolderTemplate = '', this.autoCleanMetadata = true, this.autoShrinkCoverArt = true}): super._();
  

@override final  String devicePath;
@override@JsonKey() final  String musicRootFolder;
@override@JsonKey() final  String playlistFolder;
@override@JsonKey() final  FolderStructure folderStructure;
@override@JsonKey() final  FilenameFormat filenameFormat;
@override@JsonKey() final  bool includeYear;
@override@JsonKey() final  bool overwriteExisting;
@override@JsonKey() final  TranscodeFormat transcodeFormat;
/// kbps cap passed as `maxBitRate` to Subsonic. Null = no cap (server
/// decides). Only meaningful when [transcodeFormat] != original.
@override final  int? transcodeMaxBitRate;
/// Bulk-download mode: fetches a single zip per album from
/// `/rest/download` and extracts locally instead of one HTTP request per
/// song. Only honoured when [transcodeFormat] is original — the bulk
/// endpoint does not accept transcoding parameters.
@override@JsonKey() final  bool useZipDownload;
/// Template string used when [filenameFormat] is [FilenameFormat.custom].
/// Supported tokens: `{track}`, `{disc}`, `{title}`, `{artist}`,
/// `{albumArtist}`, `{album}`, `{year}`. Numeric tokens accept a width
/// suffix: `{track:02}` → `01`, `{disc:02}` → `02`. The file extension is
/// always appended automatically — don't include `.ext` in the template.
@override@JsonKey() final  String customFilenameTemplate;
/// Template string used when [folderStructure] is [FolderStructure.custom].
/// Slashes separate path components; each component is sanitised
/// independently. Same tokens as [customFilenameTemplate], minus
/// `{title}` (a folder per song would defeat the purpose).
@override@JsonKey() final  String customFolderTemplate;
/// Strip embedded-DAP-parser-hostile tags (multi-line LYRICS, duplicate
/// GENRE, leaked ffmpeg container atoms) from every FLAC as it lands.
@override@JsonKey() final  bool autoCleanMetadata;
/// Shrink embedded album art to a 320 px longest edge (Shanling M-series
/// screen height) on transfer. Saves several MB per album; lossless audio
/// stream is untouched.
@override@JsonKey() final  bool autoShrinkCoverArt;

/// Create a copy of DeviceSettings
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$DeviceSettingsCopyWith<_DeviceSettings> get copyWith => __$DeviceSettingsCopyWithImpl<_DeviceSettings>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _DeviceSettings&&(identical(other.devicePath, devicePath) || other.devicePath == devicePath)&&(identical(other.musicRootFolder, musicRootFolder) || other.musicRootFolder == musicRootFolder)&&(identical(other.playlistFolder, playlistFolder) || other.playlistFolder == playlistFolder)&&(identical(other.folderStructure, folderStructure) || other.folderStructure == folderStructure)&&(identical(other.filenameFormat, filenameFormat) || other.filenameFormat == filenameFormat)&&(identical(other.includeYear, includeYear) || other.includeYear == includeYear)&&(identical(other.overwriteExisting, overwriteExisting) || other.overwriteExisting == overwriteExisting)&&(identical(other.transcodeFormat, transcodeFormat) || other.transcodeFormat == transcodeFormat)&&(identical(other.transcodeMaxBitRate, transcodeMaxBitRate) || other.transcodeMaxBitRate == transcodeMaxBitRate)&&(identical(other.useZipDownload, useZipDownload) || other.useZipDownload == useZipDownload)&&(identical(other.customFilenameTemplate, customFilenameTemplate) || other.customFilenameTemplate == customFilenameTemplate)&&(identical(other.customFolderTemplate, customFolderTemplate) || other.customFolderTemplate == customFolderTemplate)&&(identical(other.autoCleanMetadata, autoCleanMetadata) || other.autoCleanMetadata == autoCleanMetadata)&&(identical(other.autoShrinkCoverArt, autoShrinkCoverArt) || other.autoShrinkCoverArt == autoShrinkCoverArt));
}


@override
int get hashCode => Object.hash(runtimeType,devicePath,musicRootFolder,playlistFolder,folderStructure,filenameFormat,includeYear,overwriteExisting,transcodeFormat,transcodeMaxBitRate,useZipDownload,customFilenameTemplate,customFolderTemplate,autoCleanMetadata,autoShrinkCoverArt);

@override
String toString() {
  return 'DeviceSettings(devicePath: $devicePath, musicRootFolder: $musicRootFolder, playlistFolder: $playlistFolder, folderStructure: $folderStructure, filenameFormat: $filenameFormat, includeYear: $includeYear, overwriteExisting: $overwriteExisting, transcodeFormat: $transcodeFormat, transcodeMaxBitRate: $transcodeMaxBitRate, useZipDownload: $useZipDownload, customFilenameTemplate: $customFilenameTemplate, customFolderTemplate: $customFolderTemplate, autoCleanMetadata: $autoCleanMetadata, autoShrinkCoverArt: $autoShrinkCoverArt)';
}


}

/// @nodoc
abstract mixin class _$DeviceSettingsCopyWith<$Res> implements $DeviceSettingsCopyWith<$Res> {
  factory _$DeviceSettingsCopyWith(_DeviceSettings value, $Res Function(_DeviceSettings) _then) = __$DeviceSettingsCopyWithImpl;
@override @useResult
$Res call({
 String devicePath, String musicRootFolder, String playlistFolder, FolderStructure folderStructure, FilenameFormat filenameFormat, bool includeYear, bool overwriteExisting, TranscodeFormat transcodeFormat, int? transcodeMaxBitRate, bool useZipDownload, String customFilenameTemplate, String customFolderTemplate, bool autoCleanMetadata, bool autoShrinkCoverArt
});




}
/// @nodoc
class __$DeviceSettingsCopyWithImpl<$Res>
    implements _$DeviceSettingsCopyWith<$Res> {
  __$DeviceSettingsCopyWithImpl(this._self, this._then);

  final _DeviceSettings _self;
  final $Res Function(_DeviceSettings) _then;

/// Create a copy of DeviceSettings
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? devicePath = null,Object? musicRootFolder = null,Object? playlistFolder = null,Object? folderStructure = null,Object? filenameFormat = null,Object? includeYear = null,Object? overwriteExisting = null,Object? transcodeFormat = null,Object? transcodeMaxBitRate = freezed,Object? useZipDownload = null,Object? customFilenameTemplate = null,Object? customFolderTemplate = null,Object? autoCleanMetadata = null,Object? autoShrinkCoverArt = null,}) {
  return _then(_DeviceSettings(
devicePath: null == devicePath ? _self.devicePath : devicePath // ignore: cast_nullable_to_non_nullable
as String,musicRootFolder: null == musicRootFolder ? _self.musicRootFolder : musicRootFolder // ignore: cast_nullable_to_non_nullable
as String,playlistFolder: null == playlistFolder ? _self.playlistFolder : playlistFolder // ignore: cast_nullable_to_non_nullable
as String,folderStructure: null == folderStructure ? _self.folderStructure : folderStructure // ignore: cast_nullable_to_non_nullable
as FolderStructure,filenameFormat: null == filenameFormat ? _self.filenameFormat : filenameFormat // ignore: cast_nullable_to_non_nullable
as FilenameFormat,includeYear: null == includeYear ? _self.includeYear : includeYear // ignore: cast_nullable_to_non_nullable
as bool,overwriteExisting: null == overwriteExisting ? _self.overwriteExisting : overwriteExisting // ignore: cast_nullable_to_non_nullable
as bool,transcodeFormat: null == transcodeFormat ? _self.transcodeFormat : transcodeFormat // ignore: cast_nullable_to_non_nullable
as TranscodeFormat,transcodeMaxBitRate: freezed == transcodeMaxBitRate ? _self.transcodeMaxBitRate : transcodeMaxBitRate // ignore: cast_nullable_to_non_nullable
as int?,useZipDownload: null == useZipDownload ? _self.useZipDownload : useZipDownload // ignore: cast_nullable_to_non_nullable
as bool,customFilenameTemplate: null == customFilenameTemplate ? _self.customFilenameTemplate : customFilenameTemplate // ignore: cast_nullable_to_non_nullable
as String,customFolderTemplate: null == customFolderTemplate ? _self.customFolderTemplate : customFolderTemplate // ignore: cast_nullable_to_non_nullable
as String,autoCleanMetadata: null == autoCleanMetadata ? _self.autoCleanMetadata : autoCleanMetadata // ignore: cast_nullable_to_non_nullable
as bool,autoShrinkCoverArt: null == autoShrinkCoverArt ? _self.autoShrinkCoverArt : autoShrinkCoverArt // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

// dart format on
