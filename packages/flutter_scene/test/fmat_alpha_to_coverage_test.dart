@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_gpu_shaders/environment.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/fmat/fmat.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/fmat/shader_bundle_lint.dart';
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

// A lit cutout with every lighting hook, whose depth surfaces must drop them.
const _hookedCutout = '''
material {
  name: "HookedCutout",
  shading_model: lit,
  alpha_to_coverage: true,
}

fragment {
  void Surface(inout MaterialInputs material) {
    vec2 cell = fract(GetUV0() * 4.0) - 0.5;
    material.base_color = vec4(0.25, 0.6, 0.15, step(0.3, length(cell)));
  }

  // A brace in a comment must not end the body early }
  LightTerms Light(MaterialInputs material, LightContext light) {
    LightTerms terms;
    terms.diffuse =
        light.radiance * max(dot(light.normal, light.light_vector), 0.0);
    terms.specular = vec3(0.0);
    return terms;
  }

  void Ambient(MaterialInputs material, inout AmbientContext ambient) {
    /* { */ ambient.irradiance *= 0.5;
  }

  highp vec4 Composite(MaterialInputs material, LightingResult r) {
    return vec4(r.direct_diffuse + r.indirect_diffuse, 1.0) * r.alpha;
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

  test('a cutout ships depth fragments cut by its surface alpha', () {
    final compiled = compileFmat(_cutout, fileName: 'cutout.fmat');
    final sidecar = buildSidecar(compiled.material);
    expect(sidecar['depth_surface'], {
      'linear_depth': 'CutoutDepthSurface',
      'linear_depth_normal': 'CutoutDepthNormalSurface',
      'shadow': 'CutoutShadowSurface',
    });
    for (final kind in DepthSurfaceKind.values) {
      final source = emitFragmentGlsl(compiled.material, depthSurface: kind);
      expect(source, contains('if (material.base_color.a < 0.5)'));
      expect(source, isNot(contains('EvaluateLighting(material)')));
      expect(source, contains('texture(mask, vec2(0.0)).x'));
    }
  });

  test('a lit cutout depth surface carries none of the lighting', () {
    // Unread lighting resources reflect at binding 0, which drops the draw on
    // Vulkan and breaks the WGSL sidecar's binding match.
    for (final fmat in [_cutout, _hookedCutout]) {
      final material = compileFmat(fmat, fileName: 'cutout.fmat').material;
      expect(
        emitFragmentGlsl(material),
        contains('#include <material_lighting.glsl>'),
      );
      for (final kind in DepthSurfaceKind.values) {
        final source = emitFragmentGlsl(material, depthSurface: kind);
        expect(source, isNot(contains('material_lighting.glsl')));
        expect(source, isNot(contains('material_engine_lighting.glsl')));
        expect(source, contains('#include <material_scene_inputs.glsl>'));
        expect(source, contains('#define FLUTTER_SCENE_NO_ENGINE_RADIANCE'));
        expect(source, isNot(contains('FLUTTER_SCENE_HOOK_')));
        // A declared but unwritten sample mask is 0 on Vulkan and WebGPU,
        // which drops every sample of the cutout's shadow and depth.
        expect(source, isNot(contains('material_coverage.glsl')));
      }
    }
  });

  test('a depth surface blanks the lighting hooks and keeps the lines', () {
    final material = compileFmat(
      _hookedCutout,
      fileName: 'hooked.fmat',
    ).material;
    final source = emitFragmentGlsl(
      material,
      depthSurface: DepthSurfaceKind.shadow,
    );
    expect(source, contains('void Surface(inout MaterialInputs material)'));
    for (final hook in ['LightTerms Light(', 'void Ambient(', 'Composite(']) {
      expect(source, isNot(contains(hook)), reason: hook);
    }
    final body = source.substring(
      source.indexOf('#line ${material.fragmentSourceLine}'),
    );
    final lines = '\n'.allMatches(material.fragmentSource).length;
    expect('\n'.allMatches(body).length, greaterThanOrEqualTo(lines));
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
      final hooked = compileFmat(_hookedCutout, fileName: 'hooked.fmat');
      final sources = {
        'color': emitFragmentGlsl(compiled.material),
        for (final kind in DepthSurfaceKind.values)
          kind.name: emitFragmentGlsl(compiled.material, depthSurface: kind),
        'hooked_color': emitFragmentGlsl(hooked.material),
        for (final kind in DepthSurfaceKind.values)
          'hooked_${kind.name}': emitFragmentGlsl(
            hooked.material,
            depthSurface: kind,
          ),
      };
      for (final MapEntry(key: variant, value: source) in sources.entries) {
        for (final MapEntry(key: backend, value: define) in _backends.entries) {
          final entry = 'cutout_$variant${backend.replaceAll('-', '_')}';
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
          if (backend == '--vulkan') {
            // Read from the SPIR-V that Vulkan and WebGPU consume; the Metal
            // output can drop an unwritten mask that the SPIR-V keeps.
            final spirv = File.fromUri(
              temp.uri.resolve('$entry.spirv'),
            ).readAsBytesSync();
            expect(
              declaresSampleMask(spirv),
              variant.endsWith('color'),
              reason: entry,
            );
          }
        }
      }
    } finally {
      temp.deleteSync(recursive: true);
    }
  });
}
