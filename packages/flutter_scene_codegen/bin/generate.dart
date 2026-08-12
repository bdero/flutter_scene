/// Generates fscene codecs for every annotated component under a project's
/// `lib/`, plus the project registrar and the component manifest.
///
/// Usage, `dart run flutter_scene_codegen:generate [projectRoot]` (the
/// current directory by default). Writes `<file>.fscene.dart` beside each
/// source file containing annotated components,
/// `lib/src/fscene_registrar.g.dart`, and `flutter_scene_components.json`
/// at the project root. Only files whose content changed are rewritten.
library;

import 'dart:io';

import 'package:scene/schema.dart';

import 'package:flutter_scene_codegen/flutter_scene_codegen.dart';

void main(List<String> args) {
  if (args.length > 1 || args.contains('--help') || args.contains('-h')) {
    stderr.writeln(
      'Usage: dart run flutter_scene_codegen:generate [projectRoot]',
    );
    exit(args.length > 1 ? 64 : 0);
  }
  final root = Directory(args.isEmpty ? '.' : args.first).absolute;
  final libDir = Directory('${root.path}/lib');
  if (!libDir.existsSync()) {
    stderr.writeln('No lib/ directory under ${root.path}');
    exit(64);
  }

  final sources = libDir.listSync(recursive: true).whereType<File>().where((
    file,
  ) {
    final path = file.path;
    return path.endsWith('.dart') &&
        !path.endsWith('.fscene.dart') &&
        !path.endsWith('.g.dart');
  }).toList()..sort((a, b) => a.path.compareTo(b.path));

  var hadErrors = false;
  var wrote = 0;
  final codecLibraries = <({String importUri, List<String> codecClassNames})>[];
  final schemas = <ComponentSchema>[];
  final packageName = _packageName(root.path);

  for (final file in sources) {
    final relative = _relative(file.path, root.path);
    final result = extractComponents(file.readAsStringSync(), path: relative);
    for (final diagnostic in result.diagnostics) {
      stderr.writeln(diagnostic);
      hadErrors = hadErrors || diagnostic.severity == ExtractionSeverity.error;
    }
    if (result.components.isEmpty) continue;
    final basename = file.uri.pathSegments.last;
    final generated = generateCodecLibrary(
      components: result.components,
      sourceImport: basename,
    );
    final outPath =
        '${file.path.substring(0, file.path.length - '.dart'.length)}'
        '.fscene.dart';
    if (_writeIfChanged(outPath, generated)) wrote++;
    final pathUnderLib = _relative(outPath, libDir.path);
    codecLibraries.add((
      importUri: packageName == null
          ? _relativeImport(pathUnderLib)
          : 'package:$packageName/$pathUnderLib',
      codecClassNames: [
        for (final component in result.components)
          codecClassNameFor(component.className),
      ],
    ));
    schemas.addAll([
      for (final component in result.components) component.schema,
    ]);
  }

  final dependencyRegistrars = <({String importUri, String functionName})>[];
  for (final found in scanPackageManifests(
    '${root.path}/.dart_tool/package_config.json',
  )) {
    if (found.package == packageName) continue;
    final registrar = found.manifest['registrar'];
    if (registrar is! Map) continue;
    final library = registrar['library'];
    final function = registrar['function'];
    if (library is! String || function is! String) continue;
    dependencyRegistrars.add((importUri: library, functionName: function));
  }

  const registrarFunction = 'registerProjectComponents';
  final registrarPathUnderLib = 'src/fscene_registrar.g.dart';
  final registrarLibrary = packageName == null
      ? null
      : 'package:$packageName/$registrarPathUnderLib';
  if (codecLibraries.isNotEmpty || dependencyRegistrars.isNotEmpty) {
    final registrar = generateProjectRegistrar(
      codecLibraries: codecLibraries,
      dependencyRegistrars: dependencyRegistrars,
    );
    final registrarPath = '${libDir.path}/$registrarPathUnderLib';
    Directory('${libDir.path}/src').createSync(recursive: true);
    if (_writeIfChanged(registrarPath, registrar)) wrote++;
    final manifest = encodeComponentManifest(
      schemas: schemas,
      registrarLibrary: registrarLibrary,
      registrarFunction: registrarLibrary == null ? null : registrarFunction,
    );
    if (_writeIfChanged(
      '${root.path}/$componentManifestFileName',
      '$manifest\n',
    )) {
      wrote++;
    }
  } else {
    stdout.writeln('No annotated components found under ${libDir.path}');
  }

  stdout.writeln(
    'Generated ${schemas.length} component schema(s); '
    '$wrote file(s) written.',
  );
  // TODO(stale-outputs): remove .fscene.dart files whose source no longer
  // declares components.
  if (hadErrors) exit(1);
}

/// Writes [content] to [path] unless it already matches, so reruns keep
/// file timestamps (and downstream rebuilds) stable.
bool _writeIfChanged(String path, String content) {
  final file = File(path);
  if (file.existsSync() && file.readAsStringSync() == content) return false;
  file.writeAsStringSync(content);
  stdout.writeln('wrote ${file.path}');
  return true;
}

String? _packageName(String projectRoot) {
  final pubspec = File('$projectRoot/pubspec.yaml');
  if (!pubspec.existsSync()) return null;
  for (final line in pubspec.readAsLinesSync()) {
    final match = RegExp(r'^name:\s*(\S+)\s*$').firstMatch(line);
    if (match != null) return match.group(1);
  }
  return null;
}

String _relative(String path, String from) {
  final prefix = from.endsWith('/') ? from : '$from/';
  return path.startsWith(prefix) ? path.substring(prefix.length) : path;
}

/// A relative import from `lib/src/` (the registrar's directory) to a path
/// under `lib/`.
String _relativeImport(String pathUnderLib) => '../$pathUnderLib';
