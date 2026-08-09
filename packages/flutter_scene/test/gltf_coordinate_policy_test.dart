import 'dart:typed_data';

import 'package:flutter_scene/src/importer/gltf.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

void main() {
  group('glTF coordinate policy', () {
    test('runtime packing leaves vertex bytes untouched', () {
      final source = _pack(GltfCoordinatePolicy.runtimeBoundary);
      final vertices = Float32List.sublistView(source.vertexBytes);

      expect(vertices.sublist(0, 3), [1, 2, 3]);
      _expectListNear(vertices.sublist(3, 6), [0.25, 0.5, 0.75]);
      _expectListNear(vertices.sublist(14, 18), [0.1, 0.2, 0.3, -1]);
      expect(source.sourceWindingFlipped, isTrue);
    });

    test('offline packing reflects vectors and tangent handedness', () {
      final source = _pack(GltfCoordinatePolicy.runtimeBoundary);
      final native = _pack(GltfCoordinatePolicy.bakeNative);
      final vertices = Float32List.sublistView(native.vertexBytes);

      expect(vertices.sublist(0, 3), [1, 2, -3]);
      _expectListNear(vertices.sublist(3, 6), [0.25, 0.5, -0.75]);
      _expectListNear(vertices.sublist(14, 18), [0.1, 0.2, -0.3, 1]);
      expect(native.indexBytes, source.indexBytes);
      expect(native.sourceWindingFlipped, isFalse);
    });

    test('baked and boundary transforms produce the same world point', () {
      const policy = GltfCoordinatePolicy.bakeNative;
      final sourceTransform = Matrix4.compose(
        Vector3(4, 5, 6),
        Quaternion.axisAngle(Vector3(1, 2, 3).normalized(), 0.7),
        Vector3(2, 3, 4),
      );
      final sourcePoint = Vector3(7, 8, 9);
      final boundaryResult = sourceTransform.transform3(sourcePoint.clone());
      boundaryResult.z = -boundaryResult.z;
      final bakedResult = policy
          .convertTransform(sourceTransform)
          .transform3(policy.convertPosition(sourcePoint));

      _expectVectorNear(bakedResult, boundaryResult);
    });

    test('TRS, animation, and inverse-bind conversions agree', () {
      const policy = GltfCoordinatePolicy.bakeNative;
      final translation = Vector3(1, 2, 3);
      final rotation = Quaternion.axisAngle(Vector3(1, 2, 3).normalized(), 0.4);
      final source = Matrix4.compose(translation, rotation, Vector3(2, 3, 4));
      final convertedTrs = Matrix4.compose(
        policy.convertPosition(translation),
        policy.convertRotation(rotation),
        Vector3(2, 3, 4),
      );
      _expectMatrixNear(convertedTrs, policy.convertTransform(source));

      final translations = policy.convertAnimationValues(
        Float32List.fromList([1, 2, 3, 4, 5, 6]),
        targetPath: 'translation',
      );
      expect(translations, [1, 2, -3, 4, 5, -6]);

      final rotations = policy.convertAnimationValues(
        Float32List.fromList([1, 2, 3, 4]),
        targetPath: 'rotation',
      );
      expect(rotations, [-1, -2, 3, 4]);

      final matrices = policy.convertMatrices(
        Float32List.fromList(source.storage),
      );
      _expectMatrixNear(Matrix4.fromFloat32List(matrices), convertedTrs);
    });
  });
}

PackedPrimitive _pack(GltfCoordinatePolicy policy) {
  final attributes = Float32List.fromList([
    1,
    2,
    3,
    0.25,
    0.5,
    0.75,
    0.1,
    0.2,
    0.3,
    -1,
  ]);
  return packGltfPrimitive(
    primitive: GltfMeshPrimitive(
      attributes: const {'POSITION': 0, 'NORMAL': 1, 'TANGENT': 2},
    ),
    accessors: [
      GltfAccessor(
        componentType: GltfComponentType.float,
        count: 1,
        type: GltfAccessorType.vec3,
        bufferView: 0,
      ),
      GltfAccessor(
        componentType: GltfComponentType.float,
        count: 1,
        type: GltfAccessorType.vec3,
        bufferView: 1,
      ),
      GltfAccessor(
        componentType: GltfComponentType.float,
        count: 1,
        type: GltfAccessorType.vec4,
        bufferView: 2,
      ),
    ],
    bufferViews: [
      GltfBufferView(buffer: 0, byteOffset: 0, byteLength: 12),
      GltfBufferView(buffer: 0, byteOffset: 12, byteLength: 12),
      GltfBufferView(buffer: 0, byteOffset: 24, byteLength: 16),
    ],
    bufferData: attributes.buffer.asUint8List(),
    coordinatePolicy: policy,
  );
}

void _expectVectorNear(Vector3 actual, Vector3 expected) {
  for (var i = 0; i < 3; i++) {
    expect(actual[i], closeTo(expected[i], 1e-5));
  }
}

void _expectListNear(List<double> actual, List<double> expected) {
  for (var i = 0; i < expected.length; i++) {
    expect(actual[i], closeTo(expected[i], 1e-5));
  }
}

void _expectMatrixNear(Matrix4 actual, Matrix4 expected) {
  for (var i = 0; i < 16; i++) {
    expect(actual.storage[i], closeTo(expected.storage[i], 1e-5));
  }
}
