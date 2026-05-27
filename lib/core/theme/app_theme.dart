import 'package:flutter/material.dart';
import 'color_tokens.dart';

class AppTheme {
  static ThemeData get dark => ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Colors.transparent,
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
          thumbColor: WidgetStateProperty.all(
              ColorTokens.textSecondary.withValues(alpha: 0.3)),
          radius: const Radius.circular(4),
          thickness: WidgetStateProperty.all(4),
        ),
        popupMenuTheme: const PopupMenuThemeData(
          color: ColorTokens.surface,
          surfaceTintColor: Colors.transparent,
          elevation: 8,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(10)),
            side: BorderSide(color: ColorTokens.glassBorder),
          ),
        ),
        dialogTheme: const DialogThemeData(
          backgroundColor: ColorTokens.surface,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(14)),
            side: BorderSide(color: ColorTokens.glassBorder),
          ),
        ),
        useMaterial3: true,
      );
}
