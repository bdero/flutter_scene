import 'dart:convert';
import 'dart:io';
import 'dart:ui' show Color;

import 'package:flutter_gpu_shaders/environment.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/fmat/build_materials.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/fmat/fmat.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
// ignore: implementation_imports
import 'package:flutter_scene/src/render/render_scene.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/render/shadow_catcher_bake_pass.dart';
import 'package:flutter_scene/scene.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

class _StubGeometry extends Geometry {
  @override
  void bind(
    gpu.RenderPass pass,
    TransientWriter transientsBuffer,
    Matrix4 modelTransform,
    Matrix4 cameraTransform,
    Vector3 cameraPosition, {
    gpu.Shader? shaderOverride,
    double depthBias = 0.0,
  }) {
    throw UnsupportedError('Stub geometry is not renderable');
  }
}

FmatCompilation _compileCatcher() {
  const path = 'assets/materials/shadow_catcher.fmat';
  return compileFmat(File(path).readAsStringSync(), fileName: path);
}

Future<Object?> _compileReflection(
  Uri impellerc,
  Directory temp,
  String entry,
  String source, {
  String stage = 'frag',
}) async {
  final input = File.fromUri(temp.uri.resolve('$entry.$stage'))
    ..writeAsStringSync(source);
  final reflection = File.fromUri(temp.uri.resolve('$entry.json'));
  final result = await Process.run(impellerc.toFilePath(), [
    '--opengl-es',
    '--input-type=$stage',
    '--input=${input.path}',
    '--sl=${temp.uri.resolve('$entry.glsl').toFilePath()}',
    '--spirv=${temp.uri.resolve('$entry.spirv').toFilePath()}',
    '--reflection-json=${reflection.path}',
    '--include=${Directory.current.uri.resolve('shaders/').toFilePath()}',
    '--include=${impellerc.resolve('./shader_lib').toFilePath()}',
    '--gles-language-version=300',
  ]);
  expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
  return jsonDecode(reflection.readAsStringSync());
}

Set<String> _samplerNames(Object? reflection) {
  final samplers =
      (reflection as Map<String, Object?>)['sampled_images'] as List<Object?>?;
  return {
    for (final sampler in samplers ?? const <Object?>[])
      (sampler as Map)['name'] as String,
  };
}

