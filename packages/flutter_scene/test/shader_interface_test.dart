import 'package:flutter_scene/src/material/shader_interface.dart';
import 'package:flutter_test/flutter_test.dart';

// MSL as SPIRV-Cross emits it for the engine's skinned vertex shader and for
// the example app's toon fragment shader, before and after it declared every
// engine varying. A fragment input a shader does not read is dropped, but the
// inputs it does read keep their declared locations.
const _engineVertex = '''
struct flutter_scene_skinned_vertex_main_out
{
    float3 v_position [[user(locn0)]];
    float3 v_normal [[user(locn1)]];
    float3 v_viewvector [[user(locn2)]];
    float2 v_texture_coords [[user(locn3)]];
    float2 v_texture_coords_1 [[user(locn4)]];
    float4 v_color [[user(locn5)]];
    float4 v_tangent [[user(locn6)]];
    float4 gl_Position [[position]];
};

struct flutter_scene_skinned_vertex_main_in
{
    float3 position [[attribute(0)]];
};
''';

const _toonDeclaringFive = '''
struct example_toon_fragment_main_out
{
    float4 frag_color [[color(0)]];
};

struct example_toon_fragment_main_in
{
    float3 v_normal [[user(locn1)]];
    float3 v_viewvector [[user(locn2)]];
    float2 v_texture_coords [[user(locn3)]];
    float4 v_color [[user(locn4)]];
};
''';

const _toonDeclaringSeven = '''
struct example_toon_fragment_main_in
{
    float3 v_normal [[user(locn1)]];
    float3 v_viewvector [[user(locn2)]];
    float2 v_texture_coords [[user(locn3)]];
    float4 v_color [[user(locn5)]];
};
''';

void main() {
  group('parseMslVaryings', () {
    test('reads a vertex shader\'s outputs, skipping the position builtin', () {
      expect(
        parseMslVaryings(
          _engineVertex,
          'flutter_scene_skinned_vertex_main',
          outputs: true,
        ),
        standardVaryings,
      );
    });

    test('reads a fragment shader\'s inputs in location order', () {
      expect(
        parseMslVaryings(
          _toonDeclaringFive,
          'example_toon_fragment_main',
          outputs: false,
        ),
        const [
          StageVarying(1, 'float3', 'v_normal'),
          StageVarying(2, 'float3', 'v_viewvector'),
          StageVarying(3, 'float2', 'v_texture_coords'),
          StageVarying(4, 'float4', 'v_color'),
        ],
      );
    });

    test('is empty for a stage with no interface struct', () {
      expect(
        parseMslVaryings(
          _toonDeclaringFive,
          'some_other_entry',
          outputs: false,
        ),
        isEmpty,
      );
    });
  });

  group('describeVaryingMismatch', () {
    test('names a fragment input that lands on the wrong output', () {
      final mismatch = describeVaryingMismatch(
        standardVaryings,
        parseMslVaryings(
          _toonDeclaringFive,
          'example_toon_fragment_main',
          outputs: false,
        ),
      );
      expect(
        mismatch,
        'v_color (float4) at location 4, where the vertex shader writes '
        'v_texture_coords_1 (float2)',
      );
    });

    test('accepts a fragment shader that declares every varying', () {
      expect(
        describeVaryingMismatch(
          standardVaryings,
          parseMslVaryings(
            _toonDeclaringSeven,
            'example_toon_fragment_main',
            outputs: false,
          ),
        ),
        isNull,
      );
    });

    test('names an input the vertex shader does not write', () {
      expect(
        describeVaryingMismatch(standardVaryings, const [
          StageVarying(7, 'float', 'v_ripple'),
        ]),
        'v_ripple (float) at location 7, which the vertex shader does not '
        'write',
      );
    });

    test('ignores outputs nothing reads', () {
      expect(describeVaryingMismatch(standardVaryings, const []), isNull);
    });
  });
}
