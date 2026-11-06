// Executes the original Dart logic from the repo's lib/ over an adversarial
// corpus and writes golden fixtures to app/fixtures/. Deterministic (fixed
// seeds).
//
//   cd app && dart run tools/goldens/bin/generate.dart
//
// Run tools/goldens/sync.sh first whenever the sources it copies change.
//
// The originals are imported by relative file path. Files outside every
// package get the SDK's newest language version, under which the committed
// freezed output no longer compiles, so this launcher writes a package config
// that adds the Flutter app (repo root) as a package with the language
// version from its pubspec, then runs src/run.dart under it.
import 'dart:convert';
import 'dart:io';

Future<void> main() async {
  final goldens = Directory.fromUri(Platform.script.resolve('../'));
  final repo = Directory.fromUri(goldens.uri.resolve('../../../'));
  final pubConfig = File('${goldens.path}.dart_tool/package_config.json');
  if (!pubConfig.existsSync()) {
    final get = await Process.run(Platform.resolvedExecutable, ['pub', 'get'],
        workingDirectory: goldens.path);
    if (get.exitCode != 0) {
      stderr.write(get.stdout);
      stderr.write(get.stderr);
      exit(get.exitCode);
    }
  }

  final sdk = RegExp(r'^\s+sdk:\s*\^?(\d+)\.(\d+)', multiLine: true)
      .firstMatch(File('${repo.path}pubspec.yaml').readAsStringSync());
  if (sdk == null) {
    stderr.writeln('generate: no environment sdk constraint in ${repo.path}pubspec.yaml');
    exit(1);
  }
  final config = jsonDecode(pubConfig.readAsStringSync()) as Map<String, dynamic>;
  (config['packages'] as List).add({
    'name': 'dapper_original',
    'rootUri': repo.uri.toString(),
    'packageUri': 'lib/',
    'languageVersion': '${sdk.group(1)}.${sdk.group(2)}',
  });
  final generated = File('${goldens.path}.dart_tool/goldens_package_config.json')
    ..writeAsStringSync(const JsonEncoder.withIndent('  ').convert(config));

  final proc = await Process.start(
    Platform.resolvedExecutable,
    ['--packages=${generated.path}', '${goldens.path}bin/src/run.dart'],
    mode: ProcessStartMode.inheritStdio,
  );
  exit(await proc.exitCode);
}
