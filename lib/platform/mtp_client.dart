import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Dart-side bridge to the native MTP plugin.
///
/// Two channels:
///   - `com.dapper/mtp` (MethodChannel) — request/response RPCs (list,
///     mkdir, putBegin, etc.).
///   - `com.dapper/mtp_events` (EventChannel) — device hotplug events
///     (`{kind: "deviceList", devices: [...]}`) and per-stream progress
///     (`{kind: "progress", streamId: ..., sent: N, total: M}`).
///
/// MTP modelling notes that shape this API:
///   - Objects are identified by 32-bit ints, not paths. The Dart caller
///     keeps a path↔objectId cache (see [MtpDeviceFs]) and looks ids up via
///     [list]; native side returns ids on every enumeration.
///   - Writes go through `putBegin` → many `putChunk` → `putCommit`. The
///     server-side commit is the atomic-from-MTP's-view step; there's no
///     append/seek.
///   - Sessions are single-threaded per device. The Dart layer serialises
///     in-flight transfers per device (`MtpDeviceFs` uses a mutex).
///
/// **Today this class is a stub.** Every method completes with a sensible
/// "no MTP support" result (empty list, throw UnsupportedError on write).
/// When the native plugin lands the MethodChannel calls activate and the
/// rest of the app picks up MTP transparently via [deviceFsProvider].
class MtpClient {
  MtpClient._({
    MethodChannel? methodChannel,
    EventChannel? eventChannel,
  })  : _method = methodChannel ?? const MethodChannel(_kMethodChannel),
        _events = eventChannel ?? const EventChannel(_kEventChannel);

  /// Default singleton wired to the production channel names.
  static final MtpClient instance = MtpClient._();

  /// Test-only constructor that accepts custom channels.
  factory MtpClient.withChannels({
    required MethodChannel methodChannel,
    required EventChannel eventChannel,
  }) =>
      MtpClient._(methodChannel: methodChannel, eventChannel: eventChannel);

  /// Test-only seam: allows a subclass to bypass channel construction so
  /// every method can be overridden with a fake implementation. The real
  /// channels are never invoked when every public method is overridden.
  @visibleForTesting
  MtpClient.forTesting()
      : _method = const MethodChannel('__mtp_test__'),
        _events = const EventChannel('__mtp_test__');

  static const String _kMethodChannel = 'com.dapper/mtp';
  static const String _kEventChannel = 'com.dapper/mtp_events';

  final MethodChannel _method;
  final EventChannel _events;

  Stream<MtpEvent>? _eventStream;

  /// Returns true when the native MTP plugin is registered on this build.
  /// Probes by calling `ping` and catching `MissingPluginException`.
  ///
  /// Cached after the first call so repeated lookups (e.g. from
  /// [MtpDriveDetector.watchDrives]) don't pay the round-trip cost.
  Future<bool> isSupported() async {
    final cached = _supported;
    if (cached != null) return cached;
    try {
      await _method.invokeMethod<void>('ping');
      _supported = true;
    } on MissingPluginException {
      _supported = false;
    } catch (_) {
      _supported = false;
    }
    return _supported!;
  }

  bool? _supported;

  // ── Device hotplug ──────────────────────────────────────────────────────

  /// Stream of MTP hotplug + per-stream progress events.
  ///
  /// Currently emits nothing when the plugin is missing. The
  /// [MissingPluginException] from the EventChannel is swallowed so callers
  /// don't have to special-case the no-plugin build.
  Stream<MtpEvent> events() {
    return _eventStream ??= _events
        .receiveBroadcastStream()
        .map(_parseEvent)
        .where((e) => e != null)
        .cast<MtpEvent>()
        .handleError((Object _) {/* MissingPlugin or transport — silent */});
  }

  /// Returns the current list of MTP-connected devices.
  Future<List<MtpDevice>> enumerate() async {
    if (!await isSupported()) return const [];
    final raw = await _method.invokeListMethod<dynamic>('enumerate') ?? const [];
    return raw
        .whereType<Map>()
        .map(_parseDevice)
        .whereType<MtpDevice>()
        .toList();
  }

