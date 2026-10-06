// Pins the stage interface check's table of engine varyings to the shaders
// that define them.
@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_scene/src/material/shader_interface.dart';
import 'package:flutter_scene/src/shader_reflection/shader_reflection.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('standardVaryings matches material_varyings.glsl', () {
    final source = File('shaders/material_varyings.glsl').readAsStringSync();
    final declared = [
      for (final match in RegExp(
        r'^in\s+(?:(?:highp|mediump|lowp)\s+)?(vec[234]|float)\s+(\w+)\s*;',
        multiLine: true,
      ).allMatches(source))
        (
          match.group(1) == 'float' ? 'float' : 'float${match.group(1)![3]}',
          match.group(2)!,
        ),
    ];
    expect(declared, [
      for (final varying in standardVaryings) (varying.type, varying.name),
    ]);
    expect(
      standardVaryings.map((v) => v.location),
      List.generate(standardVaryings.length, (i) => i),
    );
  });

  // The compiled bundle is built by the package's hook and gitignored, so
  // this runs where a build has produced it and skips elsewhere.
  final generated = Directory('flutter_scene_generated/metal_desktop');
  final bundles = (generated.existsSync() ? generated.listSync() : const [])
      .whereType<File>()
      .where(
        (f) =>
            RegExp(r'shaderbundle\.base\.\w+\.shaderbundle$').hasMatch(f.path),
      )
      .toList();
  test('every standard vertex shader writes standardVaryings', () {
    for (final bundle in bundles) {
      final info = ShaderBundleInfo.parse(bundle.readAsBytesSync());
      for (final name in standardVertexShaderNames) {
        final msl = info[name]?.backends[ShaderBackend.metalDesktop];
        expect(msl, isNotNull, reason: '$name in ${bundle.path}');
        expect(
          parseMslVaryings(msl!.source.text!, msl.entrypoint, outputs: true),
          standardVaryings,
          reason: '$name in ${bundle.path}',
        );
      }
    }
  }, skip: bundles.isEmpty ? 'no compiled base bundle in this checkout' : null);
}
