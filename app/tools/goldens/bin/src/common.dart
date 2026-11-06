import 'dart:convert';
import 'dart:io';

import '../../../../../lib/domain/models/device_settings.dart' as px;
import '../../../../../lib/domain/models/song.dart';
import '../copies/windows/device_settings.dart' as wx;

/// app/fixtures/, resolved from this script so the generator is cwd-independent.
final Directory fixturesDir =
    Directory.fromUri(Platform.script.resolve('../../../../fixtures/'));

/// One golden case. [error] is set (and [output] null) when the Dart code
/// threw; it carries the thrown object's runtime type.
class Case {
  Case(this.input, this.output, {this.error, this.note});
  final Object? input;
  final Object? output;
  final String? error;
  final String? note;

  Map<String, Object?> toJson() => {
        'input': input,
        'output': output,
        if (error != null) 'error': error,
        if (note != null) 'note': note,
      };
}

/// Runs [body]; a throw becomes a [Case] carrying the error type.
Case run(Object? input, Object? Function() body) {
  try {
    final out = body();
    return lossyCase(input, out);
  } catch (e) {
    return Case(input, null, error: errorName(e));
  }
}

Future<Case> runAsync(Object? input, Future<Object?> Function() body) async {
  try {
    return lossyCase(input, await body());
  } catch (e) {
    return Case(input, null, error: errorName(e));
  }
}

String errorName(Object e) {
  final t = e.runtimeType.toString();
  // VM-internal subclasses (_TypeError, _Exception…) → public name.
  return t.startsWith('_') ? t.substring(1) : t;
}

/// Dart strings may end up holding lone UTF-16 surrogates after a
/// code-unit truncation; on disk (UTF-8) those become U+FFFD. JSON/Rust
/// strings can't carry them, so outputs replace them with U+FFFD — the same
/// as Rust's `String::from_utf16_lossy` over the truncated code units.
Case lossyCase(Object? input, Object? output) {
  var replaced = false;
  Object? walk(Object? v) {
    if (v is String) {
      final fixed = fixSurrogates(v);
      if (!identical(fixed, v)) replaced = true;
      return fixed;
    }
    if (v is List) return v.map(walk).toList();
    if (v is Map) return v.map((k, val) => MapEntry(k, walk(val)));
    return v;
  }

  final out = walk(output);
  return Case(input, out,
      note: replaced ? 'lone surrogate(s) replaced with U+FFFD' : null);
}

String fixSurrogates(String s) {
  final units = s.codeUnits;
  StringBuffer? buf;
  for (var i = 0; i < units.length; i++) {
    final c = units[i];
    final isHigh = c >= 0xD800 && c <= 0xDBFF;
    final isLow = c >= 0xDC00 && c <= 0xDFFF;
    var lone = false;
    if (isHigh) {
      lone = i + 1 >= units.length ||
          !(units[i + 1] >= 0xDC00 && units[i + 1] <= 0xDFFF);
    } else if (isLow) {
      lone = i == 0 || !(units[i - 1] >= 0xD800 && units[i - 1] <= 0xDBFF);
    }
    if (lone) {
      buf ??= StringBuffer(String.fromCharCodes(units.sublist(0, i)));
      buf.writeCharCode(0xFFFD);
    } else {
      buf?.writeCharCode(c);
    }
  }
  return buf?.toString() ?? s;
}

/// One case per line keeps the files compact yet diffable.
void writeFixture(String name, String description, List<Case> cases) {
  for (final c in cases) {
    // Inputs are authored here and must never need lossy treatment.
    _assertNoLoneSurrogates(c.input);
  }
  final buf = StringBuffer(
      '{\n "description": ${jsonEncode(description)},\n "cases": [\n');
  for (var i = 0; i < cases.length; i++) {
    buf
      ..write('  ')
      ..write(jsonEncode(cases[i].toJson()))
      ..write(i == cases.length - 1 ? '\n' : ',\n');
  }
  buf.write(' ]\n}\n');
  final file = File('${fixturesDir.path}$name.json');
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(buf.toString());
  stdout.writeln('${name.padRight(18)} ${cases.length} cases');
  caseTotal += cases.length;
}

var caseTotal = 0;

void _assertNoLoneSurrogates(Object? v) {
  if (v is String && !identical(fixSurrogates(v), v)) {
    throw StateError('input contains lone surrogate: $v');
  }
  if (v is List) v.forEach(_assertNoLoneSurrogates);
  if (v is Map) v.values.forEach(_assertNoLoneSurrogates);
}

// ── Song ────────────────────────────────────────────────────────────────────

Map<String, Object?> songToJson(Song s) => {
      'id': s.id,
      'title': s.title,
      'albumId': s.albumId,
      'artistId': s.artistId,
      'album': s.album,
      'artist': s.artist,
      'duration': s.duration,
      'bitRate': s.bitRate,
      'contentType': s.contentType,
      'suffix': s.suffix,
      'size': s.size,
      'coverArtId': s.coverArtId,
      'track': s.track,
      'discNumber': s.discNumber,
      'year': s.year,
      'genre': s.genre,
      'albumArtist': s.albumArtist,
      'userRating': s.userRating,
    };

// ── DeviceSettings ──────────────────────────────────────────────────────────

