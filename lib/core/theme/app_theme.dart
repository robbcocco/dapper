import 'package:flutter/material.dart';
import 'color_tokens.dart';

class AppTheme {
  static ThemeData get dark => ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: ColorTokens.background,
        colorScheme: const ColorScheme.dark(
          primary: ColorTokens.accent,
          surface: ColorTokens.surface,
          onSurface: ColorTokens.textPrimary,
        ),
        dividerColor: ColorTokens.divider,
        listTileTheme: const ListTileThemeData(
          selectedColor: ColorTokens.accent,
          selectedTileColor: ColorTokens.selectionBackground,
        ),
        scrollbarTheme: ScrollbarThemeData(
          thumbColor: WidgetStateProperty.all(ColorTokens.divider),
        ),
        useMaterial3: true,
      );
}
