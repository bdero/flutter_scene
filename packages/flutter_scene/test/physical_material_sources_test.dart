import 'dart:convert';
import 'dart:io';

import 'package:flutter_gpu_shaders/environment.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/fmat/build_materials.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/fmat/fmat.dart';
import 'package:flutter_test/flutter_test.dart';

FmatCompilation _compile(String name) {
  final path = 'assets/materials/$name.fmat';
  return compileFmat(File(path).readAsStringSync(), fileName: path);
}

bool _hasNamedResource(Object? value, String name) {
  if (value is Map) {
    if (value['name'] == name) return true;
    return value.values.any((entry) => _hasNamedResource(entry, name));
  }
  if (value is List) {
    return value.any((entry) => _hasNamedResource(entry, name));
  }
  return false;
}

/// The backends a lit variant has to compile for.
const _backends = ['--opengl-es', '--metal-desktop', '--vulkan'];

Future<Object?> _compileReflection(
  Uri impellerc,
  Directory temp,
  String entry,
  String source, {
  String backend = '--opengl-es',
}) async {
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
  expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
  return jsonDecode(reflection.readAsStringSync());
}

Future<Object?> _compileVertexReflection(
  Uri impellerc,
  Directory temp,
  String entry,
  String source, {
  String backend = '--opengl-es',
}) async {
  final input = File.fromUri(temp.uri.resolve('$entry.vert'))
    ..writeAsStringSync(source);
  final reflection = File.fromUri(temp.uri.resolve('$entry.json'));
  final result = await Process.run(impellerc.toFilePath(), [
    backend,
    '--input-type=vert',
    '--input=${input.path}',
    '--sl=${temp.uri.resolve('$entry.out').toFilePath()}',
    '--spirv=${temp.uri.resolve('$entry.spirv').toFilePath()}',
    '--reflection-json=${reflection.path}',
    '--include=${Directory.current.uri.resolve('shaders/').toFilePath()}',
    '--include=${impellerc.resolve('./shader_lib').toFilePath()}',
    if (backend == '--opengl-es') '--gles-language-version=300',
  ]);
  expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
  return jsonDecode(reflection.readAsStringSync());
}

