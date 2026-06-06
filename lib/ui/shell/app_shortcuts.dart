import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/library/search_focus.dart';
import '../../application/library/sidebar_state.dart';
import '../../application/playback/playback_notifier.dart';

/// Intent classes — needed by Flutter's Actions API to dispatch typed events.
class _PlayPauseIntent extends Intent {
  const _PlayPauseIntent();
}

class _NextTrackIntent extends Intent {
  const _NextTrackIntent();
}

class _PreviousTrackIntent extends Intent {
  const _PreviousTrackIntent();
}

class _FocusSearchIntent extends Intent {
  const _FocusSearchIntent();
}

class _ClearSearchIntent extends Intent {
  const _ClearSearchIntent();
}

/// Wraps [child] with global keyboard shortcuts. Bindings:
///   - Space          → play / pause
///   - ←  / →         → previous / next track
///   - ⌘F  (Ctrl+F)   → focus the sidebar search box
///   - Esc            → clear the search query (only when one is active)
///
/// Shortcuts are dispatched by Flutter's focus system; an active TextField
/// swallows letter keys before they reach us, so typing into the search box
/// stays unaffected. Space/arrow handlers explicitly bail when a text field
/// has focus to avoid hijacking caret motion / typed spaces.
class AppShortcuts extends ConsumerWidget {
  const AppShortcuts({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accel =
        Platform.isMacOS ? const _MetaF() : const _CtrlF();

    return Shortcuts(
      shortcuts: <ShortcutActivator, Intent>{
        const SingleActivator(LogicalKeyboardKey.space): const _PlayPauseIntent(),
        const SingleActivator(LogicalKeyboardKey.arrowRight):
            const _NextTrackIntent(),
        const SingleActivator(LogicalKeyboardKey.arrowLeft):
            const _PreviousTrackIntent(),
        accel: const _FocusSearchIntent(),
        const SingleActivator(LogicalKeyboardKey.escape):
            const _ClearSearchIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          _PlayPauseIntent: CallbackAction<_PlayPauseIntent>(onInvoke: (_) {
            if (_textFieldHasFocus(context)) return null;
            ref.read(playbackProvider.notifier).togglePlayPause();
            return null;
          }),
          _NextTrackIntent: CallbackAction<_NextTrackIntent>(onInvoke: (_) {
            if (_textFieldHasFocus(context)) return null;
            ref.read(playbackProvider.notifier).next();
            return null;
          }),
          _PreviousTrackIntent:
              CallbackAction<_PreviousTrackIntent>(onInvoke: (_) {
            if (_textFieldHasFocus(context)) return null;
            ref.read(playbackProvider.notifier).previous();
            return null;
          }),
          _FocusSearchIntent: CallbackAction<_FocusSearchIntent>(onInvoke: (_) {
            ref.read(searchFocusProvider).requestFocus();
            return null;
          }),
          _ClearSearchIntent: CallbackAction<_ClearSearchIntent>(onInvoke: (_) {
            // Only intercept Escape when there's actually a query to clear,
            // so Escape inside dialogs / modals keeps its dismiss behaviour.
            final query = ref.read(searchQueryProvider);
            if (query.isEmpty) return null;
            ref.read(searchQueryProvider.notifier).state = '';
            ref.read(searchFocusProvider).unfocus();
            return null;
          }),
        },
        // A focused area is required for the Shortcuts to receive key events.
        // autofocus: true so the app starts with our shortcut scope active.
        child: Focus(
          autofocus: true,
          skipTraversal: true,
          child: child,
        ),
      ),
    );
  }

  /// Returns true when the user is typing in a text field. We use this to
  /// keep Space / arrows from hijacking caret motion.
  static bool _textFieldHasFocus(BuildContext context) {
    final focused = FocusManager.instance.primaryFocus;
    final ctx = focused?.context;
    if (ctx == null) return false;
    // Heuristic: any EditableText ancestor (TextField, TextFormField,
    // CupertinoTextField, custom forms) marks this as "typing context".
    return ctx.findAncestorWidgetOfExactType<EditableText>() != null ||
        focused!.debugLabel?.contains('TextField') == true ||
        focused.debugLabel?.contains('EditableText') == true;
  }
}

class _MetaF extends SingleActivator {
  const _MetaF() : super(LogicalKeyboardKey.keyF, meta: true);
}

class _CtrlF extends SingleActivator {
  const _CtrlF() : super(LogicalKeyboardKey.keyF, control: true);
}
