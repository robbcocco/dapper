import 'dart:async';

import '../domain/models/connected_device.dart';
import 'device_fs.dart';
import 'drive_detector.dart';
import 'mtp_client.dart';

/// MTP equivalent of [MacosDriveDetector] / [WindowsDriveDetector].
///
/// Subscribes to [MtpClient.events] for hotplug + does an initial
/// [MtpClient.enumerate] so listeners see currently-connected devices on
/// subscription without waiting for the next plug/unplug.
///
/// Emits [ConnectedDevice] with `protocol: DeviceProtocol.mtp` and
/// `path: "mtp://<deviceId>"` so downstream code can disambiguate via the
/// scheme.
///
/// When the native plugin isn't registered (current state until the Swift /
/// C++ plugins land), [MtpClient.events] is silent and [MtpClient.enumerate]
/// returns `[]` — this detector then emits a single empty list and the
/// stream stays open waiting for the plugin to come online. Net result:
/// users on builds without the native plugin see no MTP devices but
/// everything else works.
class MtpDriveDetector implements DriveDetector {
  MtpDriveDetector({MtpClient? client})
      : _client = client ?? MtpClient.instance;

  final MtpClient _client;
  StreamController<List<ConnectedDevice>>? _controller;
  StreamSubscription<MtpEvent>? _eventsSub;
  List<ConnectedDevice> _last = const [];
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
    final devices = await _client.enumerate();
    return devices.map(_toConnected).toList();
  }

  @override
  Future<EjectResult> eject(String devicePath) async {
    const scheme = 'mtp://';
    if (!devicePath.startsWith(scheme)) {
      return EjectResult(
        success: false,
        error: 'MtpDriveDetector cannot eject non-MTP path: $devicePath',
      );
    }
    final deviceId = devicePath.substring(scheme.length);
    try {
      await _client.closeSession(deviceId);
      return const EjectResult(success: true);
    } catch (e) {
      return EjectResult(success: false, error: e.toString());
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _eventsSub?.cancel();
    _eventsSub = null;
    await _controller?.close();
    _controller = null;
  }

  void _start() {
    if (_disposed) return;
    _eventsSub = _client.events().listen(
      _onEvent,
      onError: (Object _, StackTrace __) {/* silent */},
    );
    // Best-effort initial snapshot so the listener doesn't sit at "no MTP
    // devices" until the first plug event.
    _client.enumerate().then((devices) {
      if (_disposed) return;
      _emit(devices.map(_toConnected).toList());
    }, onError: (Object _) {/* missing plugin → empty list */}).whenComplete(() {
      if (_last.isEmpty) _emit(const []);
    });
  }

  void _stopIfIdle() {
    if (_controller?.hasListener ?? false) return;
    _eventsSub?.cancel();
    _eventsSub = null;
  }

  void _onEvent(MtpEvent event) {
    if (event is! MtpDeviceListEvent) return;
    _emit(event.devices.map(_toConnected).toList());
  }

  void _emit(List<ConnectedDevice> devices) {
    if (_disposed) return;
    if (_sameList(_last, devices)) return;
    _last = devices;
    _controller?.add(devices);
  }

  static ConnectedDevice _toConnected(MtpDevice d) => ConnectedDevice(
        path: 'mtp://${d.deviceId}',
        label: d.label,
        totalBytes: d.totalBytes,
        availableBytes: d.availableBytes,
        protocol: DeviceProtocol.mtp,
      );

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
