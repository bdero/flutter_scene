@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_gpu_shaders/environment.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/fmat/fmat.dart';
import 'package:flutter_test/flutter_test.dart';

const _fin = '''
material {
  name: "Fin",
  shading_model: lit,
  blending: alpha,
  effects_depth: true,
  culling: none,
  parameters: [
    { type: sampler2D, name: stripes },
  ],
}

fragment {
  void Surface(inout MaterialInputs material) {
    material.base_color = vec4(0.9, 0.9, 0.9, texture(stripes, GetUV0()).a);
  }
}
''';

void main() {
  test('effects_depth ships depth fragments cut by the surface alpha', () {
    final compiled = compileFmat(_fin, fileName: 'fin.fmat');
    expect(compiled.material.effectsDepth, isTrue);
    expect(compiled.material.depthWrite, isFalse);
    final sidecar = buildSidecar(compiled.material);
    expect(sidecar['effects_depth'], isTrue);
    expect(sidecar.containsKey('depth_write'), isFalse);
    expect(sidecar['depth_surface'], {
      'linear_depth': 'FinDepthSurface',
      'linear_depth_normal': 'FinDepthNormalSurface',
      'shadow': 'FinShadowSurface',
    });
    for (final kind in DepthSurfaceKind.values) {
      final source = emitFragmentGlsl(compiled.material, depthSurface: kind);
      expect(source, contains('if (material.base_color.a < 0.5)'));
    }
  });

  test('effects_depth needs a translucent material', () {
    expect(
      () => compileFmat(
        _fin.replaceFirst('blending: alpha,', 'blending: opaque,'),
        fileName: 'bad.fmat',
      ),
      throwsA(isA<FmatException>()),
    );
  });

  test('effects_depth depth fragments compile', () async {
    final impellerc = await findImpellerC();
    final temp = Directory.systemTemp.createTempSync('effects_depth');
    try {
      final compiled = compileFmat(_fin, fileName: 'fin.fmat');
      for (final kind in DepthSurfaceKind.values) {
        final input = File.fromUri(temp.uri.resolve('${kind.name}.frag'))
          ..writeAsStringSync(
            emitFragmentGlsl(compiled.material, depthSurface: kind),
          );
        final result = await Process.run(impellerc.toFilePath(), [
          '--metal-desktop',
          '--input-type=frag',
          '--input=${input.path}',
          '--sl=${temp.uri.resolve('${kind.name}.metal').toFilePath()}',
          '--spirv=${temp.uri.resolve('${kind.name}.spirv').toFilePath()}',
          '--define=IMPELLER_TARGET_METAL',
          '--include=${Directory.current.uri.resolve('shaders/').toFilePath()}',
          '--include=${impellerc.resolve('./shader_lib').toFilePath()}',
        ]);
        expect(
          result.exitCode,
          0,
          reason: '${kind.name}\n${result.stdout}\n${result.stderr}',
        );
      }
    } finally {
      temp.deleteSync(recursive: true);
    }
  });
}
