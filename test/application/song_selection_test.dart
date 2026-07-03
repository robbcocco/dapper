import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:dapper/application/library/song_selection_notifier.dart';
import 'package:dapper/application/providers/providers.dart';
import 'package:dapper/domain/models/song.dart';

List<Song> _songs(int n) =>
    [for (var i = 0; i < n; i++) Song(id: '$i', title: 't$i')];

void main() {
  // songSelectionProvider.build() wires a listener onto the server-selection
  // chain, which walks down to the credential store (keychain → file). Give it
  // a real temp support dir so the container can build.
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  late ProviderContainer container;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('sel_test_');
    container = ProviderContainer(overrides: [
      appSupportDirProvider.overrideWithValue(tmp.path),
    ]);
  });

  tearDown(() {
    container.dispose();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  group('SongSelectionNotifier.selectRange', () {
    test('selects the inclusive range from anchor to target', () {
      final n = container.read(songSelectionProvider.notifier);
      final list = _songs(10);
      n.selectOnly('s', '2', 2); // anchor = 2
      n.selectRange('s', list, 5);
      final sel = container.read(songSelectionProvider).selectedIds;
      expect(sel, containsAll(['2', '3', '4', '5']));
      expect(sel, isNot(contains('6')));
    });

    test('does not throw when the anchor is now past the end of a shrunk list',
        () {
      final n = container.read(songSelectionProvider.notifier);
      // Anchor set against a 10-item list…
      n.toggle('s', '9', 9);
      // …then the list shrinks to 3 and the user shift-clicks row 0.
      final shrunk = _songs(3);
      expect(() => n.selectRange('s', shrunk, 0), returnsNormally);
      // Anchor clamps to the last valid index (2) → range [0..2].
      final sel = container.read(songSelectionProvider).selectedIds;
      expect(sel, containsAll(['0', '1', '2']));
    });
  });
}
