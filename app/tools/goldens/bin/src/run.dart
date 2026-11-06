// Generator body. Started by ../generate.dart with a package config that
// gives the repo's lib/ its own language version; do not run directly.
import 'dart:io';

import 'common.dart';
import 'fx_device.dart';
import 'fx_flac.dart';
import 'fx_matcher.dart';
import 'fx_paths.dart';

Future<void> main() async {
  final tmp = Directory.systemTemp.createTempSync('dapper_goldens_');
  try {
    safeFilename();
    songPath();
    filenameTemplate();
    albumFolder();
    matchZipEntry();
    await manifest(tmp);
    await scrobblerLog(tmp);
    scrobbleRule();
    await songMatcher();
    await misc(tmp);
    await flacSanitize(tmp);
    await flacShrink(tmp);
    stdout.writeln('total              $caseTotal cases → ${fixturesDir.path}');
  } finally {
    tmp.deleteSync(recursive: true);
  }
}
