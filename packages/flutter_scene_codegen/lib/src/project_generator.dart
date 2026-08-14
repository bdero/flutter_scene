/// The whole-project generation sweep shared by the CLI and the editor's
/// watch loop: extract every annotated component under `lib/`, write the
/// codec libraries, the project registrar, and the component manifest, and
/// return the schemas for immediate adoption.
library;

import 'dart:io';

import 'package:scene/schema.dart';

import 'package:flutter_scene_codegen/src/extractor.dart';
import 'package:flutter_scene_codegen/src/generator.dart';
import 'package:flutter_scene_codegen/src/manifest.dart';

/// What one sweep produced.
class ProjectGenerationResult {
  ProjectGenerationResult({
    required this.schemas,
    required this.diagnostics,
    required this.filesWritten,
    Map<String, String>? sourcePaths,
  }) : sourcePaths = sourcePaths ?? const {};

  /// Every extracted component schema, in source order.
  final List<ComponentSchema> schemas;

  /// The absolute source file declaring each component, keyed by type.
  final Map<String, String> sourcePaths;

  /// Extraction diagnostics across all files.
  final List<ExtractionDiagnostic> diagnostics;

  /// Paths written this sweep (unchanged files are skipped).
  final List<String> filesWritten;

  bool get hadErrors =>
      diagnostics.any((d) => d.severity == ExtractionSeverity.error);
}

/// Sweeps [projectRoot] (which must contain `lib/`): extracts annotated
/// components, writes `<file>.fscene.dart` beside each source declaring any,
/// `lib/src/fscene_registrar.g.dart` (wiring dependency registrars found via
/// the package-config manifest scan), and `flutter_scene_components.json` at
/// the root. Idempotent, only changed files are rewritten. Throws
/// [ArgumentError] when `lib/` is missing.
// TODO(stale-outputs): remove .fscene.dart files whose source no longer
// declares components.
ProjectGenerationResult generateProjectComponents(String projectRoot) {
  final root = Directory(projectRoot).absolute;
  final libDir = Directory('${root.path}/lib');
  if (!libDir.existsSync()) {
    throw ArgumentError('No lib/ directory under ${root.path}');
  }

  final sources = libDir.listSync(recursive: true).whereType<File>().where((
    file,
  ) {
    final path = file.path;
    return path.endsWith('.dart') &&
        !path.endsWith('.fscene.dart') &&
        !path.endsWith('.g.dart');
  }).toList()..sort((a, b) => a.path.compareTo(b.path));

  final written = <String>[];
  final diagnostics = <ExtractionDiagnostic>[];
  final codecLibraries = <({String importUri, List<String> codecClassNames})>[];
  final schemas = <ComponentSchema>[];
  final sourcePaths = <String, String>{};
  final packageName = _packageName(root.path);

  for (final file in sources) {
    final relative = _relative(file.path, root.path);
    final result = extractComponents(file.readAsStringSync(), path: relative);
    diagnostics.addAll(result.diagnostics);
    if (result.components.isEmpty) continue;
    final basename = file.uri.pathSegments.last;
    final generated = generateCodecLibrary(
      components: result.components,
      sourceImport: basename,
    );
    final outPath =
        '${file.path.substring(0, file.path.length - '.dart'.length)}'
        '.fscene.dart';
    if (_writeIfChanged(outPath, generated)) written.add(outPath);
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
    for (final component in result.components) {
      sourcePaths[component.schema.type] = file.absolute.path;
    }
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
  const registrarPathUnderLib = 'src/fscene_registrar.g.dart';
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
    if (_writeIfChanged(registrarPath, registrar)) written.add(registrarPath);
    final manifest = encodeComponentManifest(
      schemas: schemas,
      registrarLibrary: registrarLibrary,
      registrarFunction: registrarLibrary == null ? null : registrarFunction,
    );
    final manifestPath = '${root.path}/$componentManifestFileName';
    if (_writeIfChanged(manifestPath, '$manifest\n')) {
      written.add(manifestPath);
    }
  }

  return ProjectGenerationResult(
    schemas: schemas,
    diagnostics: diagnostics,
    filesWritten: written,
    sourcePaths: sourcePaths,
  );
}

/// Writes [content] to [path] unless it already matches, so reruns keep
/// file timestamps (and downstream rebuilds) stable.
bool _writeIfChanged(String path, String content) {
  final file = File(path);
  if (file.existsSync() && file.readAsStringSync() == content) return false;
  file.writeAsStringSync(content);
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
