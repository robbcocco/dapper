import 'dart:async';
import 'dart:convert';
import 'dart:developer' as dev;
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

  Future<void> setTransferConcurrency(int value) async {
    state = state.copyWith(transferConcurrency: value.clamp(1, 4));
    await _save();
  }

  Future<void> _save() async {
    final dir = ref.read(appSupportDirProvider);
    try {
      await File(p.join(dir, _kSettingsFile))
          .writeAsString(jsonEncode(state.toJson()));
    } catch (e, st) {
      dev.log('AppSettingsNotifier: failed to persist settings — $e',
          stackTrace: st);
    }
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
