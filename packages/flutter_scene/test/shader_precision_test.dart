// Material fragment sources default to mediump and opt the world-space,
// coordinate, and depth data back into highp (shaders/PRECISION.md). These
// checks keep the header and the highp declarations from regressing, since
// no CI backend runs fp16 and a lost qualifier only shows on a phone.

import 'dart:io';

import 'package:flutter_scene/src/fmat/fmat.dart';
import 'package:flutter_test/flutter_test.dart';

String _shader(String name) => File('shaders/$name').readAsStringSync();

void main() {
  test('lit and unlit fragment sources open with the mediump default', () {
    for (final name in [
      'flutter_scene_standard.frag',
      'flutter_scene_unlit.frag',
    ]) {
      final source = _shader(name);
      final precision = source.indexOf('precision mediump float;');
      expect(precision, greaterThanOrEqualTo(0), reason: name);
      expect(source.indexOf('precision highp int;'), greaterThan(precision));
      expect(source.indexOf('#include'), greaterThan(precision), reason: name);
    }
  });

  test('emitted material sources put the default before the includes', () {
    final material = parseFmat('''
material {
  name: "Precision",
  shading_model: physical,
}

fragment {
  void Surface(inout MaterialInputs material) {}
}
''');
    final glsl = emitFragmentGlsl(material);
    final precision = glsl.indexOf('precision mediump float;');
    expect(precision, greaterThanOrEqualTo(0));
    expect(glsl.indexOf('#include'), greaterThan(precision));
  });

  test('the noise library runs in highp and restores the default', () {
    final noise = _shader('noise.glsl');
    final highp = noise.indexOf('precision highp float;');
    expect(highp, greaterThanOrEqualTo(0));
    expect(noise.indexOf('int noise_hash2('), greaterThan(highp));
    expect(
      noise.trimRight(),
      endsWith(
        '#ifdef FLUTTER_SCENE_DEFAULT_FLOAT_PRECISION\n'
        'precision FLUTTER_SCENE_DEFAULT_FLOAT_PRECISION float;\n'
        '#endif',
      ),
    );
    // Every mediump source names its default before declaring it.
    const define = '#define FLUTTER_SCENE_DEFAULT_FLOAT_PRECISION mediump';
    for (final source in [
      _shader('flutter_scene_standard.frag'),
      _shader('flutter_scene_unlit.frag'),
      emitFragmentGlsl(
        parseFmat('''
material {
  name: "Precision",
  shading_model: unlit,
}

fragment {
  void Surface(inout MaterialInputs material) {}
}
'''),
      ),
    ]) {
      final defined = source.indexOf(define);
      expect(defined, greaterThanOrEqualTo(0));
      expect(source.indexOf('precision mediump float;'), greaterThan(defined));
    }
  });

  test('a block shared with the vertex stage keeps highp members', () {
    final material = parseFmat('''
material {
  name: "Shared",
  shading_model: unlit,
  parameters: [
    { type: vec4, name: tint, default: [1.0, 1.0, 1.0, 1.0] },
    { type: float, name: lift, default: 0.0 },
  ],
}

vertex {
  void Vertex(inout VertexInputs vertex) {
    vertex.world_position.y += material_params.lift;
  }
}

fragment {
  void Surface(inout MaterialInputs material) {
    material.base_color = material_params.tint;
  }
}
''');
    final glsl = emitFragmentGlsl(material);
    expect(glsl, contains('  highp vec4 tint;'));
    expect(glsl, contains('  highp float lift;'));
  });

  test('world space, coordinates, and depth stay highp', () {
    final varyings = _shader('material_varyings.glsl');
    for (final decl in [
      'in highp vec3 v_position;',
      'in highp vec3 v_viewvector;',
      'in highp vec2 v_texture_coords;',
      'in highp vec2 v_texture_coords_1;',
      'highp vec3 GetWorldPosition()',
      'highp vec2 GetUV0()',
    ]) {
      expect(varyings, contains(decl));
    }
    final inputs = _shader('material_scene_inputs.glsl');
    for (final decl in [
      'highp mat4 light_space_matrix[4];',
      'highp vec4 ssao_params;',
      'highp vec4 froxel_grid;',
      'highp vec2 GetScreenUv()',
      'highp float GetFragmentViewDepth()',
    ]) {
      expect(inputs, contains(decl));
    }
    final shadows = _shader('material_shadow_sampling.glsl');
    for (final decl in [
      'highp float receiver_depth = proj.z',
      'highp vec4 FetchPunctualTexel(int light_index, int col)',
      'highp float FetchPunctualIndex(int j)',
      'highp vec2 PunctualLightSlice()',
    ]) {
      expect(shadows, contains(decl));
    }
    final lighting = _shader('material_lighting.glsl');
    for (final decl in [
      'highp vec3 direct = vec3(0.0);',
      'highp vec3 ambient =',
      'highp vec3 out_color = ambient',
    ]) {
      expect(lighting, contains(decl));
    }
    // The BRDF terms that can exceed fp16 clamp to its range.
    expect(_shader('pbr.glsl'), contains('kMediumpFloatMax'));
  });
}
