// Guards the runtime library's dependency graph. `lib/scene.dart` must stay
// free of `dart:io` and of the hook-only sources, so the package keeps compiling
// for web (dart2js rejects the 64-bit hash constants) and for wasm.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

final RegExp _directive = RegExp(
  r'''^\s*(?:import|export)\s+'([^']+)'|^\s*(?:import|export)\s+"([^"]+)"''',
  multiLine: true,
);

/// Every library reachable from [entry] through relative and
/// `package:flutter_scene/` directives, plus the SDK libraries they name.
({Set<String> files, Set<String> sdk}) _closure(Uri lib, String entry) {
  final files = <String>{};
  final sdk = <String>{};
  final queue = <Uri>[lib.resolve(entry)];
  while (queue.isNotEmpty) {
    final uri = queue.removeLast();
    final path = uri.toFilePath();
    if (!files.add(path)) continue;
    final file = File(path);
    if (!file.existsSync()) continue;
    for (final match in _directive.allMatches(file.readAsStringSync())) {
      final target = match.group(1) ?? match.group(2)!;
      if (target.startsWith('dart:')) {
        sdk.add(target);
        continue;
      }
      if (target.startsWith('package:flutter_scene/')) {
        queue.add(
          lib.resolve(target.substring('package:flutter_scene/'.length)),
        );
        continue;
      }
      if (target.contains(':')) continue;
      queue.add(uri.resolve(target));
    }
  }
  return (files: files, sdk: sdk);
}

void main() {
  final lib = Directory.current.uri.resolve('lib/');

  test('scene.dart reaches no dart:io and no hook-only source', () {
    final closure = _closure(lib, 'scene.dart');
    expect(closure.sdk, isNot(contains('dart:io')));
    for (final hookOnly in [
      'src/generated_assets/generated_tree.dart',
      'src/generated_assets/generated_file_names.dart',
      'src/generated_assets/build_engine_assets.dart',
      'src/importer/build_cache.dart',
    ]) {
      expect(
        closure.files,
        isNot(contains(lib.resolve(hookOnly).toFilePath())),
        reason: '$hookOnly is hook-only; it uses dart:io or 64-bit literals',
      );
    }
  });

  test('the shared generated-asset layout stays pure Dart', () {
    final closure = _closure(lib, 'src/generated_assets/generated_assets.dart');
    expect(closure.sdk, ['dart:convert']);
  });
}
