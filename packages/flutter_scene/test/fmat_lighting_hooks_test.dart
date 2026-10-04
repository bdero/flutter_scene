@TestOn('vm')
library;

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

// A lit material that supplies its own ambient: the engine IBL samplers are
// compiled out, leaving room for many material textures.
final _customAmbient =
    '''
material {
  name: "CustomAmbient",
  shading_model: lit,
  environment_lighting: false,
  parameters: [
${[for (var i = 0; i < 12; i++) '    { type: sampler2D, name: tex$i },'].join('\n')}
  ],
}

fragment {
  highp vec3 g_ambient;

  void Surface(inout MaterialInputs material) {
    vec4 sum = vec4(0.0);
${[for (var i = 0; i < 12; i++) '    sum += texture(tex$i, GetUV0());'].join('\n')}
    material.base_color = vec4(sum.rgb / 12.0, 1.0);
    g_ambient = sum.rgb * 0.1;
  }

  highp vec4 Composite(MaterialInputs material, LightingResult r) {
    return vec4(r.direct_diffuse + r.direct_specular + g_ambient, 1.0) *
        r.alpha;
  }
}
''';

Future<Map<String, Object?>> _compile(
  Uri impellerc,
  Directory temp,
  String entry,
  String source,
  String backend,
) async {
  final input = File.fromUri(temp.uri.resolve('$entry.frag'))
    ..writeAsStringSync(source);
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
  return jsonDecode(reflection.readAsStringSync()) as Map<String, Object?>;
}

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

  test('custom ambient drops the engine IBL samplers', () async {
    final impellerc = await findImpellerC();
    final temp = Directory.systemTemp.createTempSync('custom_ambient');
    try {
      final compiled = compileFmat(_customAmbient, fileName: 'custom.fmat');
      final variants = emitFragmentShaderVariants(
        compiled,
        generateShadowVariant: true,
      );
      // No radiance-cube twin: the material never samples the environment.
      expect(variants.keys.where((k) => k.endsWith('Cube')), isEmpty);
      for (final variant in variants.entries) {
        expect(variant.value, contains('#define FLUTTER_SCENE_CUSTOM_AMBIENT'));
        for (final backend in _backends) {
          final json = await _compile(
            impellerc,
            temp,
            '${variant.key}${backend.replaceAll('-', '_')}',
            variant.value,
            backend,
          );
          final names = [
            for (final s in json['sampled_images']! as List) (s as Map)['name'],
          ];
          for (final absent in [
            'prefiltered_radiance',
            'prefiltered_radiance_b',
            'brdf_lut',
            'irradiance_field',
            'ssao_texture',
          ]) {
            expect(names, isNot(contains(absent)));
          }
          expect(names.length, lessThanOrEqualTo(15));
        }
      }
    } finally {
      temp.deleteSync(recursive: true);
    }
  });

  test('environment_lighting: false requires a lit material', () {
    expect(
      () => compileFmat(
        _customAmbient.replaceFirst(
          'shading_model: lit',
          'shading_model: unlit',
        ),
        fileName: 'bad.fmat',
      ),
      throwsA(isA<FmatException>()),
    );
  });

  test('directional_light: false compiles the light out', () async {
    final impellerc = await findImpellerC();
    final temp = Directory.systemTemp.createTempSync('no_directional');
    try {
      final compiled = compileFmat(
        _hooked.replaceFirst(
          'shading_model: lit,',
          'shading_model: lit,\n  directional_light: false,',
        ),
        fileName: 'no_directional.fmat',
      );
      expect(compiled.material.directionalLight, isFalse);
      final variants = emitFragmentShaderVariants(
        compiled,
        generateShadowVariant: true,
      );
      final full = emitFragmentShaderVariants(
        compileFmat(_hooked, fileName: 'hooked.fmat'),
        generateShadowVariant: true,
      );
      for (final variant in variants.entries) {
        expect(
          variant.value,
          contains('#define FLUTTER_SCENE_NO_DIRECTIONAL_LIGHT'),
        );
        await _compile(
          impellerc,
          temp,
          '${variant.key}_gles',
          variant.value,
          '--opengl-es',
        );
        // The light's inlined Light() copy is gone from the output.
        await _compile(
          impellerc,
          temp,
          '${variant.key}_full_gles',
          full[variant.key]!,
          '--opengl-es',
        );
        final trimmed = File.fromUri(
          temp.uri.resolve('${variant.key}_gles.out'),
        ).lengthSync();
        final untrimmed = File.fromUri(
          temp.uri.resolve('${variant.key}_full_gles.out'),
        ).lengthSync();
        expect(trimmed, lessThan(untrimmed));
      }
    } finally {
      temp.deleteSync(recursive: true);
    }
  });

  test('directional_light: false requires a lit material', () {
    expect(
      () => compileFmat(
        _customAmbient
            .replaceFirst('shading_model: lit', 'shading_model: unlit')
            .replaceFirst(
              'environment_lighting: false',
              'directional_light: false',
            ),
        fileName: 'bad.fmat',
      ),
      throwsA(isA<FmatException>()),
    );
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

  test('without Light(), the default BRDF keeps its specular lobe', () {
    final lighting = File('shaders/material_lighting.glsl').readAsStringSync();
    // A Composite() that weighs the lobes separately still gets highlights.
    expect(lighting, contains('direct_specular += sun_specular;'));
    expect(lighting, contains('direct_specular += punctual_specular;'));
    expect(
      lighting,
      isNot(contains('direct_diffuse += EvaluateAnalyticLight(')),
    );
  });
}
