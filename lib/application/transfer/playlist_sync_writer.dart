import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../core/extensions/string_extensions.dart';
import '../../domain/models/device_settings.dart';
import '../../domain/models/playlist.dart';
import '../../platform/device_fs.dart';
import 'transfer_path_resolver.dart';

String buildPlaylistPath(Playlist playlist, DeviceSettings settings) {
  final name = playlist.name.toSafeFilename();
  final dir = p.join(settings.devicePath, settings.playlistFolder);
  return p.join(dir, '$name.m3u');
}

Future<void> writePlaylistM3u(
  Playlist playlist,
  DeviceSettings settings,
  DeviceFs fs,
) async {
  final playlistPath = buildPlaylistPath(playlist, settings);
  final playlistDir = p.dirname(playlistPath);

  // Only include songs that are actually present on device.
  final buf = StringBuffer('#EXTM3U\n');
  var count = 0;
  for (final song in playlist.songs) {
    final songPath = buildSongPath(song, settings);
    if (!await fs.exists(songPath)) continue;
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

  await fs.mkdirp(playlistDir);
  final handle = await fs.openWrite(playlistPath);
  try {
    await handle.write(utf8.encode(buf.toString()));
    await handle.close();
  } catch (e) {
    await handle.abort();
    rethrow;
  }
  await fs.removeSidecar(playlistPath);
}

/// Sync filesystem-only existence check.
///
/// Called from widget build methods that can't await — keeping it sync via
/// `dart:io` matches the existing sync hot-path pattern (`songFileExistsOnDevice`
/// etc.). MTP-aware existence will route through a cache facade in a later
/// pass; until then, MTP devices simply report "absent" here.
bool playlistExistsOnDevice(Playlist playlist, DeviceSettings settings) =>
    File(buildPlaylistPath(playlist, settings)).existsSync();
