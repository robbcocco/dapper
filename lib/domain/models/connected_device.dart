import 'package:freezed_annotation/freezed_annotation.dart';

import '../../platform/device_fs.dart';

part 'connected_device.freezed.dart';

@freezed
class ConnectedDevice with _$ConnectedDevice {
  const factory ConnectedDevice({
    required String path,
    required String label,
    required int totalBytes,
    required int availableBytes,
    @Default(DeviceProtocol.filesystem) DeviceProtocol protocol,
  }) = _ConnectedDevice;

  const ConnectedDevice._();

  double get usedFraction =>
      totalBytes > 0 ? (totalBytes - availableBytes) / totalBytes : 0;

  String get availableFormatted => _formatBytes(availableBytes);
  String get totalFormatted => _formatBytes(totalBytes);

  static String _formatBytes(int bytes) {
    if (bytes >= 1e9) return '${(bytes / 1e9).toStringAsFixed(1)} GB';
    if (bytes >= 1e6) return '${(bytes / 1e6).toStringAsFixed(0)} MB';
    return '${(bytes / 1e3).toStringAsFixed(0)} KB';
  }
}
