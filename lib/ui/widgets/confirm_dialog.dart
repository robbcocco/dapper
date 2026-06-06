import 'package:flutter/material.dart';

import '../../core/theme/color_tokens.dart';

/// Tiny confirm dialog used for destructive bulk actions. Returns true when
/// the user clicks the confirm button, false (or null) when they cancel or
/// dismiss. Centralised so every "are you sure?" prompt in the app gets the
/// same styling without copy-paste.
Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Confirm',
  String cancelLabel = 'Cancel',
  bool destructive = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      backgroundColor: ColorTokens.surface,
      title: Text(title,
          style: const TextStyle(color: ColorTokens.textPrimary, fontSize: 15)),
      content: Text(message,
          style: const TextStyle(color: ColorTokens.textSecondary, fontSize: 13)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(cancelLabel,
              style: const TextStyle(color: ColorTokens.textSecondary)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(
            confirmLabel,
            style: TextStyle(
                color: destructive ? Colors.redAccent : ColorTokens.accent),
          ),
        ),
      ],
    ),
  );
  return result ?? false;
}
