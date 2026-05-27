import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:macos_window_utils/macos_window_utils.dart';
import 'package:window_manager/window_manager.dart';

import 'core/constants/app_constants.dart';
import 'core/theme/app_theme.dart';
import 'ui/shell/app_shell.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize macos_window_utils — enables NSVisualEffectView and window APIs.
  await WindowManipulator.initialize();
  WindowManipulator.setWindowBackgroundColorToClear();
  WindowManipulator.makeTitlebarTransparent();
  WindowManipulator.enableFullSizeContentView();
  // Window-level vibrancy material — visible behind any transparent Flutter content.
  WindowManipulator.setMaterial(NSVisualEffectViewMaterial.underWindowBackground);

  await windowManager.ensureInitialized();
  await windowManager.setMinimumSize(AppConstants.minWindowSize);
  await windowManager.setTitle('Dapper');

  runApp(const ProviderScope(child: DapperApp()));
}

class DapperApp extends StatelessWidget {
  const DapperApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Dapper',
      theme: AppTheme.dark,
      debugShowCheckedModeBanner: false,
      home: const AppShell(),
    );
  }
}
