import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/library/song_selection_notifier.dart';
import '../../domain/models/song.dart';

/// Adds a Cmd+A / Ctrl+A binding that selects every song in [allSongs] under
/// [scopeKey]. Routes through [HardwareKeyboard.addHandler] rather than a
/// focused [Shortcuts] widget so the binding still fires after the user
/// dismisses a dialog (Flutter's autofocus only fires once on mount — once
/// focus moves to a dialog's text field and the dialog closes, a plain
/// `Focus(autofocus: true)` won't reclaim).
///
/// Skips the binding when an editable text field currently holds focus so
/// pressing Cmd+A inside a search box still selects the text inside the box.
class SelectAllShortcut extends ConsumerStatefulWidget {
  const SelectAllShortcut({
    super.key,
    required this.scopeKey,
    required this.allSongs,
    required this.child,
  });

  final String scopeKey;
  final List<Song> allSongs;
  final Widget child;

  @override
  ConsumerState<SelectAllShortcut> createState() =>
      _SelectAllShortcutState();
}

class _SelectAllShortcutState extends ConsumerState<SelectAllShortcut> {
  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  bool _onKey(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    if (event.logicalKey != LogicalKeyboardKey.keyA) return false;
    final kbd = HardwareKeyboard.instance;
    if (!kbd.isMetaPressed && !kbd.isControlPressed) return false;
    if (_isTextInputFocused()) return false;
    ref
        .read(songSelectionProvider.notifier)
        .selectAll(widget.scopeKey, widget.allSongs);
    return true; // consume so the OS doesn't beep / re-route the keystroke
  }

  bool _isTextInputFocused() {
    final focus = FocusManager.instance.primaryFocus;
    final ctx = focus?.context;
    if (ctx == null) return false;
    if (ctx.widget is EditableText) return true;
    var found = false;
    ctx.visitAncestorElements((e) {
      if (e.widget is EditableText) {
        found = true;
        return false;
      }
      return true;
    });
    return found;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