/// Platform-neutral description of a DeviceSettings; converted to the posix
/// (original) or windows (path-context copy) class on demand.
class Settings {
  const Settings({
    required this.devicePath,
    this.musicRootFolder = '',
    this.playlistFolder = 'Playlists',
    this.folderStructure = 'artistAlbum',
    this.filenameFormat = 'discTrack',
    this.includeYear = false,
    this.overwriteExisting = false,
    this.transcodeFormat = 'original',
    this.transcodeMaxBitRate,
    this.useZipDownload = true,
    this.customFilenameTemplate = '',
    this.customFolderTemplate = '',
    this.autoCleanMetadata = true,
    this.autoShrinkCoverArt = true,
  });

  final String devicePath;
  final String musicRootFolder;
  final String playlistFolder;
  final String folderStructure;
  final String filenameFormat;
  final bool includeYear;
  final bool overwriteExisting;
  final String transcodeFormat;
  final int? transcodeMaxBitRate;
  final bool useZipDownload;
  final String customFilenameTemplate;
  final String customFolderTemplate;
  final bool autoCleanMetadata;
  final bool autoShrinkCoverArt;

  Settings copyWith({
    String? devicePath,
    String? musicRootFolder,
    String? playlistFolder,
    String? folderStructure,
    String? filenameFormat,
    bool? includeYear,
    String? transcodeFormat,
    int? transcodeMaxBitRate,
    String? customFilenameTemplate,
    String? customFolderTemplate,
  }) =>
      Settings(
        devicePath: devicePath ?? this.devicePath,
        musicRootFolder: musicRootFolder ?? this.musicRootFolder,
        playlistFolder: playlistFolder ?? this.playlistFolder,
        folderStructure: folderStructure ?? this.folderStructure,
        filenameFormat: filenameFormat ?? this.filenameFormat,
        includeYear: includeYear ?? this.includeYear,
        overwriteExisting: overwriteExisting,
        transcodeFormat: transcodeFormat ?? this.transcodeFormat,
        transcodeMaxBitRate: transcodeMaxBitRate ?? this.transcodeMaxBitRate,
        useZipDownload: useZipDownload,
        customFilenameTemplate:
            customFilenameTemplate ?? this.customFilenameTemplate,
        customFolderTemplate: customFolderTemplate ?? this.customFolderTemplate,
        autoCleanMetadata: autoCleanMetadata,
        autoShrinkCoverArt: autoShrinkCoverArt,
      );

  px.DeviceSettings posix() {
    final s = px.DeviceSettings(
      devicePath: devicePath,
      musicRootFolder: musicRootFolder,
      playlistFolder: playlistFolder,
      folderStructure: px.FolderStructure.values.byName(folderStructure),
      filenameFormat: px.FilenameFormat.values.byName(filenameFormat),
      includeYear: includeYear,
      overwriteExisting: overwriteExisting,
      transcodeFormat: px.TranscodeFormat.values.byName(transcodeFormat),
      transcodeMaxBitRate: transcodeMaxBitRate,
      useZipDownload: useZipDownload,
      customFilenameTemplate: customFilenameTemplate,
      customFolderTemplate: customFolderTemplate,
      autoCleanMetadata: autoCleanMetadata,
      autoShrinkCoverArt: autoShrinkCoverArt,
    );
    _checkRoundTrip(posixSettingsToJson(s));
    return s;
  }

  wx.DeviceSettings windows() => wx.DeviceSettings(
        devicePath: devicePath,
        musicRootFolder: musicRootFolder,
        playlistFolder: playlistFolder,
        folderStructure: wx.FolderStructure.values.byName(folderStructure),
        filenameFormat: wx.FilenameFormat.values.byName(filenameFormat),
        includeYear: includeYear,
        overwriteExisting: overwriteExisting,
        transcodeFormat: wx.TranscodeFormat.values.byName(transcodeFormat),
        transcodeMaxBitRate: transcodeMaxBitRate,
        useZipDownload: useZipDownload,
        customFilenameTemplate: customFilenameTemplate,
        customFolderTemplate: customFolderTemplate,
        autoCleanMetadata: autoCleanMetadata,
        autoShrinkCoverArt: autoShrinkCoverArt,
      );

  Map<String, Object?> toJson() => {
        'devicePath': devicePath,
        'musicRootFolder': musicRootFolder,
        'playlistFolder': playlistFolder,
        'folderStructure': folderStructure,
        'filenameFormat': filenameFormat,
        'includeYear': includeYear,
        'overwriteExisting': overwriteExisting,
        'transcodeFormat': transcodeFormat,
        'transcodeMaxBitRate': transcodeMaxBitRate,
        'useZipDownload': useZipDownload,
        'customFilenameTemplate': customFilenameTemplate,
        'customFolderTemplate': customFolderTemplate,
        'autoCleanMetadata': autoCleanMetadata,
        'autoShrinkCoverArt': autoShrinkCoverArt,
      };

  void _checkRoundTrip(Map<String, Object?> fromDart) {
    final mine = toJson();
    for (final k in mine.keys) {
      if (mine[k] != fromDart[k]) {
        throw StateError('Settings.$k mismatch: ${mine[k]} vs ${fromDart[k]}');
      }
    }
  }
}

/// Serialises the real Dart object so field coverage can't drift from the
/// model: any field added to DeviceSettings must be added here and in
/// [Settings].
Map<String, Object?> posixSettingsToJson(px.DeviceSettings s) => {
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
      'autoCleanMetadata': s.autoCleanMetadata,
      'autoShrinkCoverArt': s.autoShrinkCoverArt,
    };
