import 'dart:io';

import 'package:flutter/services.dart';

import '../domain/models/connected_device.dart';

abstract class DriveDetector {
  Stream<List<ConnectedDevice>> watchDrives();
  Future<List<ConnectedDevice>> listDrives();
}

DriveDetector createDriveDetector() {
  if (Platform.isMacOS) return MacosDriveDetector();
  if (Platform.isWindows) return WindowsDriveDetector();
  throw UnsupportedError('Drive detection not supported on this platform');
}

class MacosDriveDetector implements DriveDetector {
  static const _channel = EventChannel('com.dapper/drive_detector');

  late final Stream<List<ConnectedDevice>> _stream = _channel
      .receiveBroadcastStream()
      .map(_parseEvent)
      .asBroadcastStream();

  @override
  Stream<List<ConnectedDevice>> watchDrives() => _stream;

  @override
  Future<List<ConnectedDevice>> listDrives() => watchDrives().first;

  static List<ConnectedDevice> _parseEvent(dynamic event) {
    if (event is! List) return [];
    return event
        .whereType<Map>()
        .map((m) => ConnectedDevice(
              path: m['path'] as String,
              label: m['label'] as String? ?? 'USB Device',
              totalBytes: (m['totalBytes'] as int?) ?? 0,
              availableBytes: (m['availableBytes'] as int?) ?? 0,
            ))
        .toList();
  }
}

class WindowsDriveDetector implements DriveDetector {
  @override
  Stream<List<ConnectedDevice>> watchDrives() => const Stream.empty();

  @override
  Future<List<ConnectedDevice>> listDrives() async => [];
}
