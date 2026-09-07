import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:data_assets/data_assets.dart';
import 'package:flutter_scene/build_hooks.dart';
import 'package:hooks/hooks.dart';

/// Bakes the building SDK's identity and the flutter_scene version into an
/// `editor_build_info.json` data asset, so the running editor can compare a
/// selected Flutter installation (and an open project's flutter_scene
/// dependency) against what it was built with. Works identically for dev runs
/// and packaged builds, unlike the release-pin file (CI clone target) and
/// `tool_manifest.json` (describes the bundled toolchain, packaged only).
void main(List<String> args) {
  build(args, (input, output) async {
    // The terrain material. The editor is where terrain gets painted, and the
    // paint tool assigns this material to the terrain it paints — so the
    // editor has to have compiled it, or the assignment resolves to a material
    // that will not load and the ground draws as nothing.
    await buildTerrainMaterial(
      buildInput: input,
      buildOutput: output,
      sourceRoot: await _flutterScenePackageRoot(),
      pruneGeneratedTree: false,
    );
    if (!input.config.buildDataAssets) {
      return;
    }
    final info = <String, Object?>{
      ...await _frameworkInfo(),
      'flutterSceneVersion': await _flutterSceneVersion(),
    };
    final outDir = Directory.fromUri(
      input.packageRoot.resolve('build/editor_build_info/'),
    )..createSync(recursive: true);
    final file = File.fromUri(outDir.uri.resolve('editor_build_info.json'));
    file.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(info));
    output.assets.data.add(
      DataAsset(
        package: input.packageName,
        name: 'editor_build_info.json',
        file: file.uri,
      ),
    );
  });
}

/// The building SDK's `bin/cache/flutter.version.json`, already materialized
/// by the tool before hooks run. The SDK root comes from `FLUTTER_ROOT` (set
/// by the `flutter` launcher) or from walking up from the running `dart`
/// binary (`<root>/bin/cache/dart-sdk/bin/dart`).
Future<Map<String, Object?>> _frameworkInfo() async {
  final candidates = <String>[
    if (Platform.environment['FLUTTER_ROOT'] case final String root) root,
    // dart lives at <root>/bin/cache/dart-sdk/bin/dart.
    File(Platform.resolvedExecutable).parent.parent.parent.parent.parent.path,
  ];
  for (final root in candidates) {
    final file = File('$root/bin/cache/flutter.version.json');
    if (!file.existsSync()) continue;
    final decoded = jsonDecode(file.readAsStringSync());
    if (decoded is! Map) continue;
    return {
      'frameworkVersion': decoded['frameworkVersion'],
      'frameworkRevision': decoded['frameworkRevision'],
      'engineRevision': decoded['engineRevision'],
      'engineContentHash': decoded['engineContentHash'],
      'dartSdkVersion': decoded['dartSdkVersion'],
      'repositoryUrl': decoded['repositoryUrl'],
    };
  }
  return const {};
}

/// The resolved flutter_scene package's pubspec version.
Future<String?> _flutterSceneVersion() async {
  final libUri = await Isolate.resolvePackageUri(
    Uri.parse('package:flutter_scene/scene.dart'),
  );
  if (libUri == null) return null;
  final pubspec = File.fromUri(libUri.resolve('../pubspec.yaml'));
  if (!pubspec.existsSync()) return null;
  final match = RegExp(
    r'^version:\s*(\S+)',
    multiLine: true,
  ).firstMatch(pubspec.readAsStringSync());
  return match?.group(1);
}

/// flutter_scene's own package root, which its shipped `.fmat` sources resolve
/// against.
Future<Uri> _flutterScenePackageRoot() async {
  final uri = await Isolate.resolvePackageUri(
    Uri.parse('package:flutter_scene/flutter_scene.dart'),
  );
  if (uri == null) {
    throw StateError(
      'Could not resolve package:flutter_scene, so the terrain material has '
      'no source to compile from.',
    );
  }
  // .../flutter_scene/lib/flutter_scene.dart -> .../flutter_scene/
  return uri.resolve('../');
}