  // ── Session lifecycle ──────────────────────────────────────────────────

  Future<void> openSession(String deviceId) async {
    if (!await isSupported()) return;
    await _method.invokeMethod<void>('openSession', {'deviceId': deviceId});
  }

  Future<void> closeSession(String deviceId) async {
    if (!await isSupported()) return;
    await _method.invokeMethod<void>('closeSession', {'deviceId': deviceId});
  }

  // ── Object operations ──────────────────────────────────────────────────

  /// Lists immediate children of [parentObjectId] (use `0` for root).
  Future<List<MtpObject>> list(String deviceId, int parentObjectId) async {
    if (!await isSupported()) return const [];
    final raw = await _method.invokeListMethod<dynamic>('list', {
      'deviceId': deviceId,
      'parentObjectId': parentObjectId,
    });
    if (raw == null) return const [];
    return raw
        .whereType<Map>()
        .map(_parseObject)
        .whereType<MtpObject>()
        .toList();
  }

  /// Creates a folder under [parentObjectId] and returns the new object id.
  Future<int> mkdir(String deviceId, int parentObjectId, String name) async {
    if (!await isSupported()) {
      throw const MtpUnsupportedException('mkdir');
    }
    final id = await _method.invokeMethod<int>('mkdir', {
      'deviceId': deviceId,
      'parentObjectId': parentObjectId,
      'name': name,
    });
    if (id == null) throw const MtpProtocolException('mkdir returned null');
    return id;
  }

  Future<void> delete(String deviceId, int objectId) async {
    if (!await isSupported()) return;
    await _method.invokeMethod<void>('delete', {
      'deviceId': deviceId,
      'objectId': objectId,
    });
  }

  Future<int?> freeSpace(String deviceId) async {
    if (!await isSupported()) return null;
    final v = await _method.invokeMethod<int>('freeSpace', {
      'deviceId': deviceId,
    });
    return v;
  }

  // ── Write (Put) ─────────────────────────────────────────────────────────

  /// Begins a write session, returns an opaque streamId used by
  /// [putChunk]/[putCommit]/[putAbort].
  Future<String> putBegin({
    required String deviceId,
    required int parentObjectId,
    required String name,
    required int totalBytes,
  }) async {
    if (!await isSupported()) {
      throw const MtpUnsupportedException('putBegin');
    }
    final streamId = await _method.invokeMethod<String>('putBegin', {
      'deviceId': deviceId,
      'parentObjectId': parentObjectId,
      'name': name,
      'totalBytes': totalBytes,
    });
    if (streamId == null) {
      throw const MtpProtocolException('putBegin returned null streamId');
    }
    return streamId;
  }

  Future<void> putChunk(String streamId, Uint8List bytes) async {
    if (!await isSupported()) {
      throw const MtpUnsupportedException('putChunk');
    }
    await _method.invokeMethod<void>('putChunk', {
      'streamId': streamId,
      'bytes': bytes,
    });
  }

  /// Commits the in-flight write and returns the new object id.
  Future<int> putCommit(String streamId) async {
    if (!await isSupported()) {
      throw const MtpUnsupportedException('putCommit');
    }
    final id = await _method.invokeMethod<int>('putCommit', {
      'streamId': streamId,
    });
    if (id == null) {
      throw const MtpProtocolException('putCommit returned null');
    }
    return id;
  }

  Future<void> putAbort(String streamId) async {
    if (!await isSupported()) return;
    await _method.invokeMethod<void>('putAbort', {'streamId': streamId});
  }

  // ── Read (Get) ──────────────────────────────────────────────────────────

  /// Begins a read of [objectId], returns an opaque streamId. Chunks are
  /// pulled with [getChunk] until it returns an empty Uint8List, then
  /// [getEnd] releases native resources.
  Future<String> getBegin(String deviceId, int objectId) async {
    if (!await isSupported()) {
      throw const MtpUnsupportedException('getBegin');
    }
    final streamId = await _method.invokeMethod<String>('getBegin', {
      'deviceId': deviceId,
      'objectId': objectId,
    });
    if (streamId == null) {
      throw const MtpProtocolException('getBegin returned null streamId');
    }
    return streamId;
  }

