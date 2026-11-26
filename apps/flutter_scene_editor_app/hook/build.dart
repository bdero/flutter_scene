import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:hooks/hooks.dart';

/// Bakes the building SDK's identity and the flutter_scene version into
/// `editor_build_info/editor_build_info.json`, so the running editor can
/// compare a selected Flutter installation (and an open project's
/// flutter_scene dependency) against what it was built with. Works
/// identically for dev runs and packaged builds, unlike the release-pin file
/// (CI clone target) and `tool_manifest.json` (describes the bundled
/// toolchain, packaged only).
///
/// It is a plain asset (listed in pubspec.yaml) rather than a data asset,
/// since data assets are master-only and the editor builds on stable.
void main(List<String> args) {
  build(args, (input, output) async {
    final info = <String, Object?>{
      ...await _frameworkInfo(),
      'flutterSceneVersion': await _flutterSceneVersion(),
    };
    final file = File.fromUri(
      input.packageRoot.resolve('editor_build_info/editor_build_info.json'),
    );
    final encoded = const JsonEncoder.withIndent('  ').convert(info);
    // An unchanged file keeps its mtime.
    if (!file.existsSync() || file.readAsStringSync() != encoded) {
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(encoded);
    }
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
