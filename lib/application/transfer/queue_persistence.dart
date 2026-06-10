import 'dart:convert';
import 'dart:developer' as dev;
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../domain/models/song.dart';
import '../../domain/models/transfer_task.dart';

const _kQueueFile = 'transfer_queue.json';

List<TransferTask> loadQueue(String supportDir) {
  final file = File(p.join(supportDir, _kQueueFile));
  if (!file.existsSync()) return [];
  try {
    final list = jsonDecode(file.readAsStringSync()) as List;
    return list.whereType<Map<String, dynamic>>().map(_taskFromJson).toList();
  } catch (e, st) {
    dev.log('queue_persistence: failed to parse $_kQueueFile — $e',
        stackTrace: st);
    return [];
  }
}

Future<void> saveQueue(String supportDir, List<TransferTask> tasks) async {
  final toSave = tasks
      .where((t) =>
          t.status == TransferStatus.queued ||
          t.status == TransferStatus.inProgress ||
          t.status == TransferStatus.failed)
      .toList();
  final file = File(p.join(supportDir, _kQueueFile));
  try {
    await file.writeAsString(jsonEncode(toSave.map(_taskToJson).toList()));
  } catch (e, st) {
    dev.log('queue_persistence: failed to write $_kQueueFile — $e',
        stackTrace: st);
  }
}

Map<String, dynamic> _taskToJson(TransferTask t) => {
      'id': t.id,
      'song': _songToJson(t.song),
      'devicePath': t.devicePath,
      'status': t.status.name,
      if (t.errorMessage != null) 'errorMessage': t.errorMessage,
      if (t.zipGroupId != null) 'zipGroupId': t.zipGroupId,
      if (t.zipSourceId != null) 'zipSourceId': t.zipSourceId,
    };

TransferTask _taskFromJson(Map<String, dynamic> j) {
  final statusStr = j['status'] as String? ?? 'queued';
  var status = TransferStatus.values.firstWhere(
    (s) => s.name == statusStr,
    orElse: () => TransferStatus.queued,
  );
  // Tasks that were mid-flight when the app closed restart from scratch.
  if (status == TransferStatus.inProgress) status = TransferStatus.queued;
  return TransferTask(
    id: j['id'] as String,
    song: _songFromJson(j['song'] as Map<String, dynamic>),
    devicePath: j['devicePath'] as String,
    status: status,
    errorMessage: j['errorMessage'] as String?,
    zipGroupId: j['zipGroupId'] as String?,
    zipSourceId: j['zipSourceId'] as String?,
  );
}

Map<String, dynamic> _songToJson(Song s) => {
      'id': s.id,
      'title': s.title,
      if (s.albumId != null) 'albumId': s.albumId,
      if (s.artistId != null) 'artistId': s.artistId,
      if (s.album != null) 'album': s.album,
      if (s.artist != null) 'artist': s.artist,
      if (s.duration != null) 'duration': s.duration,
      if (s.bitRate != null) 'bitRate': s.bitRate,
      if (s.contentType != null) 'contentType': s.contentType,
      if (s.suffix != null) 'suffix': s.suffix,
      if (s.size != null) 'size': s.size,
      if (s.coverArtId != null) 'coverArtId': s.coverArtId,
      if (s.track != null) 'track': s.track,
      if (s.discNumber != null) 'discNumber': s.discNumber,
      if (s.year != null) 'year': s.year,
      if (s.genre != null) 'genre': s.genre,
      if (s.albumArtist != null) 'albumArtist': s.albumArtist,
    };

Song _songFromJson(Map<String, dynamic> j) => Song(
      id: j['id'] as String,
      title: j['title'] as String,
      albumId: j['albumId'] as String?,
      artistId: j['artistId'] as String?,
      album: j['album'] as String?,
      artist: j['artist'] as String?,
      duration: j['duration'] as int?,
      bitRate: j['bitRate'] as int?,
      contentType: j['contentType'] as String?,
      suffix: j['suffix'] as String?,
      size: j['size'] as int?,
      coverArtId: j['coverArtId'] as String?,
      track: j['track'] as int?,
      discNumber: j['discNumber'] as int?,
      year: j['year'] as int?,
      genre: j['genre'] as String?,
      albumArtist: j['albumArtist'] as String?,
    );
