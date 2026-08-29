// The decal projection math and the parameter writes it drives. A DecalNode
// itself owns GPU geometry and a compiled material, so the seams both sides of
// that (the box transform and the parameter write) are what a headless test can
// reach; the drawn result is covered by the `decal` smoke scene.

import 'dart:typed_data';

import 'package:flutter_scene/src/fmat/fmat_ast.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/decal.dart';
import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_scene/src/material/material_parameters.dart';
import 'package:flutter_scene/src/material/physically_based_material.dart';
import 'package:flutter_scene/src/material/unlit_material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

MaterialParameters _decalParameters({
  bool declared = true,
}) => MaterialParameters.withLayout(
  blockName: 'MaterialParams',
  blockSizeBytes: 80,
  parameters: declared
      ? {
          'decal_inverse': (type: FmatType.mat4, offset: 0, sourceColor: false),
          'decal_fade': (type: FmatType.float_, offset: 64, sourceColor: false),
        }
      : {'tint': (type: FmatType.vec4, offset: 0, sourceColor: false)},
);

void main() {
  test('a straight-down projection maps the box onto the world axes', () {
    final transform = DecalNode.boxTransform(
      point: Vector3(2, 1, -3),
      normal: Vector3(0, 1, 0),
      size: 2.0,
      depth: 4.0,
    );
    final inverse = Matrix4.inverted(transform);

    // The projection point is the box center.
    expect(
      inverse.transformed3(Vector3(2, 1, -3)),
      _closeToVector(Vector3(0, 0, 0)),
    );
    // Half the size across, half the depth along the normal, are the faces.
    expect(
      inverse.transformed3(Vector3(3, 1, -3)),
      _closeToVector(Vector3(0.5, 0, 0)),
    );
    expect(
      inverse.transformed3(Vector3(2, 1, -2)),
      _closeToVector(Vector3(0, 0, 0.5)),
    );
    expect(
      inverse.transformed3(Vector3(2, 3, -3)),
      _closeToVector(Vector3(0, 0.5, 0)),
    );
    // A point past a face lands outside the unit box, where the shader
    // discards.
    expect(inverse.transformed3(Vector3(4, 1, -3)).x, greaterThan(0.5));
  });

  test('the box transform aligns its Y with the projection normal', () {
    final transform = DecalNode.boxTransform(
      point: Vector3.zero(),
      normal: Vector3(1, 0, 0),
      size: 1.0,
      depth: 1.0,
    );
    final inverse = Matrix4.inverted(transform);

    // Along the normal is local Y, whatever the normal is.
    expect(
      inverse.transformed3(Vector3(0.5, 0, 0)),
      _closeToVector(Vector3(0, 0.5, 0)),
    );
    // The basis stays right-handed, so the draw is not winding-flipped.
    expect(transform.determinant(), greaterThan(0));
  });

  test('rotation spins the projection about the normal', () {
    final transform = DecalNode.boxTransform(
      point: Vector3.zero(),
      normal: Vector3(0, 1, 0),
      size: 2.0,
      depth: 1.0,
      rotation: 1.5707963267948966,
    );
    final inverse = Matrix4.inverted(transform);

    // A quarter turn about the normal sends world +X to local +Z, so the
    // sampled texture rotates with it.
    expect(
      inverse.transformed3(Vector3(1, 0, 0)),
      _closeToVector(Vector3(0, 0, 0.5)),
    );
  });

  test('the projection and the fade write through to the material', () {
    final parameters = _decalParameters();
    final inverse = Matrix4.inverted(
      DecalNode.boxTransform(
        point: Vector3(0, 0, 0),
        normal: Vector3(0, 1, 0),
        size: 2.0,
        depth: 2.0,
      ),
    );
    writeDecalParameters(parameters, inverse: inverse, fade: 0.25);

    final block = parameters.rawBlock;
    for (var i = 0; i < 16; i++) {
      expect(
        block.getFloat32(i * 4, Endian.host),
        closeTo(inverse.storage[i], 1e-6),
      );
    }
    expect(block.getFloat32(64, Endian.host), closeTo(0.25, 1e-6));
  });

  test('a material that declares neither parameter is skipped, not thrown', () {
    final parameters = _decalParameters(declared: false);
    expect(
      () => writeDecalParameters(
        parameters,
        inverse: Matrix4.identity(),
        fade: 1.0,
      ),
      returnsNormally,
    );
  });

  test('a mismatched decal parameter type is skipped, not written', () {
    // A material that spells decal_fade as a vec4 must not take a setFloat
    // write; the writer gates on the declared type, not just the name.
    final parameters = MaterialParameters.withLayout(
      blockName: 'MaterialParams',
      blockSizeBytes: 80,
      parameters: {
        'decal_inverse': (type: FmatType.mat4, offset: 0, sourceColor: false),
        'decal_fade': (type: FmatType.vec4, offset: 64, sourceColor: false),
      },
    );

    expect(
      () => writeDecalParameters(
        parameters,
        inverse: Matrix4.identity(),
        fade: 0.25,
      ),
      returnsNormally,
    );
    expect(parameters.isParameterAssigned('decal_fade'), isFalse);
    expect(parameters.isParameterAssigned('decal_inverse'), isTrue);
  });

  test('the built-in materials keep the occluding depth test', () {
    expect(UnlitMaterial().depthCompare, gpu.CompareFunction.lessEqual);
    expect(
      PhysicallyBasedMaterial().depthCompare,
      gpu.CompareFunction.lessEqual,
    );
  });
}

Matcher _closeToVector(Vector3 expected) => predicate<Vector3>(
  (actual) => (actual - expected).length < 1e-6,
  'is within 1e-6 of $expected',
);