void main() {
  test('shadow catcher compiles two variants and no cube twins', () {
    final compiled = _compileCatcher();
    final variants = emitFragmentShaderVariants(
      compiled,
      generateShadowVariant: true,
    );

    expect(
      variants.keys,
      unorderedEquals({'ShadowCatcher', 'ShadowCatcherShadow'}),
    );
    // The generated main() outputs the composed overlay directly instead of
    // running the lighting.
    for (final glsl in variants.values) {
      expect(glsl, isNot(contains('EvaluateLighting(material)')));
      expect(
        glsl,
        contains(
          'frag_color = vec4(material.base_color.rgb, 1.0) * '
          'material.base_color.a;',
        ),
      );
    }
    // The vertex stage carries the local position for the radial fade.
    expect(
      compiled.vertexGlsl.keys,
      unorderedEquals({
        'ShadowCatcherUnskinnedVertex',
        'ShadowCatcherSkinnedVertex',
        'ShadowCatcherUnskinnedDepthVertex',
      }),
    );
  });

  test('shadow catcher metadata routes it through the translucent pass', () {
    final compiled = _compileCatcher();

    expect(compiled.sidecar['shading_model'], 'shadowCatcher');
    expect(compiled.sidecar['blending'], 'alpha');
    expect(compiled.sidecar['depth_write'], isNot(isTrue));
    expect(compiled.material.engineInputs, isEmpty);
  });

  test(
    'shadow catcher variants declare exactly the samplers bind expects',
    () async {
      final variants = emitFragmentShaderVariants(
        _compileCatcher(),
        generateShadowVariant: true,
      );
      final temp = Directory.systemTemp.createTempSync('shadow_catcher');
      try {
        final impellerc = await findImpellerC();
        // The shadow variant, drawn when a shadow atlas is bound, samples the
        // atlas, the occlusion chain, and the punctual textures the spot loop
        // reads. EngineLightingUniforms.bindShadowCatcherTextures binds exactly
        // this set; a drifted sampler set fails the draw at bind time.
        final shadow = await _compileReflection(
          impellerc,
          temp,
          'ShadowCatcherShadow',
          variants['ShadowCatcherShadow']!,
        );
        expect(
          _samplerNames(shadow),
          unorderedEquals({
            'shadow_map',
            'ssao_texture',
            'punctual_lights',
            'punctual_index',
            'baked_shadow_texture',
          }),
        );
        // The no-shadow variant compiles the whole shadow path out, leaving
        // the occlusion chain and the baked cache.
        final base = await _compileReflection(
          impellerc,
          temp,
          'ShadowCatcher',
          variants['ShadowCatcher']!,
        );
        expect(
          _samplerNames(base),
          unorderedEquals({'ssao_texture', 'baked_shadow_texture'}),
        );
      } finally {
        temp.deleteSync(recursive: true);
      }
    },
  );

  test('shadow catcher defaults match the documented contract', () {
    final material = ShadowCatcherMaterial();

    expect(material.shadowColor, const Color(0xFF000000));
    expect(material.shadowIntensity, 0.8);
    expect(material.aoStrength, 0.5);
    expect(material.softness, 0.0);
    expect(material.fadeStart, 0.0);
    expect(material.fadeEnd, 0.0);
    expect(material.mode, ShadowCatcherMode.baked);
    expect(material.isOpaque(), isFalse);
    expect(material.depthPrepassParticipates, isTrue);
    expect(material.drawsNothing, isFalse);
  });

  test('baked mode requests a bake exactly when a cache is stale', () {
    final material = ShadowCatcherMaterial();
    // Baked by default: the first rendered frame bakes the cache.
    expect(material.needsBakedShadowRefresh, isTrue);

    // A disabled catcher never bakes (it draws nothing at all).
    material.shadowIntensity = 0.0;
    expect(material.needsBakedShadowRefresh, isFalse);
    material.shadowIntensity = 0.8;

    // Live mode samples the atlas per fragment; no cache to refresh.
    material.mode = ShadowCatcherMode.live;
    expect(material.needsBakedShadowRefresh, isFalse);

    // Returning to baked mode re-bakes, as does the explicit dirty flag and
    // a softness change (the cache resolution rides softness).
    material.mode = ShadowCatcherMode.baked;
    expect(material.needsBakedShadowRefresh, isTrue);
    material.markBakedShadowsDirty();
    expect(material.needsBakedShadowRefresh, isTrue);
    material.softness = 0.3;
    expect(material.needsBakedShadowRefresh, isTrue);
  });

  test('bake resolution maps softness to a fixed blur span', () {
    // Softer shadows bake smaller: the 4-texel blur kernel spans the
    // softness, so resolution = footprint / softness * 4.
    expect(ShadowCatcherBakePass.bakeResolution(2.0, 0.1), 80);
    expect(ShadowCatcherBakePass.bakeResolution(2.0, 0.4), 20);
    // Softness 0 defers to the scene's atlas softness at a default size.
    expect(ShadowCatcherBakePass.bakeResolution(2.0, 0.0), 256);
    // Clamped so tiny or huge footprints stay reasonable.
    expect(ShadowCatcherBakePass.bakeResolution(100.0, 0.01), 1024);
    expect(ShadowCatcherBakePass.bakeResolution(0.1, 10.0), 16);
  });

  test('the scene registers a bake pass for stale baked catchers', () {
    final source = File('lib/src/scene.dart').readAsStringSync();

    expect(source, contains('needsBakedShadowRefresh'));
    expect(source, contains('ShadowCatcherBakePass'));
  });

  test('shadow catcher fmat defaults mirror the Dart defaults', () {
    final compiled = _compileCatcher();
    final defaults = {
      for (final p in compiled.material.uniformParameters)
        p.name: p.defaultValue,
    };

    expect(defaults['shadow_color'], [0, 0, 0]);
    expect(defaults['shadow_intensity'], 0.8);
    expect(defaults['ao_strength'], 0.5);
    expect(defaults['fade_start'], 0);
    expect(defaults['fade_end'], 0);
    expect(defaults['catcher_mode'], 0);
    // The baked cache sampler is the only material texture.
    expect(compiled.material.samplerParameters.map((p) => p.name), [
      'baked_shadow_texture',
    ]);
  });

  test('zero shadow intensity is a true early-out', () {
    final renderScene = RenderScene();
    final root = Node()..debugMountInto(renderScene);
    final catcher = ShadowCatcherMaterial(shadowIntensity: 0.0);
    root.add(Node(mesh: Mesh(_StubGeometry(), catcher)));

    root.scenePrePass(0);
    expect(catcher.drawsNothing, isTrue);
    // The item joins no pass at all: every encoder (color, depth prepass,
    // shadows) rejects invisible items before recording a draw.
    expect(renderScene.items.single.visible, isFalse);

    catcher.shadowIntensity = 0.4;
    root.scenePrePass(0);
    expect(renderScene.items.single.visible, isTrue);

    catcher.shadowIntensity = 0.0;
    root.scenePrePass(0);
    expect(renderScene.items.single.visible, isFalse);
  });

  test('depth prepass selects items through depthPrepassParticipates', () {
    // The screen-space occlusion chain only knows surfaces in the depth
    // prepass. The catcher is translucent, so without this opt-in its AO
    // term would silently read the backdrop's depth (zero occlusion).
    final source = File('lib/src/render/depth_prepass.dart').readAsStringSync();

    expect(source, contains('depthPrepassParticipates'));
    expect(ShadowCatcherMaterial().depthPrepassParticipates, isTrue);
    expect(UnlitMaterial().depthPrepassParticipates, isTrue);
    expect(
      (PhysicallyBasedMaterial()..alphaMode = AlphaMode.blend)
          .depthPrepassParticipates,
      isFalse,
    );
  });

  test('alpha composition follows the documented formula', () {
    // alpha = saturate(intensity * (1 - visibility) + ao * (1 - occlusion))
    //         * radial fade.
    expect(
      ShadowCatcherMaterial.composeAlpha(
        shadowVisibility: 0.0,
        occlusion: 1.0,
        shadowIntensity: 0.8,
        aoStrength: 0.5,
      ),
      closeTo(0.8, 1e-9),
    );
    expect(
      ShadowCatcherMaterial.composeAlpha(
        shadowVisibility: 1.0,
        occlusion: 0.5,
        shadowIntensity: 0.8,
        aoStrength: 0.5,
      ),
      closeTo(0.25, 1e-9),
    );
    // The sum saturates before the fade applies.
    expect(
      ShadowCatcherMaterial.composeAlpha(
        shadowVisibility: 0.0,
        occlusion: 0.0,
        shadowIntensity: 1.0,
        aoStrength: 1.0,
      ),
      1.0,
    );
    // Radial fade: full inside fadeStart, zero at fadeEnd, smooth between.
    expect(
      ShadowCatcherMaterial.composeAlpha(
        shadowVisibility: 0.0,
        occlusion: 1.0,
        shadowIntensity: 1.0,
        aoStrength: 0.0,
        radialDistance: 0.2,
        fadeStart: 0.5,
        fadeEnd: 1.0,
      ),
      1.0,
    );
    expect(
      ShadowCatcherMaterial.composeAlpha(
        shadowVisibility: 0.0,
        occlusion: 1.0,
        shadowIntensity: 1.0,
        aoStrength: 0.0,
        radialDistance: 1.0,
        fadeStart: 0.5,
        fadeEnd: 1.0,
      ),
      0.0,
    );
    expect(
      ShadowCatcherMaterial.composeAlpha(
        shadowVisibility: 0.0,
        occlusion: 1.0,
        shadowIntensity: 1.0,
        aoStrength: 0.0,
        radialDistance: 0.75,
        fadeStart: 0.5,
        fadeEnd: 1.0,
      ),
      closeTo(0.5, 1e-9),
    );
    // fadeEnd at or below fadeStart leaves the fade off.
    expect(
      ShadowCatcherMaterial.composeAlpha(
        shadowVisibility: 0.5,
        occlusion: 1.0,
        shadowIntensity: 1.0,
        aoStrength: 0.0,
        radialDistance: 100.0,
      ),
      closeTo(0.5, 1e-9),
    );
  });
}
