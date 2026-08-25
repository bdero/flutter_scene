import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_scene/src/components/directional_light_component.dart';
import 'package:flutter_scene/src/fscene/realize/realize.dart';
import 'package:flutter_scene/src/importer/gltf.dart';
import 'package:flutter_scene/src/importer/in_memory_import.dart';
import 'package:flutter_scene/src/runtime_importer/runtime_importer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

void main() {
  group('glTF coordinate policy', () {
    test(
      'runtime and offline directional lights resolve the same direction',
      () async {
        final bytes = Uint8List.fromList(
          utf8.encode(
            jsonEncode({
              'asset': {'version': '2.0'},
              'extensionsUsed': ['KHR_lights_punctual'],
              'extensions': {
                'KHR_lights_punctual': {
                  'lights': [
                    {'type': 'directional'},
                  ],
                },
              },
              'scenes': [
                {
                  'nodes': [0],
                },
              ],
              'scene': 0,
              'nodes': [
                {
                  'rotation': [0.0, 0.38268343, 0.0, 0.92387953],
                  'extensions': {
                    'KHR_lights_punctual': {'light': 0},
                  },
                },
              ],
            }),
          ),
        );
        final runtime = await importGltf(
          bytes,
          resolveUri: (_) async => Uint8List(0),
        );
        final offline = realizeScene(
          importGltfToSceneDocument(bytes, resolveUri: (_) => null),
        );
        final runtimeLight = runtime.children.single
            .getComponent<DirectionalLightComponent>()!;
        final offlineLight = offline.children.single
            .getComponent<DirectionalLightComponent>()!;

        _expectVectorNear(
          runtimeLight.worldDirection,
          offlineLight.worldDirection,
        );
      },
    );

    test('runtime and offline imported triangles agree on drawn orientation', () {
      // A single CCW triangle in glTF space.
      final runtimePacked = _packWithIndices(
        GltfCoordinatePolicy.runtimeBoundary,
      );
      final offlinePacked = _packWithIndices(GltfCoordinatePolicy.bakeNative);

      final runtimeVertices = Float32List.sublistView(
        runtimePacked.vertexBytes,
      );
      final offlineVertices = Float32List.sublistView(
        offlinePacked.vertexBytes,
      );

      final runtimeIndices = Uint16List.sublistView(runtimePacked.indexBytes);
      final offlineIndices = Uint16List.sublistView(offlinePacked.indexBytes);

      // Runtime import preserves glTF vertex coordinates and CCW indices [0, 1, 2],
      // and places an F = diag(1, 1, -1) boundary transform at the imported root.
      // In world space, vertex i becomes F * v_i = (v_x, v_y, -v_z).
      Vector3 runtimeWorldVertex(int index) {
        final v = runtimeIndices[index];
        return Vector3(
          runtimeVertices[v * 18],
          runtimeVertices[v * 18 + 1],
          -runtimeVertices[v * 18 + 2],
        );
      }

      // Offline import bakes F into vertex positions and swaps indices to [0, 2, 1]
      // with an identity root transform.
      Vector3 offlineWorldVertex(int index) {
        final v = offlineIndices[index];
        return Vector3(
          offlineVertices[v * 18],
          offlineVertices[v * 18 + 1],
          offlineVertices[v * 18 + 2],
        );
      }

      // The drawn triangle in world space:
      final r0 = runtimeWorldVertex(0);
      final r1 = runtimeWorldVertex(1);
      final r2 = runtimeWorldVertex(2);

      final o0 = offlineWorldVertex(0);
      final o1 = offlineWorldVertex(1);
      final o2 = offlineWorldVertex(2);

      // Because runtime's F transform has negative determinant (parity flip),
      // the effective world-space winding normal is (r2 - r0) x (r1 - r0),
      // exactly matching offline's CCW geometric normal (o1 - o0) x (o2 - o0).
      final runtimeEffectiveNormal = (r2 - r0).cross(r1 - r0);
      final offlineEffectiveNormal = (o1 - o0).cross(o2 - o0);

      _expectVectorNear(runtimeEffectiveNormal, offlineEffectiveNormal);
    });

    test('runtime packing leaves vertex bytes untouched', () {
      final source = _pack(GltfCoordinatePolicy.runtimeBoundary);
      final vertices = Float32List.sublistView(source.vertexBytes);

      expect(vertices.sublist(0, 3), [1, 2, 3]);
      _expectListNear(vertices.sublist(3, 6), [0.25, 0.5, 0.75]);
      _expectListNear(vertices.sublist(14, 18), [0.1, 0.2, 0.3, -1]);
      expect(source.sourceWindingFlipped, isFalse);
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

    test('offline packing swaps index pairs for CCW native winding', () {
      final source = _packWithIndices(GltfCoordinatePolicy.runtimeBoundary);
      final native = _packWithIndices(GltfCoordinatePolicy.bakeNative);

      final sourceIndices = Uint16List.sublistView(source.indexBytes);
      final nativeIndices = Uint16List.sublistView(native.indexBytes);

      expect(sourceIndices, [0, 1, 2]);
      expect(nativeIndices, [0, 2, 1]);
      expect(source.sourceWindingFlipped, isFalse);
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

PackedPrimitive _packWithIndices(GltfCoordinatePolicy policy) {
  final positions = Float32List.fromList([0, 0, 0, 1, 0, 0, 0, 1, 0]);
  final indices = Uint16List.fromList([0, 1, 2]);
  final buffer = Uint8List(positions.lengthInBytes + indices.lengthInBytes);
  buffer.setRange(0, positions.lengthInBytes, positions.buffer.asUint8List());
  buffer.setRange(
    positions.lengthInBytes,
    buffer.length,
    indices.buffer.asUint8List(),
  );

  return packGltfPrimitive(
    primitive: GltfMeshPrimitive(attributes: const {'POSITION': 0}, indices: 1),
    accessors: [
      GltfAccessor(
        componentType: GltfComponentType.float,
        count: 3,
        type: GltfAccessorType.vec3,
        bufferView: 0,
      ),
      GltfAccessor(
        componentType: GltfComponentType.unsignedShort,
        count: 3,
        type: GltfAccessorType.scalar,
        bufferView: 1,
      ),
    ],
    bufferViews: [
      GltfBufferView(
        buffer: 0,
        byteOffset: 0,
        byteLength: positions.lengthInBytes,
      ),
      GltfBufferView(
        buffer: 0,
        byteOffset: positions.lengthInBytes,
        byteLength: indices.lengthInBytes,
      ),
    ],
    bufferData: buffer,
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
