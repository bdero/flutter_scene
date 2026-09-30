// ignore: implementation_imports
import 'package:flutter_scene/src/fmat/fmat.dart';
import 'package:flutter_test/flutter_test.dart';

String _material({
  String extra = '',
  String vertex = '',
  String surface = '',
}) =>
    '''
material {
  name: "Probe",
  shading_model: lit,
  $extra
}
${vertex.isEmpty ? '' : 'vertex {\n  void Vertex(inout VertexInputs vertex) {\n    $vertex\n  }\n}'}
fragment {
  void Surface(inout MaterialInputs material) {
    $surface
    material.base_color = vec4(1.0);
  }
}
''';

bool? _flag(String source) =>
    buildSidecar(
          compileFmat(source, fileName: 'probe.fmat').material,
        )['shadow_reads_camera']
        as bool?;

void main() {
  test('a vertex stage reading the camera marks the shadow view dependent', () {
    expect(
      _flag(
        _material(
          vertex:
              'vertex.world_position.y -= 0.01 * distance(vertex.world_position, vertex.camera_position);',
        ),
      ),
      isTrue,
    );
  });

  test('a vertex stage that ignores the camera leaves shadows shareable', () {
    expect(_flag(_material(vertex: 'vertex.world_position.y += 0.1;')), isNull);
  });

  test('a cutout surface reading the view marks the shadow view dependent', () {
    expect(
      _flag(
        _material(
          extra: 'alpha_to_coverage: true,',
          surface: 'if (GetFragmentViewDepth() > 5.0) discard;',
        ),
      ),
      isTrue,
    );
  });

  test('an opaque surface reading the view casts through the engine depth', () {
    expect(
      _flag(_material(surface: 'float d = GetFragmentViewDepth();')),
      isNull,
    );
  });
}
