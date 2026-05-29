import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/services.dart';
import 'package:win32/win32.dart';

import '../domain/models/connected_device.dart';

abstract class DriveDetector {
  Stream<List<ConnectedDevice>> watchDrives();
  Future<List<ConnectedDevice>> listDrives();
  /// Releases any background resources (timers, broadcast controllers). Safe
  /// to call multiple times.
  Future<void> dispose();
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

  // The underlying EventChannel stream lives for the app's lifetime and has
  // no owner-side close, so dispose is a no-op.
  @override
  Future<void> dispose() async {}

  static List<ConnectedDevice> _parseEvent(dynamic event) {
    if (event is! List) return [];
    final result = <ConnectedDevice>[];
    for (final entry in event.whereType<Map>()) {
      final path = entry['path'];
      if (path is! String || path.isEmpty) continue;
      result.add(ConnectedDevice(
        path: path,
        label: entry['label'] as String? ?? 'USB Device',
        totalBytes: (entry['totalBytes'] as int?) ?? 0,
        availableBytes: (entry['availableBytes'] as int?) ?? 0,
      ));
    }
    return result;
  }
}

class WindowsDriveDetector implements DriveDetector {
  static const _pollInterval = Duration(seconds: 2);

  // Single shared broadcast stream so multiple listeners coalesce onto one
  // polling timer; the timer stops as soon as the last subscriber leaves.
  StreamController<List<ConnectedDevice>>? _controller;
  Timer? _timer;
  List<ConnectedDevice>? _last;

  @override
  Stream<List<ConnectedDevice>> watchDrives() {
    // The controller's lifetime spans the detector's; close happens in dispose.
    // ignore: close_sinks
    final controller = _controller ??= StreamController.broadcast(
      onListen: _startPolling,
      onCancel: _stopPolling,
    );
    return controller.stream;
  }

  void _startPolling() {
    if (_timer != null) return;
    _last = null;
    _emit(); // immediate first scan so listeners don't wait 2s
    _timer = Timer.periodic(_pollInterval, (_) => _emit());
  }

  void _stopPolling() {
    _timer?.cancel();
    _timer = null;
  }

  void _emit() {
    final current = _scan();
    if (_last == null || !_sameList(_last!, current)) {
      _last = current;
      _controller?.add(current);
    }
  }

  @override
  Future<void> dispose() async {
    _stopPolling();
    await _controller?.close();
    _controller = null;
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
