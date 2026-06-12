import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:dapper/domain/models/connected_device.dart';
import 'package:dapper/platform/composite_drive_detector.dart';
import 'package:dapper/platform/device_fs.dart';
import 'package:dapper/platform/drive_detector.dart';

/// Minimal DriveDetector for tests. Emits whatever the test pushes into
/// [controller]; eject records the request.
class _FakeDetector implements DriveDetector {
  _FakeDetector({required this.label});

  final String label;
  final StreamController<List<ConnectedDevice>> controller =
      StreamController<List<ConnectedDevice>>.broadcast();
  final List<String> ejectedPaths = [];
  EjectResult ejectResult = const EjectResult(success: true);
  bool disposed = false;

  @override
  Stream<List<ConnectedDevice>> watchDrives() => controller.stream;

  @override
  Future<List<ConnectedDevice>> listDrives() async => const [];

  @override
  Future<EjectResult> eject(String devicePath) async {
    ejectedPaths.add(devicePath);
    return ejectResult;
  }

  @override
  Future<void> dispose() async {
    disposed = true;
    await controller.close();
  }
}

/// "MTP detector" tagged by class name. CompositeDriveDetector uses runtime
/// type name to dispatch eject — anything with "Mtp" in the runtimeType
/// gets MTP paths. This shim ensures the dispatch branches correctly.
class _FakeMtpDetector extends _FakeDetector {
  _FakeMtpDetector() : super(label: 'mtp');
}

void main() {
  late _FakeDetector fs;
  late _FakeMtpDetector mtp;
  late CompositeDriveDetector composite;

  setUp(() {
    fs = _FakeDetector(label: 'fs');
    mtp = _FakeMtpDetector();
    composite = CompositeDriveDetector([fs, mtp]);
  });

  tearDown(() async {
    await composite.dispose();
  });

  group('watchDrives', () {
    test('union: emits both children appended', () async {
      final received = <List<ConnectedDevice>>[];
      final sub = composite.watchDrives().listen(received.add);

      fs.controller.add(const [
        ConnectedDevice(
          path: '/Volumes/A',
          label: 'A',
          totalBytes: 100,
          availableBytes: 50,
        ),
      ]);
      await Future<void>.delayed(Duration.zero);
      mtp.controller.add(const [
        ConnectedDevice(
          path: 'mtp://x',
          label: 'X',
          totalBytes: 200,
          availableBytes: 80,
          protocol: DeviceProtocol.mtp,
        ),
      ]);
      await Future<void>.delayed(Duration.zero);

      // Two emissions: after FS adds, after MTP adds.
      expect(received, hasLength(2));
      expect(received.last.map((d) => d.path), ['/Volumes/A', 'mtp://x']);

      await sub.cancel();
    });

    test('FS detector emits replacement preserves last MTP list', () async {
      final received = <List<ConnectedDevice>>[];
      final sub = composite.watchDrives().listen(received.add);

      mtp.controller.add(const [
        ConnectedDevice(
          path: 'mtp://x',
          label: 'X',
          totalBytes: 200,
          availableBytes: 80,
          protocol: DeviceProtocol.mtp,
        ),
      ]);
      await Future<void>.delayed(Duration.zero);

      fs.controller.add(const [
        ConnectedDevice(
          path: '/Volumes/A',
          label: 'A',
          totalBytes: 100,
          availableBytes: 50,
        ),
      ]);
      await Future<void>.delayed(Duration.zero);

      expect(received.last.map((d) => d.path), ['/Volumes/A', 'mtp://x']);
      await sub.cancel();
    });
  });

  group('eject dispatch', () {
    test('mtp:// path goes to the MTP detector', () async {
      await composite.eject('mtp://x');
      expect(mtp.ejectedPaths, ['mtp://x']);
      expect(fs.ejectedPaths, isEmpty);
    });

    test('non-mtp path goes to the filesystem detector', () async {
      await composite.eject('/Volumes/A');
      expect(fs.ejectedPaths, ['/Volumes/A']);
      expect(mtp.ejectedPaths, isEmpty);
    });
  });

  group('dispose', () {
    test('closes every child', () async {
      await composite.dispose();
      expect(fs.disposed, isTrue);
      expect(mtp.disposed, isTrue);
    });
  });
}
