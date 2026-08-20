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

Future<Object?> _compileReflection(
  Uri impellerc,
  Directory temp,
  String entry,
  String source,
) async {
  final input = File.fromUri(temp.uri.resolve('$entry.frag'))
    ..writeAsStringSync(source);
  final reflection = File.fromUri(temp.uri.resolve('$entry.json'));
  final result = await Process.run(impellerc.toFilePath(), [
    '--opengl-es',
    '--input-type=frag',
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

void main() {
  test('materials guard their shadow sampler layout', () {
    final manifest =
        jsonDecode(File('shaders/base.shaderbundle.json').readAsStringSync())
            as Map<String, dynamic>;
    final lighting = File('shaders/material_lighting.glsl').readAsStringSync();
    final uniforms = File(
      'shaders/material_engine_lighting.glsl',
    ).readAsStringSync();

    expect(
      manifest['StandardFragment']['file'],
      'shaders/flutter_scene_standard.frag',
    );
    expect(lighting, contains('#ifndef FLUTTER_SCENE_SKIP_SHADOWS'));
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
  // stage's, so a skinned draw (which spends one on joints_texture) leaves 15
  // for the fragment stage on a driver reporting the ES 3.0 minimum of 16.
  // Engines older than the combined-limit fix reject the draw outright, so
  // every lit variant has to fit.
  //
  // Raising this needs the engine fix in every supported stable; see the
  // TODO(radiance-layout) in shaders/texture.glsl. Until then, a new engine
  // sampler has to displace an existing one rather than extend the set.
  const maxFragmentSamplers = 15;

  test('lit material variants fit the fragment texture-unit budget', () async {
    final temp = Directory.systemTemp.createTempSync('sampler_budget');
    try {
      final impellerc = await findImpellerC();
      for (final name in ['physical_opaque', 'physical_transmission']) {
        final variants = emitFragmentShaderVariants(
          _compile(name),
          generateShadowVariant: true,
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
        }
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
    expect(
      compiled.glsl,
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
    final lighting = File('shaders/material_lighting.glsl').readAsStringSync();
    final uniforms = File(
      'shaders/material_engine_lighting.glsl',
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
}
