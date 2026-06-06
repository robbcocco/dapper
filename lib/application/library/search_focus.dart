import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Shared focus node for the sidebar search field. Lives in a provider so
/// the global `⌘F` keyboard shortcut can call `.requestFocus()` without
/// reaching into the search-bar's widget state.
final searchFocusProvider = Provider<FocusNode>((ref) {
  final node = FocusNode(debugLabel: 'sidebar-search');
  ref.onDispose(node.dispose);
  return node;
});
