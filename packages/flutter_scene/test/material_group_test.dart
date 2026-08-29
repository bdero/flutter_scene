// The name-and-type gate MaterialGroup writes through. The group's promise is
// that one write spans a heterogeneous set, so a member that does not declare
// the name, or declares it with another type, is skipped rather than throwing
// partway through the group and leaving earlier members written. Constructing
// a PreprocessedMaterial needs a compiled shader, so the gate is exercised on
// the parameter block it reads.

import 'package:flutter_scene/src/fmat/fmat_ast.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/material/material_parameters.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

void main() {
  final parameters = MaterialParameters.withLayout(
    blockName: 'MaterialParams',
    blockSizeBytes: 32,
    parameters: {
      'strength': (type: FmatType.float_, offset: 0, sourceColor: false),
      'tint': (type: FmatType.vec4, offset: 16, sourceColor: false),
    },
  );

  test('the type gate accepts only the declared type', () {
    expect(parameters.hasParameterOfType('strength', FmatType.float_), isTrue);
    expect(parameters.hasParameterOfType('tint', FmatType.vec4), isTrue);
  });

  test('a name declared with another type is rejected, not thrown on', () {
    // The setter this gates would throw ArgumentError, which is what aborts a
    // group write partway through.
    expect(parameters.hasParameterOfType('strength', FmatType.vec3), isFalse);
    expect(
      () => parameters.setVec3('strength', Vector3.zero()),
      throwsArgumentError,
    );
  });

  test('an undeclared name is rejected for every type', () {
    for (final type in FmatType.values) {
      expect(parameters.hasParameterOfType('missing', type), isFalse);
    }
  });
}
