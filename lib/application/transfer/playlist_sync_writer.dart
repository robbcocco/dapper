import 'dart:io';

import 'package:path/path.dart' as p;

import '../../core/extensions/string_extensions.dart';
import '../../domain/models/device_settings.dart';
import '../../domain/models/playlist.dart';
import 'device_manifest.dart';
import 'transfer_path_resolver.dart';

String buildPlaylistPath(Playlist playlist, DeviceSettings settings) {
  final name = playlist.name.toSafeFilename();
  final dir = p.join(settings.devicePath, settings.playlistFolder);
  return p.join(dir, '$name.m3u');
}

Future<void> writePlaylistM3u(
  Playlist playlist,
  DeviceSettings settings,
) async {
  final playlistPath = buildPlaylistPath(playlist, settings);
  final playlistDir = p.dirname(playlistPath);

  // Only include songs that are actually present on device.
  final buf = StringBuffer('#EXTM3U\n');
  var count = 0;
  for (final song in playlist.songs) {
    final songPath = buildSongPath(song, settings);
    if (!await File(songPath).exists()) continue;
    count++;
    // Use forward-slash separators (M1S is Android-based).
    final rel = p.relative(songPath, from: playlistDir).replaceAll(r'\', '/');
    final duration = song.duration ?? -1;
    final artist = song.artist ?? '';
    final display = artist.isNotEmpty ? '$artist - ${song.title}' : song.title;
    buf
      ..write('#EXTINF:$duration,$display\n')
      ..write('$rel\n');
  }

  if (count == 0) return;

  await Directory(playlistDir).create(recursive: true);
  await File(playlistPath).writeAsString(buf.toString());
  await removeMacOSSidecar(playlistPath);
}

bool playlistExistsOnDevice(Playlist playlist, DeviceSettings settings) =>
    File(buildPlaylistPath(playlist, settings)).existsSync();
