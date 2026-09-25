import 'dart:io';

import 'package:flutter_gpu_shaders/environment.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/fmat/fmat.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/fmat/fmat_emitter.dart';
import 'package:flutter_test/flutter_test.dart';

const _cutout = '''
material {
  name: "Cutout",
  shading_model: lit,
  alpha_to_coverage: true,
  parameters: [
    { type: sampler2D, name: mask },
  ],
}

fragment {
  void Surface(inout MaterialInputs material) {
    material.base_color = vec4(0.2, 0.6, 0.1, texture(mask, GetUV0()).a);
  }
}
''';

// Bundle builds define the target macro per entry; a direct compile must
// pass it, or the GLES entry would see the sample mask.
const _backends = {
  '--opengl-es': 'IMPELLER_TARGET_OPENGLES',
  '--metal-desktop': 'IMPELLER_TARGET_METAL',
  '--vulkan': 'IMPELLER_TARGET_VULKAN',
};

void main() {
  test('alpha_to_coverage writes coverage from the surface alpha', () {
    final compiled = compileFmat(_cutout, fileName: 'cutout.fmat');
    expect(compiled.material.alphaToCoverage, isTrue);
    final source = emitFragmentGlsl(compiled.material);
    expect(source, contains('#include <material_coverage.glsl>'));
    expect(source, contains('ApplyAlphaToCoverage(material.base_color.a);'));
    expect(buildSidecar(compiled.material)['alpha_to_coverage'], isTrue);
  });

  test('alpha_to_coverage needs an opaque material', () {
    expect(
      () => compileFmat(
        _cutout.replaceFirst(
          'alpha_to_coverage: true,',
          'alpha_to_coverage: true,\n  blending: alpha,',
        ),
        fileName: 'bad.fmat',
      ),
      throwsA(isA<FmatException>()),
    );
  });

  test('alpha_to_coverage compiles on every backend', () async {
    final impellerc = await findImpellerC();
    final temp = Directory.systemTemp.createTempSync('alpha_to_coverage');
    try {
      final compiled = compileFmat(_cutout, fileName: 'cutout.fmat');
      final source = emitFragmentGlsl(compiled.material);
      for (final MapEntry(key: backend, value: define) in _backends.entries) {
        final entry = 'cutout${backend.replaceAll('-', '_')}';
        final input = File.fromUri(temp.uri.resolve('$entry.frag'))
          ..writeAsStringSync(source);
        final output = temp.uri.resolve('$entry.out').toFilePath();
        final result = await Process.run(impellerc.toFilePath(), [
          backend,
          '--input-type=frag',
          '--input=${input.path}',
          '--sl=$output',
          '--spirv=${temp.uri.resolve('$entry.spirv').toFilePath()}',
          '--define=$define',
          '--include=${Directory.current.uri.resolve('shaders/').toFilePath()}',
          '--include=${impellerc.resolve('./shader_lib').toFilePath()}',
          if (backend == '--opengl-es') '--gles-language-version=300',
        ]);
        expect(
          result.exitCode,
          0,
          reason: '$entry\n${result.stdout}\n${result.stderr}',
        );
        if (backend == '--metal-desktop') {
          expect(File(output).readAsStringSync(), contains('sample_mask'));
        }
      }
    } finally {
      temp.deleteSync(recursive: true);
    }
  });
}
