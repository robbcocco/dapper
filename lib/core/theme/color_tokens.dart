import 'package:flutter/material.dart';

class ColorTokens {
  // Backgrounds
  static const Color background = Color(0xFF1C1C1E);
  static const Color surface = Color(0xFF2C2C2E);
  static const Color surfaceVariant = Color(0xFF3A3A3C);

  // Glass panels — NSVisualEffectView provides the blur; this overlay adds a
  // subtle dark tint on top so panels read as distinct from the main content.
  static const Color sidebarOverlay = Color(0x28000000);
  static const Color glassBorder = Color(0x18FFFFFF);

  // Interactive
  static const Color accent = Color(0xFF0A84FF);
  static const Color selectionBackground = Color(0x2E0A84FF);

  // Text
  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFF8E8E93);

  // Layout
  static const Color divider = Color(0x20FFFFFF);
}
