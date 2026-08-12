/// The `flutter_scene_components.json` manifest: the schemas a package's
/// components declare plus the registrar entry point that installs their
/// codecs, so editors and tooling discover component types across package
/// boundaries without compiling them.
library;

import 'dart:convert';
import 'dart:io';

import 'package:scene/schema.dart';

/// The manifest file name, looked up at each package root.
const String componentManifestFileName = 'flutter_scene_components.json';

/// A decoded manifest: the declared schemas and the optional registrar
/// (library URI plus function name) that installs the matching codecs.
typedef ComponentManifest = ({
  List<ComponentSchema> schemas,
  String? registrarLibrary,
  String? registrarFunction,
});

/// Encodes the manifest JSON for [schemas], naming the registrar entry
/// point when one exists.
String encodeComponentManifest({
  required Iterable<ComponentSchema> schemas,
  String? registrarLibrary,
  String? registrarFunction,
}) {
  final payload = <String, Object?>{
    'schemas': encodeComponentSchemas(schemas),
    if (registrarLibrary != null || registrarFunction != null)
      'registrar': {
        if (registrarLibrary != null) 'library': registrarLibrary,
        if (registrarFunction != null) 'function': registrarFunction,
      },
  };
  return const JsonEncoder.withIndent('  ').convert(payload);
}

/// Decodes manifest [content]; malformed schema entries are skipped and a
/// missing registrar decodes to nulls.
ComponentManifest decodeComponentManifest(String content) {
  final json = jsonDecode(content);
  final map = json is Map ? json : const <String, Object?>{};
  final registrar = map['registrar'];
  return (
    schemas: decodeComponentSchemas(map['schemas']),
    registrarLibrary: registrar is Map ? registrar['library'] as String? : null,
    registrarFunction: registrar is Map
        ? registrar['function'] as String?
        : null,
  );
}

/// Scans the packages resolved by the package config at [packageConfigPath]
/// (a `.dart_tool/package_config.json`) for `flutter_scene_components.json`
/// manifests at their roots.
List<({String package, String rootPath, Map<String, Object?> manifest})>
scanPackageManifests(String packageConfigPath) {
  final configFile = File(packageConfigPath);
  final results =
      <({String package, String rootPath, Map<String, Object?> manifest})>[];
  if (!configFile.existsSync()) return results;
  final Object? config;
  try {
    config = jsonDecode(configFile.readAsStringSync());
  } on FormatException {
    return results;
  }
  if (config is! Map) return results;
  final packages = config['packages'];
  if (packages is! List) return results;
  final configUri = configFile.absolute.uri;
  for (final entry in packages) {
    if (entry is! Map) continue;
    final name = entry['name'];
    final rootUri = entry['rootUri'];
    if (name is! String || rootUri is! String) continue;
    final Uri root;
    try {
      root = configUri.resolveUri(Uri.parse(rootUri));
    } on FormatException {
      continue;
    }
    if (root.scheme != 'file' && root.scheme != '') continue;
    final rootPath = root.toFilePath();
    final manifestFile = File(
      '$rootPath${rootPath.endsWith(Platform.pathSeparator) ? '' : Platform.pathSeparator}$componentManifestFileName',
    );
    if (!manifestFile.existsSync()) continue;
    final Object? manifest;
    try {
      manifest = jsonDecode(manifestFile.readAsStringSync());
    } on FormatException {
      continue;
    }
    if (manifest is! Map) continue;
    results.add((
      package: name,
      rootPath: manifestFile.parent.path,
      manifest: manifest.cast<String, Object?>(),
    ));
  }
  return results;
}
