import 'dart:io';

import 'package:path/path.dart' as p;

import '../../core/extensions/string_extensions.dart';
import '../../domain/models/device_settings.dart';
import '../../domain/models/playlist.dart';
import 'transfer_path_resolver.dart';

String buildPlaylistPath(Playlist playlist, DeviceSettings settings) {
  final name = playlist.name.toSafeFilename();
  final dir = p.join(settings.resolvedMusicRoot, settings.playlistFolder);
  return p.join(dir, '$name.m3u');
}

Future<void> writePlaylistM3u(
  Playlist playlist,
  DeviceSettings settings,
) async {
  final playlistPath = buildPlaylistPath(playlist, settings);
  final playlistDir = p.dirname(playlistPath);

  await Directory(playlistDir).create(recursive: true);

  final buf = StringBuffer('#EXTM3U\n');
  for (final song in playlist.songs) {
    final songPath = buildSongPath(song, settings);
    // Use forward-slash separators (M1S is Android-based).
    final rel = p.relative(songPath, from: playlistDir).replaceAll(r'\', '/');
    final duration = song.duration ?? -1;
    final artist = song.artist ?? '';
    final display = artist.isNotEmpty ? '$artist - ${song.title}' : song.title;
    buf
      ..write('#EXTINF:$duration,$display\n')
      ..write('$rel\n');
  }

  await File(playlistPath).writeAsString(buf.toString());
}

bool playlistExistsOnDevice(Playlist playlist, DeviceSettings settings) =>
    File(buildPlaylistPath(playlist, settings)).existsSync();
