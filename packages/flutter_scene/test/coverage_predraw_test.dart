import 'dart:convert';
import 'dart:io';

import 'package:flutter_scene/scene.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/fmat/fmat.dart';
import 'package:flutter_test/flutter_test.dart';

// The source with `//` comments removed, so prose mentioning discard does not
// count.
String _code(String source) =>
    source.split('\n').map((line) => line.split('//').first).join('\n');

void main() {
  test('the opaque material shaders never discard', () {
    // A discard anywhere in a shader turns off early depth testing and
    // hidden-surface removal for its every draw on tiled GPUs; cutouts go
    // through the coverage pre-draw instead.
    for (final path in [
      'shaders/flutter_scene_standard.frag',
      'shaders/flutter_scene_unlit.frag',
    ]) {
      final code = _code(File(path).readAsStringSync());
      expect(code, isNot(contains('discard')), reason: path);
      expect(code, isNot(contains('ApplyLodFade')), reason: path);
    }
    const physical = 'assets/materials/physical_opaque.fmat';
    final compiled = compileFmat(
      File(physical).readAsStringSync(),
      fileName: physical,
    );
    expect(_code(compiled.glsl), isNot(contains('discard')));
  });

  test('the coverage pre-draw applies the cross-fade and the mask', () {
    final code = _code(
      File('shaders/flutter_scene_coverage.frag').readAsStringSync(),
    );
    expect(code, contains('ApplyLodFade(coverage_info.fade)'));
    expect(code, contains('ApplyDepthAlphaMask()'));
    final bundle =
        jsonDecode(File('shaders/base.shaderbundle.json').readAsStringSync())
            as Map<String, Object?>;
    expect(bundle['CoverageFragment'], {
      'type': 'fragment',
      'file': 'shaders/flutter_scene_coverage.frag',
    });
  });

  test('the built-in lit and unlit materials cross-fade', () {
    expect(PhysicallyBasedMaterial().lodCrossFades, isTrue);
    expect(UnlitMaterial().lodCrossFades, isTrue);
  });

  test('an alpha-masked material cuts out through its depth mask', () {
    final material = PhysicallyBasedMaterial();
    expect(material.depthAlphaMasked, isFalse);
    material.alphaMode = AlphaMode.mask;
    expect(material.depthAlphaMasked, isTrue);
  });
}
