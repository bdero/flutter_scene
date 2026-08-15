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
    List<String>? filesDeleted,
    List<String>? parseFailedPaths,
  }) : sourcePaths = sourcePaths ?? const {},
       filesDeleted = filesDeleted ?? const [],
       parseFailedPaths = parseFailedPaths ?? const [];

  /// Every extracted component schema, in source order.
  final List<ComponentSchema> schemas;

  /// The absolute source file declaring each component, keyed by type.
  final Map<String, String> sourcePaths;

  /// Stale generated outputs removed this sweep (a `.fscene.dart` whose
  /// source no longer declares components).
  final List<String> filesDeleted;

  /// Absolute paths of sources that failed to parse this sweep (mid-edit
  /// syntax errors). Their outputs are preserved and consumers must not
  /// retire the components they last declared.
  final List<String> parseFailedPaths;

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
/// the root. Idempotent, only changed files are rewritten; a `.fscene.dart`
/// whose source no longer declares components is deleted, and the registrar
/// and manifest refresh even when the last component disappears, so a
/// deleted component stops being registered instead of breaking the build.
/// Throws [ArgumentError] when `lib/` is missing.
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
  final expectedOutputs = <String>{};
  final packageName = _packageName(root.path);

  final parseFailedPaths = <String>[];
  for (final file in sources) {
    final relative = _relative(file.path, root.path);
    final result = extractComponents(file.readAsStringSync(), path: relative);
    diagnostics.addAll(result.diagnostics);
    if (result.parseFailed) {
      // A mid-edit syntax error says nothing about what the file declares;
      // keep its previous output (and let consumers keep its schemas) until
      // it parses again.
      parseFailedPaths.add(file.absolute.path);
      final outPath =
          '${file.path.substring(0, file.path.length - '.dart'.length)}'
          '.fscene.dart';
      if (File(outPath).existsSync()) expectedOutputs.add(outPath);
      continue;
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
    expectedOutputs.add(outPath);
  }

  // A generated codec whose source stopped declaring components (or was
  // deleted outright) is stale; leaving it breaks the build once its
  // component class is gone.
  final deleted = <String>[];
  for (final file in libDir.listSync(recursive: true).whereType<File>()) {
    if (!file.path.endsWith('.fscene.dart')) continue;
    if (expectedOutputs.contains(file.path)) continue;
    file.deleteSync();
    deleted.add(file.path);
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
  // The registrar and manifest also refresh when they exist with nothing
  // left to register (the last component was deleted): an emptied registrar
  // keeps the app's registerProjectComponents() call compiling while
  // registering nothing.
  final registrarPath = '${libDir.path}/$registrarPathUnderLib';
  final manifestPath = '${root.path}/$componentManifestFileName';
  if (codecLibraries.isNotEmpty ||
      dependencyRegistrars.isNotEmpty ||
      File(registrarPath).existsSync()) {
    final registrar = generateProjectRegistrar(
      codecLibraries: codecLibraries,
      dependencyRegistrars: dependencyRegistrars,
    );
    Directory('${libDir.path}/src').createSync(recursive: true);
    if (_writeIfChanged(registrarPath, registrar)) written.add(registrarPath);
    final manifest = encodeComponentManifest(
      schemas: schemas,
      registrarLibrary: registrarLibrary,
      registrarFunction: registrarLibrary == null ? null : registrarFunction,
    );
    if (_writeIfChanged(manifestPath, '$manifest\n')) {
      written.add(manifestPath);
    }
  }

  return ProjectGenerationResult(
    schemas: schemas,
    diagnostics: diagnostics,
    filesWritten: written,
    sourcePaths: sourcePaths,
    filesDeleted: deleted,
    parseFailedPaths: parseFailedPaths,
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
