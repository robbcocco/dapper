import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/song.dart';
import '../providers/providers.dart';

/// Multi-select state for the currently visible song list.
///
/// [scopeKey] identifies the visible scope (album id, playlist id, etc.) so
/// navigating to a different list clears the selection automatically.
/// [anchorIndex] is the last single-clicked row — used as the fixed end when
/// the user shift-clicks for range selection.
class SongSelectionState {
  const SongSelectionState({
    this.scopeKey,
    this.selectedIds = const {},
    this.anchorIndex,
  });

  final String? scopeKey;
  final Set<String> selectedIds;
  final int? anchorIndex;

  bool get isEmpty => selectedIds.isEmpty;
  int get count => selectedIds.length;
  bool isSelected(String id) => selectedIds.contains(id);
  bool matches(String? key) => key != null && scopeKey == key;

  SongSelectionState copyWith({
    String? scopeKey,
    Set<String>? selectedIds,
    int? anchorIndex,
    bool resetAnchor = false,
  }) =>
      SongSelectionState(
        scopeKey: scopeKey ?? this.scopeKey,
        selectedIds: selectedIds ?? this.selectedIds,
        anchorIndex: resetAnchor ? null : (anchorIndex ?? this.anchorIndex),
      );
}

class SongSelectionNotifier extends Notifier<SongSelectionState> {
  @override
  SongSelectionState build() {
    // Selection ids are server-scoped — switching Navidrome servers would
    // leave stale ids that don't match any song in the new library, making
    // the action bar non-functional. Drop the selection when the active
    // server id changes.
    ref.listen(selectedServerIdProvider, (prev, next) {
      if (prev?.valueOrNull != next.valueOrNull) {
        state = const SongSelectionState();
      }
    });
    return const SongSelectionState();
  }

  /// Resets selection when the visible scope changes.
  void setScope(String scopeKey) {
    if (state.scopeKey == scopeKey) return;
    state = SongSelectionState(scopeKey: scopeKey);
  }

  void clear() {
    state = SongSelectionState(scopeKey: state.scopeKey);
  }

  /// Replaces the selection with a single id and sets the anchor.
  void selectOnly(String scopeKey, String id, int index) {
    state = SongSelectionState(
      scopeKey: scopeKey,
      selectedIds: {id},
      anchorIndex: index,
    );
  }

  /// Toggles a single id. Sets the anchor to [index] regardless of result so
  /// a subsequent shift-click ranges from the most recent toggle.
  void toggle(String scopeKey, String id, int index) {
    final scoped = state.matches(scopeKey)
        ? state
        : SongSelectionState(scopeKey: scopeKey);
    final next = Set<String>.from(scoped.selectedIds);
    if (next.contains(id)) {
      next.remove(id);
    } else {
      next.add(id);
    }
    state = scoped.copyWith(selectedIds: next, anchorIndex: index);
  }

  /// Adds every song in [ordered] to the selection. Anchor is reset to the
  /// last index so a subsequent shift-click ranges from the end of the list.
  void selectAll(String scopeKey, List<Song> ordered) {
    if (ordered.isEmpty) return;
    state = SongSelectionState(
      scopeKey: scopeKey,
      selectedIds: {for (final s in ordered) s.id},
      anchorIndex: ordered.length - 1,
    );
  }

  /// Selects every song from the anchor to [toIndex] inclusive. When no
  /// anchor is set the [toIndex] is treated as a single-select.
  void selectRange(String scopeKey, List<Song> ordered, int toIndex) {
    if (toIndex < 0 || toIndex >= ordered.length) return;
    final scoped = state.matches(scopeKey)
        ? state
        : SongSelectionState(scopeKey: scopeKey);
    final anchor = scoped.anchorIndex ?? toIndex;
    final lo = anchor < toIndex ? anchor : toIndex;
    final hi = anchor < toIndex ? toIndex : anchor;
    final next = Set<String>.from(scoped.selectedIds);
    for (var i = lo; i <= hi; i++) {
      next.add(ordered[i].id);
    }
    state = scoped.copyWith(
      selectedIds: next,
      // Leave anchor at its existing value so subsequent shift-clicks keep
      // ranging from the original point, like Finder.
    );
  }
}

final songSelectionProvider =
    NotifierProvider<SongSelectionNotifier, SongSelectionState>(
  SongSelectionNotifier.new,
);
