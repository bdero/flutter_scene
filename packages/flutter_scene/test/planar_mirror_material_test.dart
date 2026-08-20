// The `planar_reflection` engine input: parsing, the emitted sampler,
// uniform block, and accessor, the sidecar round trip, and (when impellerc
// resolves) a cross-backend compile of every generated variant within the
// fragment sampler budget.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_gpu_shaders/environment.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/fmat/build_materials.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/fmat/fmat.dart';
import 'package:flutter_test/flutter_test.dart';

const String kMirrorFmat = '''
material {
  name: "PlanarMirror",
  shading_model: lit,
  engine_inputs: [ planar_reflection ],
  parameters: [
    { type: vec4, name: base_color, hint: source_color,
      default: [0.9, 0.9, 0.95, 1.0] },
    { type: float, name: reflectivity, hint: range(0, 1, 0.01), default: 1.0 },
  ],
}

fragment {
  void Surface(inout MaterialInputs material) {
    vec4 reflection = GetPlanarReflection();
    material.base_color = material_params.base_color;
    material.metallic = 1.0;
    // With a live capture the mirror term rides emissive and the surface
    // goes rough so the environment reflection bows out; without one the
    // sharp environment reflection is the fallback.
    material.roughness = mix(0.05, 1.0, reflection.a);
    material.emissive = material_params.base_color.rgb * reflection.rgb *
        (material_params.reflectivity * reflection.a);
    PrepareMaterial(material);
  }
}
''';

void main() {
  test('a lit surface material may declare planar_reflection', () {
    final compiled = compileFmat(kMirrorFmat, fileName: 'mirror.fmat');
    expect(compiled.material.engineInputs, ['planar_reflection']);
    expect(compiled.sidecar['engine_inputs'], ['planar_reflection']);
  });

  test('the emitted fragment carries the sampler, block, and accessor', () {
    final compiled = compileFmat(kMirrorFmat, fileName: 'mirror.fmat');
    expect(compiled.glsl, contains('uniform sampler2D planar_reflection;'));
    expect(compiled.glsl, contains('uniform PlanarReflectionInfo {'));
    expect(compiled.glsl, contains('mat4 view_projection;'));
    expect(compiled.glsl, contains('vec4 GetPlanarReflection()'));
    expect(compiled.glsl, contains('planar_reflection_info.params.x < 0.5'));
    // Projective sampling maps NDC into the engine's top-down capture UV.
    expect(compiled.glsl, contains('0.5 - 0.5 * clip.y / clip.w'));
  });

  test('materials without the input emit none of the planar plumbing', () {
    const plain = '''
material {
  name: "Plain",
  shading_model: lit,
}

fragment {
  void Surface(inout MaterialInputs material) {
    material.base_color = vec4(1.0);
    PrepareMaterial(material);
  }
}
''';
    final compiled = compileFmat(plain, fileName: 'plain.fmat');
    expect(compiled.glsl, isNot(contains('planar_reflection')));
    expect(compiled.sidecar.containsKey('engine_inputs'), isFalse);
  });

  test('an unknown engine input names planar_reflection as supported', () {
    const bad = '''
material {
  name: "Bad",
  engine_inputs: [ mirror_color ],
}

fragment {
  void Surface(inout MaterialInputs material) {
    PrepareMaterial(material);
  }
}
''';
    expect(
      () => compileFmat(bad, fileName: 'bad.fmat'),
      throwsA(
        isA<FmatException>().having(
          (e) => e.toString(),
          'message',
          contains('planar_reflection'),
        ),
      ),
    );
  });

  test('planar_reflection requires a lit shading model', () {
    const unlit = '''
material {
  name: "UnlitMirror",
  shading_model: unlit,
  engine_inputs: [ planar_reflection ],
}

fragment {
  void Surface(inout MaterialInputs material) {
    material.base_color = vec4(1.0);
    PrepareMaterial(material);
  }
}
''';
    expect(
      () => compileFmat(unlit, fileName: 'unlit.fmat'),
      throwsA(isA<FmatException>()),
    );
  });

  test('every generated variant compiles on every backend in budget', () async {
    Uri? impellerc;
    try {
      impellerc = await findImpellerC();
    } catch (_) {
      impellerc = null;
    }
    if (impellerc == null) {
      markTestSkipped('impellerc not found in the SDK cache');
      return;
    }

    const maxFragmentSamplers = 15;
    final compiled = compileFmat(kMirrorFmat, fileName: 'mirror.fmat');
    final variants = emitFragmentShaderVariants(
      compiled,
      generateShadowVariant: true,
    );
    expect(
      variants.keys,
      unorderedEquals({
        'PlanarMirror',
        'PlanarMirrorShadow',
        'PlanarMirrorCube',
        'PlanarMirrorShadowCube',
      }),
    );

    final temp = Directory.systemTemp.createTempSync('planar_mirror');
    try {
      for (final backend in ['--opengl-es', '--metal-desktop', '--vulkan']) {
        for (final variant in variants.entries) {
          final label = '${variant.key}_${backend.replaceAll('-', '_')}';
          final input = File.fromUri(temp.uri.resolve('$label.frag'))
            ..writeAsStringSync(variant.value);
          final reflection = File.fromUri(temp.uri.resolve('$label.json'));
          final result = await Process.run(impellerc.toFilePath(), [
            backend,
            '--input-type=frag',
            '--input=${input.path}',
            '--sl=${temp.uri.resolve('$label.sl').toFilePath()}',
            '--spirv=${temp.uri.resolve('$label.spirv').toFilePath()}',
            '--reflection-json=${reflection.path}',
            '--include=${Directory.current.uri.resolve('shaders/').toFilePath()}',
            '--include=${impellerc.resolve('./shader_lib').toFilePath()}',
            if (backend == '--opengl-es') '--gles-language-version=300',
          ]);
          expect(
            result.exitCode,
            0,
            reason: '$label\n${result.stdout}\n${result.stderr}',
          );
          final parsed =
              jsonDecode(reflection.readAsStringSync()) as Map<String, Object?>;
          final samplers = parsed['sampled_images'];
          if (samplers is List) {
            expect(
              samplers,
              hasLength(lessThanOrEqualTo(maxFragmentSamplers)),
              reason:
                  '$label declares ${samplers.length} fragment samplers, '
                  'over the $maxFragmentSamplers budget.',
            );
          }
        }
      }
    } finally {
      temp.deleteSync(recursive: true);
    }
  });
}
