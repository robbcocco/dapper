import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/services.dart';
import 'package:win32/win32.dart';

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
  static const _pollInterval = Duration(seconds: 2);

  @override
  Stream<List<ConnectedDevice>> watchDrives() async* {
    List<ConnectedDevice>? last;
    while (true) {
      final current = _scan();
      if (last == null || !_sameList(last, current)) {
        last = current;
        yield current;
      }
      await Future.delayed(_pollInterval);
    }
  }

  @override
  Future<List<ConnectedDevice>> listDrives() async => _scan();

  static List<ConnectedDevice> _scan() {
    final result = <ConnectedDevice>[];
    final bitmask = GetLogicalDrives();
    for (var bit = 0; bit < 26; bit++) {
      if (bitmask & (1 << bit) == 0) continue;
      final letter = String.fromCharCode('A'.codeUnitAt(0) + bit);
      final root = '$letter:\\';
      final rootPtr = root.toNativeUtf16();
      try {
        if (GetDriveType(rootPtr) != DRIVE_REMOVABLE) continue;
        final device = _queryVolume(root, rootPtr, letter);
        if (device != null) result.add(device);
      } finally {
        free(rootPtr);
      }
    }
    return result;
  }

  static ConnectedDevice? _queryVolume(
    String root,
    Pointer<Utf16> rootPtr,
    String letter,
  ) {
    final labelBuf = calloc<Uint16>(MAX_PATH + 1);
    final totalBytes = calloc<Uint64>();
    final freeBytes = calloc<Uint64>();
    try {
      GetVolumeInformation(
        rootPtr,
        labelBuf.cast(),
        MAX_PATH + 1,
        nullptr,
        nullptr,
        nullptr,
        nullptr,
        0,
      );
      GetDiskFreeSpaceEx(rootPtr, nullptr, totalBytes, freeBytes);
      final label = labelBuf.cast<Utf16>().toDartString();
      return ConnectedDevice(
        path: root,
        label: label.isEmpty ? '$letter:' : label,
        totalBytes: totalBytes.value,
        availableBytes: freeBytes.value,
      );
    } catch (_) {
      return null;
    } finally {
      free(labelBuf);
      free(totalBytes);
      free(freeBytes);
    }
  }

  static bool _sameList(List<ConnectedDevice> a, List<ConnectedDevice> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].path != b[i].path ||
          a[i].availableBytes != b[i].availableBytes) {
        return false;
      }
    }
    return true;
  }
}
