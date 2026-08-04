import 'dart:io';

// ignore: implementation_imports
import 'package:flutter_scene/src/fmat/fmat.dart';
import 'package:flutter_test/flutter_test.dart';

FmatCompilation _compile(String name) {
  final path = 'assets/materials/$name.fmat';
  return compileFmat(File(path).readAsStringSync(), fileName: path);
}

void main() {
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
      'lib/src/material/advanced_physical_material.dart',
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
    expect(compiled.glsl, contains('SampleTransmissionBand'));
    expect(compiled.glsl, contains('roughness * clamp(ior * 2.0 - 2.0'));
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

  test('shared lighting composes clearcoat after the underlying material', () {
    final source = File('shaders/material_lighting.glsl').readAsStringSync();
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
    expect(
      source,
      isNot(contains('mix(out_color, material.transmission_color')),
    );
    expect(transmission, greaterThan(0));
    expect(coatComposition, greaterThan(transmission));
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