void main() {
  test('materials guard their shadow sampler layout', () {
    final manifest =
        jsonDecode(File('shaders/base.shaderbundle.json').readAsStringSync())
            as Map<String, dynamic>;
    final sampling = File(
      'shaders/material_shadow_sampling.glsl',
    ).readAsStringSync();
    final uniforms = File(
      'shaders/material_engine_lighting.glsl',
    ).readAsStringSync();

    expect(
      manifest['StandardFragment']['file'],
      'shaders/flutter_scene_standard.frag',
    );
    expect(sampling, contains('#ifndef FLUTTER_SCENE_SKIP_SHADOWS'));
    expect(
      uniforms,
      contains(
        '#ifndef FLUTTER_SCENE_SKIP_SHADOWS\n'
        'uniform sampler2D shadow_map;\n'
        '#endif',
      ),
    );
  });

  test('physical materials compile matching shadow sampler layouts', () async {
    final compiled = _compile('physical_opaque');
    final variants = emitFragmentShaderVariants(
      compiled,
      generateShadowVariant: true,
    );
    expect(
      variants.keys,
      unorderedEquals({
        'PhysicalOpaque',
        'PhysicalOpaqueShadow',
        'PhysicalOpaqueCube',
        'PhysicalOpaqueShadowCube',
      }),
    );
    final temp = Directory.systemTemp.createTempSync('physical_variants');
    try {
      final impellerc = await findImpellerC();
      final base = await _compileReflection(
        impellerc,
        temp,
        'PhysicalOpaque',
        variants['PhysicalOpaque']!,
      );
      final shadow = await _compileReflection(
        impellerc,
        temp,
        'PhysicalOpaqueShadow',
        variants['PhysicalOpaqueShadow']!,
      );
      expect(_hasNamedResource(base, 'shadow_map'), isFalse);
      expect(_hasNamedResource(shadow, 'shadow_map'), isTrue);
    } finally {
      temp.deleteSync(recursive: true);
    }
  });

  // The GLES backend allocates fragment texture units after the vertex
  // stage's, from one combined pool with an ES 3.0 minimum of 16. The
  // fragment cap of 15 leaves room for a skinned draw's joints_texture; the
  // worst pairing the engine makes is a lit morphed skinned draw (2 vertex
  // samplers, 17 combined), pinned with its justification by the vertex
  // pairing test below. Engines older than the combined-limit fix reject an
  // over-budget draw outright, so every lit variant has to fit.
  //
  // Raising this needs the engine fix in every supported stable; see the
  // TODO(radiance-layout) in shaders/texture.glsl. Until then, a new engine
  // sampler has to displace an existing one rather than extend the set.
  const maxFragmentSamplers = 15;

  test('lit material variants fit the fragment texture-unit budget', () async {
    final temp = Directory.systemTemp.createTempSync('sampler_budget');
    try {
      final impellerc = await findImpellerC();
      var worst = 0;
      for (final name in [
        'physical_opaque',
        'physical_transmission',
        'shadow_catcher',
      ]) {
        final variants = emitFragmentShaderVariants(
          _compile(name),
          generateShadowVariant: true,
          generateLightmapVariant: name == 'physical_opaque',
        );
        for (final variant in variants.entries) {
          final reflection =
              await _compileReflection(
                    impellerc,
                    temp,
                    variant.key,
                    variant.value,
                  )
                  as Map<String, Object?>;
          final samplers = reflection['sampled_images']! as List<Object?>;
          expect(
            samplers,
            hasLength(lessThanOrEqualTo(maxFragmentSamplers)),
            reason:
                '${variant.key} declares ${samplers.length} fragment '
                'samplers, over the $maxFragmentSamplers budget.',
          );
          // The world-space irradiance field extends the environment's
          // coefficient texture downward rather than declaring a sampler of
          // its own, so every lit variant still reads exactly one of them.
          if (name != 'shadow_catcher' && !variant.key.contains('Lightmap')) {
            expect(
              _hasNamedResource(reflection, 'irradiance_field'),
              isTrue,
              reason: '${variant.key} lost the irradiance-field sampler.',
            );
          }
          if (samplers.length > worst) worst = samplers.length;
        }
      }
      // Pinned so a new engine sampler shows up as a failure here rather than
      // as a rejected skinned draw on a minimum-spec driver. The irradiance
      // field left this untouched because it rides the coefficient texture.
      expect(worst, 14);
    } finally {
      temp.deleteSync(recursive: true);
    }
  });

  // GLES exposes one combined pool of texture units, vertex stage first, and
  // the ES 3.0 minimum is 16 total. The fragment cap above only holds the
  // real invariant when the vertex-stage counts are pinned too, so this
  // asserts them, and the combined total for every pairing the engine makes.
  // A sampler added to either stage moves a number here and fails loudly.
  //
  // The one pairing over the 16-unit minimum is a lit morphed skinned draw
  // at 17, accepted deliberately because real GLES3 hardware reports 32 or
  // more units; see TODO(morph-sampler-budget) in morphed_geometry.dart for
  // the escape (joints and morph deltas sharing one vertex texture).
  test('vertex sampler counts pin the combined pairing budget', () async {
    final temp = Directory.systemTemp.createTempSync('vertex_sampler_budget');
    try {
      final impellerc = await findImpellerC();
      const expectedVertexSamplers = {
        'UnskinnedVertex': 0,
        'SkinnedVertex': 1,
        'MorphedUnskinnedVertex': 1,
        'MorphedSkinnedVertex': 2,
      };
      const expectedCombined = {
        'UnskinnedVertex': 15,
        'SkinnedVertex': 16,
        'MorphedUnskinnedVertex': 16,
        'MorphedSkinnedVertex': 17,
      };
      final manifest =
          jsonDecode(File('shaders/base.shaderbundle.json').readAsStringSync())
              as Map<String, dynamic>;
      for (final entry in expectedVertexSamplers.entries) {
        final file = (manifest[entry.key] as Map)['file'] as String;
        final reflection =
            await _compileVertexReflection(
                  impellerc,
                  temp,
                  entry.key,
                  File(file).readAsStringSync(),
                )
                as Map<String, Object?>;
        final samplers =
            reflection['sampled_images'] as List<Object?>? ?? const [];
        expect(
          samplers,
          hasLength(entry.value),
          reason:
              '${entry.key} declares ${samplers.length} vertex samplers, '
              'expected ${entry.value}; the combined pairing table below '
              'reasons from these counts.',
        );
        expect(
          maxFragmentSamplers + entry.value,
          expectedCombined[entry.key],
          reason:
              'the worst lit pairing for ${entry.key} changed; update the '
              'table and re-justify it against the 16-unit ES 3.0 minimum.',
        );
      }
    } finally {
      temp.deleteSync(recursive: true);
    }
  });

  test('base lit shaders fit the fragment texture-unit budget', () async {
    final temp = Directory.systemTemp.createTempSync('base_sampler_budget');
    try {
      final impellerc = await findImpellerC();
      for (final entry in [
        'flutter_scene_standard',
        'flutter_scene_standard_cube',
        'flutter_scene_standard_lightmap',
        'flutter_scene_standard_lightmap_cube',
        'flutter_scene_standard_no_shadow',
        'flutter_scene_standard_no_shadow_cube',
        'flutter_scene_standard_lightmap_no_shadow',
        'flutter_scene_standard_lightmap_no_shadow_cube',
      ]) {
        final reflection =
            await _compileReflection(
                  impellerc,
                  temp,
                  entry,
                  File('shaders/$entry.frag').readAsStringSync(),
                )
                as Map<String, Object?>;
        final samplers = reflection['sampled_images']! as List<Object?>;
        expect(
          samplers,
          hasLength(lessThanOrEqualTo(maxFragmentSamplers)),
          reason:
              '$entry declares ${samplers.length} fragment samplers, over '
              'the $maxFragmentSamplers budget.',
        );
      }
    } finally {
      temp.deleteSync(recursive: true);
    }
  });

  test('the baked lightmap ships as a define-gated variant axis', () {
    final compiled = _compile('physical_opaque');
    final plain = emitFragmentShaderVariants(
      compiled,
      generateShadowVariant: true,
    );
    final withLightmap = emitFragmentShaderVariants(
      compiled,
      generateShadowVariant: true,
      generateLightmapVariant: true,
    );

    expect(
      withLightmap.keys,
      unorderedEquals({
        'PhysicalOpaque',
        'PhysicalOpaqueShadow',
        'PhysicalOpaqueCube',
        'PhysicalOpaqueShadowCube',
        'PhysicalOpaqueLightmap',
        'PhysicalOpaqueLightmapShadow',
        'PhysicalOpaqueLightmapCube',
        'PhysicalOpaqueLightmapShadowCube',
      }),
    );
    // The axis adds entries; it does not disturb the ones already shipping.
    plain.forEach((entry, glsl) {
      expect(withLightmap[entry], glsl, reason: '$entry changed');
    });
    withLightmap.forEach((entry, glsl) {
      expect(
        glsl.contains('#define FLUTTER_SCENE_LIGHTMAP'),
        entry.contains('Lightmap'),
        reason: '$entry should define the lightmap only when named Lightmap.',
      );
    });
    // The transmission material is deliberately left off the axis; see the
    // TODO(lightmap-transmission) in buildBundledPhysicalMaterials.
    expect(
      emitFragmentShaderVariants(
        _compile('physical_transmission'),
        generateShadowVariant: true,
      ).keys,
      hasLength(4),
    );
  });

  test('a bound lightmap displaces the SH diffuse ambient', () {
    final lightmap = File('shaders/lightmap.glsl').readAsStringSync();
    final uniforms = File(
      'shaders/material_engine_lighting.glsl',
    ).readAsStringSync();
    final lighting = File('shaders/material_lighting.glsl').readAsStringSync();

    // The sampler takes the texture unit irradiance_field gives up, so a
    // lightmap entry costs no more than its plain twin.
    expect(
      uniforms,
      contains(
        '#ifndef FLUTTER_SCENE_LIGHTMAP\n'
        'uniform highp sampler2D irradiance_field;\n'
        '#endif',
      ),
    );
    expect(lightmap, contains('uniform sampler2D lightmap_texture;'));
    expect(lightmap, contains('uniform LightmapInfo {'));
    expect(lightmap, contains('vec3 BakedDiffuseRadiance() {'));
    // RGBM decode is a uniform-driven branch, not a second define axis.
    expect(lightmap, contains('baked.rgb * pow(baked.a, 2.2) * 34.4932'));
    expect(lightmap, contains('lightmap_info.rotation.w > 0.5'));
    expect(lightmap, isNot(contains('#define FLUTTER_SCENE_LIGHTMAP_RGBM')));
    expect(lighting, contains('vec3 irradiance = BakedDiffuseRadiance();'));
  });

  test('lightmap variants trade sh_coefficients for the lightmap', () async {
    final temp = Directory.systemTemp.createTempSync('lightmap_samplers');
    try {
      final impellerc = await findImpellerC();
      final variants = emitFragmentShaderVariants(
        _compile('physical_opaque'),
        generateShadowVariant: true,
        generateLightmapVariant: true,
      );
      final entries = <String, String>{
        ...variants,
        'flutter_scene_standard': File(
          'shaders/flutter_scene_standard.frag',
        ).readAsStringSync(),
        'flutter_scene_standard_lightmap': File(
          'shaders/flutter_scene_standard_lightmap.frag',
        ).readAsStringSync(),
        'flutter_scene_standard_lightmap_cube': File(
          'shaders/flutter_scene_standard_lightmap_cube.frag',
        ).readAsStringSync(),
      };
      for (final backend in _backends) {
        for (final entry in entries.entries) {
          final lit = entry.key.toLowerCase().contains('lightmap');
          final reflection =
              await _compileReflection(
                    impellerc,
                    temp,
                    entry.key,
                    entry.value,
                    backend: backend,
                  )
                  as Map<String, Object?>;
          final samplers = reflection['sampled_images']! as List<Object?>;
          expect(
            samplers,
            hasLength(lessThanOrEqualTo(maxFragmentSamplers)),
            reason:
                '${entry.key} on $backend declares ${samplers.length} '
                'fragment samplers, over the $maxFragmentSamplers budget.',
          );
          expect(
            _hasNamedResource(reflection, 'lightmap_texture'),
            lit,
            reason: '${entry.key} on $backend',
          );
          expect(
            _hasNamedResource(reflection, 'irradiance_field'),
            !lit,
            reason: '${entry.key} on $backend',
          );
        }
      }
    } finally {
      temp.deleteSync(recursive: true);
    }
  }, timeout: const Timeout(Duration(minutes: 10)));

  test('the base bundle ships the lightmap standard entries', () {
    final manifest =
        jsonDecode(File('shaders/base.shaderbundle.json').readAsStringSync())
            as Map<String, dynamic>;

    expect(
      manifest['StandardLightmapFragment']['file'],
      'shaders/flutter_scene_standard_lightmap.frag',
    );
    expect(
      manifest['StandardLightmapCubeFragment']['file'],
      'shaders/flutter_scene_standard_lightmap_cube.frag',
    );
    for (final entry in [
      'flutter_scene_standard_lightmap',
      'flutter_scene_standard_lightmap_cube',
    ]) {
      final source = File('shaders/$entry.frag').readAsStringSync();
      expect(source, contains('#define FLUTTER_SCENE_LIGHTMAP'));
      expect(source, contains('#include <flutter_scene_standard.frag>'));
    }
  });

  test('the base bundle ships the no-shadow standard entries', () async {
    final manifest =
        jsonDecode(File('shaders/base.shaderbundle.json').readAsStringSync())
            as Map<String, dynamic>;

    const entries = {
      'StandardNoShadowFragment': 'flutter_scene_standard_no_shadow',
      'StandardNoShadowCubeFragment': 'flutter_scene_standard_no_shadow_cube',
      'StandardLightmapNoShadowFragment':
          'flutter_scene_standard_lightmap_no_shadow',
      'StandardLightmapNoShadowCubeFragment':
          'flutter_scene_standard_lightmap_no_shadow_cube',
    };
    entries.forEach((entry, file) {
      expect(manifest[entry]['file'], 'shaders/$file.frag');
      final source = File('shaders/$file.frag').readAsStringSync();
      expect(source, contains('#define FLUTTER_SCENE_SKIP_SHADOWS'));
      expect(source, contains('#include <flutter_scene_standard.frag>'));
    });

    // The twin exists to drop the shadow sampling; the full entry keeps it.
    final temp = Directory.systemTemp.createTempSync('standard_no_shadow');
    try {
      final impellerc = await findImpellerC();
      final full =
          await _compileReflection(
                impellerc,
                temp,
                'StandardFragment',
                File('shaders/flutter_scene_standard.frag').readAsStringSync(),
              )
              as Map<String, Object?>;
      final slim =
          await _compileReflection(
                impellerc,
                temp,
                'StandardNoShadowFragment',
                File(
                  'shaders/flutter_scene_standard_no_shadow.frag',
                ).readAsStringSync(),
              )
              as Map<String, Object?>;
      expect(_hasNamedResource(full, 'shadow_map'), isTrue);
      expect(_hasNamedResource(slim, 'shadow_map'), isFalse);
      // The twins must stay bind-compatible outside the shadow atlas: the
      // punctual light textures survive the define, so a shadow-less scene
      // still shades its point and spot lights.
      expect(_hasNamedResource(slim, 'punctual_lights'), isTrue);
      expect(_hasNamedResource(slim, 'punctual_index'), isTrue);
    } finally {
      temp.deleteSync(recursive: true);
    }
  });

  test('lit variants select their radiance layout by define', () {
    final variants = emitFragmentShaderVariants(
      _compile('physical_opaque'),
      generateShadowVariant: true,
    );
    variants.forEach((entry, glsl) {
      expect(
        glsl.contains('#define FLUTTER_SCENE_RADIANCE_CUBE'),
        entry.endsWith('Cube'),
        reason: '$entry should define the cube layout only when named Cube.',
      );
    });
    // One sampler, whose type the define picks, so the layout the backend
    // does not build costs no texture unit.
    final lighting = File(
      'shaders/material_engine_lighting.glsl',
    ).readAsStringSync();
    expect(lighting, contains('uniform RadianceSampler prefiltered_radiance;'));
    expect(
      lighting,
      contains('uniform RadianceSampler prefiltered_radiance_b;'),
    );
    expect(lighting, isNot(contains('prefiltered_radiance_cube')));
  });

  test('the standard path takes its dielectric F0 from FragInfo', () {
    final lighting = File('shaders/material_lighting.glsl').readAsStringSync();
    final uniforms = File(
      'shaders/material_scene_inputs.glsl',
    ).readAsStringSync();
    // The physical path still derives its own from the material inputs; the
    // standard path reads the CPU-packed product, so scalar ior and specular
    // no longer force the physical variant.
    expect(uniforms, contains('vec4 dielectric_f0;'));
    expect(lighting, contains('frag_info.dielectric_f0.xyz'));
    expect(
      lighting,
      contains('material.specular_color * material.specular_weight'),
    );
    expect(
      lighting,
      isNot(contains('vec3 dielectric_reflectance = vec3(0.04);')),
    );
  });

  test('lit materials reverse normals on back-facing fragments', () {
    final varyings = File('shaders/material_varyings.glsl').readAsStringSync();
    final standard = File(
      'shaders/flutter_scene_standard.frag',
    ).readAsStringSync();

    expect(varyings, contains('gl_FrontFacing ? 1.0 : -1.0'));
    expect(standard, contains('vec3 normal = GetWorldNormal();'));
    expect(standard, isNot(contains('vec3 normal = normalize(v_normal);')));
  });

  test('transmissive physical materials keep back-face culling', () {
    final source = File(
      'lib/src/material/preprocessed_material.dart',
    ).readAsStringSync();

    expect(source, contains('pass.setCullMode(renderCullMode);'));
    expect(
      source,
      isNot(contains('doubleSided ? gpu.CullMode.none : renderCullMode')),
    );
  });

  test('physical feature textures preserve high-impact inputs first', () {
    final source = File(
      'lib/src/material/physical_material_variant.dart',
    ).readAsStringSync();
    final emissive = source.indexOf('(1, d.emissiveTexture)');
    final occlusion = source.indexOf('(2, d.occlusionTexture)');
    final specular = source.indexOf('(3, d.specularTexture)');

    expect(emissive, greaterThan(0));
    expect(occlusion, greaterThan(emissive));
    expect(specular, greaterThan(occlusion));
    expect(source, contains('math.max(d.attenuationDistance, 0.0001)'));
  });

  test('opaque physical shader exposes advanced properties', () {
    final compiled = _compile('physical_opaque');
    final names = compiled.material.parameters.map((p) => p.name).toSet();

    expect(compiled.glsl, contains('#define FLUTTER_SCENE_PHYSICAL_MATERIAL'));
    expect(compiled.material.samplerParameters, hasLength(6));
    expect(
      names,
      containsAll(<String>{
        'anisotropy',
        'clearcoat',
        'diffuse_transmission',
        'ior',
        'iridescence',
        'sheen_color',
        'specular_factor',
      }),
    );
    expect(
      compiled.glsl,
      contains('material.clearcoat_normal = GetWorldNormal();'),
    );
    expect(
      compiled.glsl,
      isNot(contains('material.clearcoat_normal = material.normal;')),
    );
  });

  test('transmission shader requests optional scene inputs', () {
    final compiled = _compile('physical_transmission');

    expect(compiled.material.samplerParameters, hasLength(5));
    expect(compiled.material.engineInputs, [
      'scene_color',
      'filtered_scene_color',
    ]);
    expect(compiled.material.depthWrite, isTrue);
    expect(compiled.sidecar['depth_write'], isTrue);
    expect(compiled.glsl, contains('GetSceneColorFiltered'));
    expect(compiled.glsl, contains('#define FLUTTER_SCENE_SKIP_SSAO'));
    expect(compiled.glsl, isNot(contains('uniform sampler2D ssao_texture;')));
    // The scene-color sampler and its accessors compile in through the shared
    // include, on the define the emitter writes for a declared input.
    expect(compiled.glsl, contains('#define FLUTTER_SCENE_SCENE_COLOR'));
    expect(
      File('shaders/material_scene_inputs.glsl').readAsStringSync(),
      contains('frag_info.scene_inputs.x < 0.5) return vec3(0.0)'),
    );
    expect(compiled.glsl, contains('texture(emissive_texture'));
    expect(compiled.glsl, contains('#include <filtered_scene_color.glsl>'));
    expect(compiled.glsl, contains('refract(-GetViewDirection()'));
    expect(compiled.glsl, contains('ProjectWorldOffsetToScreenUv'));
    expect(compiled.glsl, contains('thickness * GetModelScale()'));
    expect(
      compiled.glsl,
      contains('length(ray_r), length(ray_g), length(ray_b)'),
    );
  });

  test('physical texture slots select their declared UV channel', () {
    final opaque = _compile('physical_opaque');
    final transmission = _compile('physical_transmission');

    expect(opaque.glsl, contains('GetUV(material_params.feature_a_uv_set)'));
    expect(opaque.glsl, contains('GetUV(material_params.base_color_uv_set)'));
    expect(
      transmission.glsl,
      contains('GetUV(material_params.transmission_data_uv_set)'),
    );
  });

  test('material texture transforms share channel selection and UV math', () {
    final inputs = File('shaders/material_inputs.glsl').readAsStringSync();
    final standard = File(
      'shaders/flutter_scene_standard.frag',
    ).readAsStringSync();
    final unlit = File('shaders/flutter_scene_unlit.frag').readAsStringSync();
    final depthNormal = File(
      'shaders/flutter_scene_linear_depth_normal.frag',
    ).readAsStringSync();

    expect(inputs, contains('vec2 MaterialTextureUv('));
    expect(inputs, contains('int(rotation.z + 0.5)'));
    expect(standard, contains('MaterialTextureUv('));
    expect(unlit, contains('MaterialTextureUv('));
    expect(depthNormal, contains('MaterialTextureUv('));
    expect(standard, isNot(contains('vec2 TransformUv(')));
    // The standard shader skips all five UV-transform evaluations behind one
    // uniform flag carried in the base record's padding float, set by the
    // material when any record transforms its UVs or selects UV set 1.
    expect(
      standard,
      contains('texture_transforms.base_color_rotation.w > 0.5'),
    );
  });

  test('filtered scene color lives in a reviewable shader include', () {
    final filtered = File(
      'shaders/filtered_scene_color.glsl',
    ).readAsStringSync();

    expect(filtered, contains('uniform sampler2D scene_filtered_color;'));
    expect(filtered, contains('vec3 SampleTransmissionBand('));
    expect(filtered, contains('vec3 GetSceneColorFiltered('));
    expect(filtered, contains('TransmissionWeight0'));
    expect(filtered, contains('roughness * clamp(ior * 2.0 - 2.0'));
  });

  test('shared lighting composes clearcoat after the underlying material', () {
    final source = File('shaders/material_lighting.glsl').readAsStringSync();
    final pbr = File('shaders/pbr.glsl').readAsStringSync();
    final transmission = source.indexOf(
      'out_color += transmitted_light * specular_transmission',
    );
    final coatComposition = source.indexOf(
      'out_color = out_color * (1.0 - coat_weight * coat_fresnel)',
    );

    expect(source, contains('EvaluateClearcoatLight'));
    expect(source, contains('SpecularAARoughness(\n      coat_normal'));
    expect(source, contains('vec3(0.04) * coat_ab.x + coat_ab.y'));
    expect(source, contains('material.transmission_color * albedo *'));
    expect(
      source,
      isNot(contains('material.diffuse_transmission_color * albedo *')),
    );
    expect(
      source,
      contains('(1.0 - 0.5 * material.sheen_roughness) * occlusion *'),
    );
    expect(source, contains('return roughness;'));
    expect(source, contains('max(material.sheen_roughness, kMinRoughness)'));
    expect(pbr, contains('kMinRoughness * kMinRoughness'));
    expect(
      source,
      isNot(contains('mix(out_color, material.transmission_color')),
    );
    expect(transmission, greaterThan(0));
    expect(coatComposition, greaterThan(transmission));
  });

  test('cascade cross-fade collapses to the hard hand-off at zero', () {
    // The cascade sampling lives in the shared shadow-sampling include so the
    // shadow catcher can use it without the lighting framework.
    final lighting = File(
      'shaders/material_shadow_sampling.glsl',
    ).readAsStringSync();
    final uniforms = File(
      'shaders/material_scene_inputs.glsl',
    ).readAsStringSync();

    // The overlap rides an already-declared slot, so no uniform or sampler is
    // added, and it is packed as a fraction the shader halves into UV space.
    expect(uniforms, contains('vec4 directional_light_color;'));
    expect(lighting, contains('frag_info.directional_light_color.w * 0.5'));

    // A zero band selects the constant 1.0, so the first containing cascade
    // takes the whole weight and the rest are skipped; the leftover weight
    // reads as lit. Together these make zero overlap exactly today's path.
    expect(lighting, contains('return band > 0.0 ? ramp.x * ramp.y : 1.0;'));
    expect(lighting, contains('min(CascadeBlendWeight(uv, margin, band),'));
    expect(lighting, contains('return shadow_sum + (1.0 - weight);'));
    // The weight guard replaces the old `found` flag, so a full cascade ends
    // the walk instead of a second lookup.
    expect(lighting, contains('if (weight < 1.0 && count > IDX)'));
    // An early return inside the blend would emit a loop here (see the
    // Direct3D note on SampleShadow), so the helper must stay a select.
    expect(lighting, isNot(contains('if (band <= 0.0) return')));
  });

  test('anisotropy affects analytic and image-based lighting', () {
    final pbr = File('shaders/pbr.glsl').readAsStringSync();
    final lighting = File('shaders/material_lighting.glsl').readAsStringSync();
    final normals = File('shaders/normals.glsl').readAsStringSync();

    expect(pbr, contains('float VisibilityGGXAnisotropic'));
    expect(
      lighting,
      contains('float alpha_t = mix(alpha_b, 1.0, anisotropy * anisotropy);'),
    );
    expect(lighting, contains('visibility = VisibilityGGXAnisotropic('));
    expect(
      lighting,
      contains('float bend = 1.0 - anisotropy * (1.0 - roughness);'),
    );
    expect(
      lighting,
      contains('mix(reflection_normal, bent_normal, roughness * roughness)'),
    );
    expect(lighting, contains('material.anisotropy_uv'));
    expect(lighting, contains('mat3 tangent_frame = TangentFrame('));
    expect(normals, contains('vec4 authored = GetWorldTangent();'));
    expect(
      normals,
      contains('return CotangentFrame(normal, view_vector, uv);'),
    );
  });

  test('vertex bodies carry normals by the inverse-transpose', () {
    final helper = File('shaders/normal_transform.glsl').readAsStringSync();
    final unskinned = File(
      'shaders/flutter_scene_unskinned_body.glsl',
    ).readAsStringSync();
    final skinned = File(
      'shaders/flutter_scene_skinned_body.glsl',
    ).readAsStringSync();

    // mat3(model) is the inverse-transpose only for rotation, uniform scale,
    // and reflection, so both bodies have to route the normal through the
    // helper or a non-uniformly scaled node lights like the wrong shape.
    for (final body in [unskinned, skinned]) {
      expect(body, contains('#include <normal_transform.glsl>'));
      expect(body, contains('WorldNormalMatrix('));
      expect(
        body.contains('world_normal = mat3(model_transform) * in_normal'),
        isFalse,
      );
    }
    // Positions and tangents still transform by the model matrix.
    expect(unskinned, contains('mat3(model_transform) * tangent.xyz'));
    expect(skinned, contains('mat3(combined_transform) * tangent.xyz'));

    // Cofactors, not transpose(inverse(M)): the two differ by the determinant,
    // whose magnitude the later normalize removes and whose sign the helper
    // applies, so this spelling needs no division and no inverse() (which
    // GLSL ES 1.00 lacks).
    expect(helper, contains('cross(linear[1], linear[2])'));
    expect(helper, contains('cofactor * sign(det)'));
    final body = helper
        .split('\n')
        .where((line) => !line.trimLeft().startsWith('//'))
        .join('\n');
    expect(body.contains('inverse('), isFalse);
    expect(body.contains('transpose('), isFalse);
    // The singular test compares against zero, not an epsilon. A determinant
    // scales as the cube of the model's scale, so a fixed threshold would
    // reject a legitimately small model and hand back the wrong normal.
    expect(helper, contains('if (det == 0.0)'));
  });
}
