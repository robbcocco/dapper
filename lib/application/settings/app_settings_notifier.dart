import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../domain/models/app_settings.dart';
import '../providers/providers.dart';

const _kSettingsFile = 'app_settings.json';

class AppSettingsNotifier extends Notifier<AppSettings> {
  @override
  AppSettings build() {
    final dir = ref.watch(appSupportDirProvider);
    return _load(dir);
  }

  void setTransferConcurrency(int value) {
    state = state.copyWith(transferConcurrency: value.clamp(1, 4));
    _save();
  }

  void _save() {
    final dir = ref.read(appSupportDirProvider);
    File(p.join(dir, _kSettingsFile))
        .writeAsString(jsonEncode(state.toJson()))
        .ignore();
  }

  static AppSettings _load(String dir) {
    final file = File(p.join(dir, _kSettingsFile));
    if (!file.existsSync()) return const AppSettings();
    try {
      return AppSettings.fromJson(
          jsonDecode(file.readAsStringSync()) as Map<String, dynamic>);
    } catch (_) {
      return const AppSettings();
    }
  }
}
