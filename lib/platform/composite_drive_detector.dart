import 'dart:async';

import '../domain/models/connected_device.dart';
import 'drive_detector.dart';

/// Merges N [DriveDetector] streams into one.
///
/// Used to combine the filesystem detector ([MacosDriveDetector] /
/// [WindowsDriveDetector]) with [MtpDriveDetector] so consumers see a
/// single unified `Stream<List<ConnectedDevice>>`.
///
/// Emits the union of the most-recent list seen from each child detector.
/// [eject] dispatches to the child detector whose path scheme matches:
///   - `mtp://...` → the MTP detector
///   - anything else → the filesystem detector (first non-MTP child)
class CompositeDriveDetector implements DriveDetector {
  CompositeDriveDetector(this._children) {
    assert(_children.isNotEmpty);
  }

  final List<DriveDetector> _children;
  final List<List<ConnectedDevice>?> _lastPerChild = [];
  StreamController<List<ConnectedDevice>>? _controller;
  List<StreamSubscription<List<ConnectedDevice>>>? _subs;
  bool _disposed = false;

  @override
  Stream<List<ConnectedDevice>> watchDrives() {
    // The controller's lifetime spans the detector's; close happens in dispose.
    // ignore: close_sinks
    final controller = _controller ??= StreamController.broadcast(
      onListen: _start,
      onCancel: _stopIfIdle,
    );
    return controller.stream;
  }

  @override
  Future<List<ConnectedDevice>> listDrives() async {
    final lists = await Future.wait(_children.map((d) => d.listDrives()));
    return [for (final l in lists) ...l];
  }

  @override
  Future<EjectResult> eject(String devicePath) async {
    final isMtp = devicePath.startsWith('mtp://');
    for (final child in _children) {
      if (isMtp && child.runtimeType.toString().contains('Mtp')) {
        return child.eject(devicePath);
      }
      if (!isMtp && !child.runtimeType.toString().contains('Mtp')) {
        return child.eject(devicePath);
      }
    }
    return EjectResult(
        success: false, error: 'No detector for path: $devicePath');
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    for (final s in _subs ?? const []) {
      await s.cancel();
    }
    _subs = null;
    await _controller?.close();
    _controller = null;
    for (final child in _children) {
      await child.dispose();
    }
  }

  void _start() {
    if (_disposed) return;
    _lastPerChild
      ..clear()
      ..addAll(List<List<ConnectedDevice>?>.filled(_children.length, null));
    _subs = [
      for (var i = 0; i < _children.length; i++)
        _children[i].watchDrives().listen(
          (list) {
            _lastPerChild[i] = list;
            _emit();
          },
          onError: (Object _, StackTrace __) {/* silent */},
        ),
    ];
  }

  void _stopIfIdle() {
    if (_controller?.hasListener ?? false) return;
    for (final s in _subs ?? const []) {
      s.cancel();
    }
    _subs = null;
  }

  void _emit() {
    if (_disposed) return;
    final merged = <ConnectedDevice>[];
    for (final l in _lastPerChild) {
      if (l != null) merged.addAll(l);
    }
    _controller?.add(merged);
  }
}
