import 'package:flutter_scene/src/gpu/shared/glsl_transpile.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('strips the SPIRV-Cross clip-space depth remap', () {
    const source = '''
#version 300 es
in vec3 position;
uniform float _impeller_y_flip;
void main()
{
    gl_Position = vec4(position, 1.0);
    gl_Position.y *= _impeller_y_flip;
    gl_Position.z = 2.0 * gl_Position.z - gl_Position.w;
}
''';
    final stripped = stripClipSpaceDepthRemap(source);
    expect(stripped, isNot(contains('2.0 * gl_Position.z')));
    // Everything else, the y flip included, stays.
    expect(stripped, contains('gl_Position.y *= _impeller_y_flip;'));
    expect(stripped, contains('gl_Position = vec4(position, 1.0);'));
    expect(stripped.split('\n').length, source.split('\n').length - 1);
  });

  test('leaves a shader without the remap unchanged', () {
    const source = 'void main() { gl_Position.z = gl_Position.w; }\n';
    expect(stripClipSpaceDepthRemap(source), source);
  });
}
