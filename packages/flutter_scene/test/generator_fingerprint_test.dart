// The build stamps fingerprint the code that writes each output, so changing
// that code rebuilds the output without a manual revision bump.

// ignore_for_file: implementation_imports

import 'package:flutter_scene/src/importer/build_cache.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('each output kind fingerprints its own generator', () {
    final scene = sceneGeneratorFingerprint();
    final texture = textureGeneratorFingerprint();
    final material = materialCompilerFingerprint();
    expect({scene, texture, material}, hasLength(3));
    expect(sceneGeneratorFingerprint(), scene);
  });

  test('the compiler sources skip runtime code a hook cannot run', () {
    final names = [
      for (final uri in materialCompilerSources()) uri.pathSegments.last,
    ];
    expect(names, containsAll(['fmat_emitter.dart', 'fmat_parser.dart']));
    // Both import Flutter, so they are runtime-only.
    expect(names, isNot(contains('material_registry.dart')));
    expect(names, isNot(contains('fmat_bytes_library.dart')));
  });
}