  Future<Uint8List> getChunk(String streamId, int maxBytes) async {
    if (!await isSupported()) {
      throw const MtpUnsupportedException('getChunk');
    }
    final v = await _method.invokeMethod<Uint8List>('getChunk', {
      'streamId': streamId,
      'maxBytes': maxBytes,
    });
    return v ?? Uint8List(0);
  }

  Future<void> getEnd(String streamId) async {
    if (!await isSupported()) return;
    await _method.invokeMethod<void>('getEnd', {'streamId': streamId});
  }

  // ── Helpers ─────────────────────────────────────────────────────────────

  static MtpDevice? _parseDevice(Map<dynamic, dynamic> raw) {
    final id = raw['deviceId'];
    if (id is! String || id.isEmpty) return null;
    return MtpDevice(
      deviceId: id,
      label: (raw['label'] as String?) ?? 'MTP Device',
      totalBytes: (raw['totalBytes'] as int?) ?? 0,
      availableBytes: (raw['availableBytes'] as int?) ?? 0,
    );
  }

  static MtpObject? _parseObject(Map<dynamic, dynamic> raw) {
    final id = raw['objectId'];
    final name = raw['name'];
    if (id is! int || name is! String) return null;
    return MtpObject(
      objectId: id,
      name: name,
      isDir: (raw['isDir'] as bool?) ?? false,
      size: (raw['size'] as int?) ?? 0,
      modifiedMillis: raw['modifiedMillis'] as int?,
    );
  }

  static MtpEvent? _parseEvent(dynamic raw) {
    if (raw is! Map) return null;
    final kind = raw['kind'];
    if (kind == 'deviceList') {
      final devices = (raw['devices'] as List?)
              ?.whereType<Map>()
              .map(_parseDevice)
              .whereType<MtpDevice>()
              .toList() ??
          const <MtpDevice>[];
      return MtpDeviceListEvent(devices);
    }
    if (kind == 'progress') {
      final streamId = raw['streamId'];
      final sent = raw['sent'];
      final total = raw['total'];
      if (streamId is String && sent is int && total is int) {
        return MtpProgressEvent(streamId: streamId, sent: sent, total: total);
      }
    }
    return null;
  }
}

/// A device the native plugin reported as connected.
class MtpDevice {
  const MtpDevice({
    required this.deviceId,
    required this.label,
    required this.totalBytes,
    required this.availableBytes,
  });
  final String deviceId;
  final String label;
  final int totalBytes;
  final int availableBytes;
}

/// An MTP object (file or folder) returned by [MtpClient.list].
class MtpObject {
  const MtpObject({
    required this.objectId,
    required this.name,
    required this.isDir,
    required this.size,
    this.modifiedMillis,
  });
  final int objectId;
  final String name;
  final bool isDir;
  final int size;
  final int? modifiedMillis;
}

sealed class MtpEvent {
  const MtpEvent();
}

class MtpDeviceListEvent extends MtpEvent {
  const MtpDeviceListEvent(this.devices);
  final List<MtpDevice> devices;
}

class MtpProgressEvent extends MtpEvent {
  const MtpProgressEvent({
    required this.streamId,
    required this.sent,
    required this.total,
  });
  final String streamId;
  final int sent;
  final int total;
}

/// Thrown when a call requires the native plugin but it's not registered.
class MtpUnsupportedException implements Exception {
  const MtpUnsupportedException(this.operation);
  final String operation;

  @override
  String toString() =>
      'MTP plugin not available — cannot perform $operation';
}

/// Thrown when the native plugin returned an unexpected shape.
class MtpProtocolException implements Exception {
  const MtpProtocolException(this.message);
  final String message;

  @override
  String toString() => 'MTP protocol error: $message';
}
