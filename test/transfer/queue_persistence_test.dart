import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:dapper/application/transfer/queue_persistence.dart';
import 'package:dapper/domain/models/song.dart';
import 'package:dapper/domain/models/transfer_task.dart';

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('dapper_queue_test_');
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  TransferTask makeTask({
    String id = 't1',
    TransferStatus status = TransferStatus.queued,
    String? errorMessage,
    Song? song,
  }) =>
      TransferTask(
        id: id,
        song: song ??
            const Song(
              id: 's1',
              title: 'Title',
              album: 'Album',
              artist: 'Artist',
              suffix: 'mp3',
              track: 1,
            ),
        devicePath: '/dev/usb',
        status: status,
        errorMessage: errorMessage,
      );

  test('loadQueue returns [] when the file does not exist', () {
    expect(loadQueue(tmp.path), isEmpty);
  });

  test('saveQueue + loadQueue round-trip queued tasks', () async {
    await saveQueue(tmp.path, [makeTask(id: 'a'), makeTask(id: 'b')]);
    final loaded = loadQueue(tmp.path);
    expect(loaded.map((t) => t.id), ['a', 'b']);
    expect(loaded.first.devicePath, '/dev/usb');
  });

  test('saveQueue skips completed / cancelled tasks (only persists queued / '
      'inProgress / failed)', () async {
    await saveQueue(tmp.path, [
      makeTask(id: 'queued', status: TransferStatus.queued),
      makeTask(id: 'inProgress', status: TransferStatus.inProgress),
      makeTask(id: 'failed', status: TransferStatus.failed),
      makeTask(id: 'completed', status: TransferStatus.completed),
      makeTask(id: 'cancelled', status: TransferStatus.cancelled),
    ]);
    final loaded = loadQueue(tmp.path);
    expect(loaded.map((t) => t.id).toSet(),
        {'queued', 'inProgress', 'failed'});
  });

  test('mid-flight tasks restart as queued after a load', () async {
    // The contract: tasks that were inProgress when the app closed must come
    // back as queued, with bytesReceived/totalBytes reset, so the engine can
    // restart them cleanly instead of resuming from a half-finished download.
    await saveQueue(tmp.path, [
      makeTask(id: 't', status: TransferStatus.inProgress),
    ]);
    final loaded = loadQueue(tmp.path);
    expect(loaded.single.status, TransferStatus.queued);
    expect(loaded.single.bytesReceived, 0);
    expect(loaded.single.totalBytes, 0);
  });

  test('preserves errorMessage on failed tasks', () async {
    await saveQueue(tmp.path, [
      makeTask(id: 't', status: TransferStatus.failed, errorMessage: 'oops'),
    ]);
    final loaded = loadQueue(tmp.path);
    expect(loaded.single.errorMessage, 'oops');
  });

  test('saving an empty list yields an empty list on load', () async {
    await saveQueue(tmp.path, []);
    expect(loadQueue(tmp.path), isEmpty);
  });

  test('loadQueue returns [] on malformed JSON without throwing', () async {
    await File('${tmp.path}/transfer_queue.json')
        .writeAsString('{this is not valid');
    expect(loadQueue(tmp.path), isEmpty);
  });

  test('round-trip preserves all serialised song fields', () async {
    const song = Song(
      id: 's-id',
      title: 'Title',
      albumId: 'alb-1',
      artistId: 'art-1',
      album: 'Album',
      artist: 'Artist',
      duration: 240,
      bitRate: 320,
      contentType: 'audio/mpeg',
      suffix: 'mp3',
      size: 5_000_000,
      coverArtId: 'cov-1',
      track: 7,
      discNumber: 2,
      year: 1999,
      genre: 'Rock',
      albumArtist: 'Album Artist',
    );
    await saveQueue(tmp.path, [makeTask(song: song)]);
    final back = loadQueue(tmp.path).single.song;
    expect(back, song);
  });
}
