import 'dart:convert';
import 'dart:io';

import 'package:flutter_gpu_shaders/environment.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/fmat/build_materials.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/fmat/fmat.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/fmat/fmat_emitter.dart';
import 'package:flutter_test/flutter_test.dart';

const _hooked = '''
material {
  name: "Hooked",
  shading_model: lit,
  parameters: [
    { type: float, name: gain, default: 1.0 },
  ],
}

fragment {
  float g_wrap;

  void Surface(inout MaterialInputs material) {
    material.base_color = vec4(0.5, 0.5, 0.5, 1.0);
    g_wrap = 0.3;
  }

  LightTerms Light(MaterialInputs material, LightContext light) {
    float ndl = dot(light.normal, light.light_vector);
    LightTerms t;
    t.diffuse = light.radiance * clamp((ndl + g_wrap) / (1.0 + g_wrap), 0.0, 1.0) *
        material.base_color.rgb * (1.0 / 3.14159265);
    t.specular = vec3(0.0);
    return t;
  }

  void Ambient(MaterialInputs material, inout AmbientContext ambient) {
    ambient.irradiance *= material_params.gain;
    ambient.specular_occlusion = 0.5;
  }

  highp vec4 Composite(MaterialInputs material, LightingResult r) {
    return vec4(r.direct_diffuse + r.direct_specular + r.indirect_diffuse +
        r.indirect_specular + r.emissive, 1.0) * r.alpha;
  }
}
''';

const _backends = ['--opengl-es', '--metal-desktop', '--vulkan'];

void main() {
  test('detects only hooks with the expected signature', () {
    expect(lightingHooksIn(_hooked), {'Light', 'Ambient', 'Composite'});
    expect(lightingHooksIn('void Light(int x) {}'), isEmpty);
    expect(
      lightingHooksIn('vec3 Ambient(float x) { return vec3(x); }'),
      isEmpty,
    );
    expect(lightingHooksIn('void Surface(inout MaterialInputs m) {}'), isEmpty);
  });

  test('emits the hook defines for a lit material', () {
    final compiled = compileFmat(_hooked, fileName: 'hooked.fmat');
    final variants = emitFragmentShaderVariants(
      compiled,
      generateShadowVariant: true,
    );
    for (final source in variants.values) {
      expect(source, contains('#define FLUTTER_SCENE_HOOK_LIGHT'));
      expect(source, contains('#define FLUTTER_SCENE_HOOK_AMBIENT'));
      expect(source, contains('#define FLUTTER_SCENE_HOOK_COMPOSITE'));
    }
  });

  test('hooked lit variants compile on every backend', () async {
    final impellerc = await findImpellerC();
    final temp = Directory.systemTemp.createTempSync('lighting_hooks');
    try {
      final compiled = compileFmat(_hooked, fileName: 'hooked.fmat');
      final variants = emitFragmentShaderVariants(
        compiled,
        generateShadowVariant: true,
      );
      for (final variant in variants.entries) {
        for (final backend in _backends) {
          final entry = '${variant.key}${backend.replaceAll('-', '_')}';
          final input = File.fromUri(temp.uri.resolve('$entry.frag'))
            ..writeAsStringSync(variant.value);
          final reflection = File.fromUri(temp.uri.resolve('$entry.json'));
          final result = await Process.run(impellerc.toFilePath(), [
            backend,
            '--input-type=frag',
            '--input=${input.path}',
            '--sl=${temp.uri.resolve('$entry.out').toFilePath()}',
            '--spirv=${temp.uri.resolve('$entry.spirv').toFilePath()}',
            '--reflection-json=${reflection.path}',
            '--include=${Directory.current.uri.resolve('shaders/').toFilePath()}',
            '--include=${impellerc.resolve('./shader_lib').toFilePath()}',
            if (backend == '--opengl-es') '--gles-language-version=300',
          ]);
          expect(
            result.exitCode,
            0,
            reason: '$entry\n${result.stdout}\n${result.stderr}',
          );
          final json =
              jsonDecode(reflection.readAsStringSync()) as Map<String, Object?>;
          expect(
            (json['sampled_images']! as List).length,
            lessThanOrEqualTo(15),
          );
        }
      }
    } finally {
      temp.deleteSync(recursive: true);
    }
  });
}
