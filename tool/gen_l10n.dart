// Generates the localization classes of every module.
//
// Each module owns its ARB files in a `l10n/` folder next to its code:
//   lib/features/ocr/l10n/ocr_fr.arb   (template, French)
//   lib/features/ocr/l10n/ocr_en.arb
// and gets `OcrLocalizations` in `l10n/generated/ocr_localizations.dart`.
//
// Usage:
//   dart run tool/gen_l10n.dart            regenerate every module
//   dart run tool/gen_l10n.dart ocr core   regenerate the given modules only
//   dart run tool/gen_l10n.dart --list     print the delegate of every module
import 'dart:io';

const String _templateSuffix = '_fr.arb';

class L10nModule {
  L10nModule(this.name, this.directory);

  final String name;
  final String directory;

  String get className =>
      '${name.split('_').map((part) => part[0].toUpperCase() + part.substring(1)).join()}Localizations';

  String get outputFile => '${name}_localizations.dart';
}

List<L10nModule> discoverModules() {
  final modules = <L10nModule>[];
  for (final entity in Directory('lib').listSync(recursive: true)) {
    if (entity is! File) continue;
    final path = entity.path.replaceAll('\\', '/');
    final fileName = path.split('/').last;
    if (!path.contains('/l10n/') || path.contains('/generated/')) continue;
    if (!fileName.endsWith(_templateSuffix)) continue;
    modules.add(
      L10nModule(
        fileName.substring(0, fileName.length - _templateSuffix.length),
        path.substring(0, path.lastIndexOf('/')),
      ),
    );
  }
  modules.sort((a, b) => a.name.compareTo(b.name));
  return modules;
}

Future<int> generate(L10nModule module) async {
  final result = await Process.run('flutter', [
    'gen-l10n',
    '--arb-dir=${module.directory}',
    '--template-arb-file=${module.name}$_templateSuffix',
    '--output-dir=${module.directory}/generated',
    '--output-localization-file=${module.outputFile}',
    '--output-class=${module.className}',
    '--preferred-supported-locales=fr',
    '--no-nullable-getter',
    '--format',
  ], runInShell: true);
  stdout.write(result.stdout);
  stderr.write(result.stderr);
  return result.exitCode;
}

Future<void> main(List<String> args) async {
  final modules = discoverModules();
  if (args.contains('--list')) {
    for (final module in modules) {
      stdout.writeln(
        '${module.className}  ${module.directory}/generated/${module.outputFile}',
      );
    }
    return;
  }

  final requested = args.where((arg) => !arg.startsWith('--')).toSet();
  final unknown = requested.difference(modules.map((m) => m.name).toSet());
  if (unknown.isNotEmpty) {
    stderr.writeln('Unknown l10n module(s): ${unknown.join(', ')}');
    exitCode = 64;
    return;
  }

  var failures = 0;
  for (final module in modules) {
    if (requested.isNotEmpty && !requested.contains(module.name)) continue;
    stdout.writeln('gen-l10n ${module.name} -> ${module.className}');
    if (await generate(module) != 0) failures++;
  }
  if (failures > 0) {
    stderr.writeln('$failures module(s) failed.');
    exitCode = 1;
  }
}
