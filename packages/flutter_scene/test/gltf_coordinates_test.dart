import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_scene/src/components/directional_light_component.dart';
import 'package:flutter_scene/src/fscene/realize/realize.dart';
import 'package:flutter_scene/src/importer/gltf.dart';
import 'package:flutter_scene/src/importer/in_memory_import.dart';
import 'package:flutter_scene/src/runtime_importer/runtime_importer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

// glTF and the engine share one right-handed, -Z forward, CCW convention, so
// import carries source data through unchanged on both paths.
void main() {
  group('glTF coordinates', () {
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
        // An untransformed glTF light points down -Z; a 45 degree yaw swings
        // it toward -X.
        _expectVectorNear(
          runtimeLight.worldDirection,
          Vector3(-0.70710678, 0.0, -0.70710678),
        );
      },
    );

    test('packing leaves positions, normals, and tangents untouched', () {
      final packed = _pack();
      final vertices = Float32List.sublistView(packed.vertexBytes);

      expect(vertices.sublist(0, 3), [1, 2, 3]);
      _expectListNear(vertices.sublist(3, 6), [0.25, 0.5, 0.75]);
      _expectListNear(vertices.sublist(14, 18), [0.1, 0.2, 0.3, -1]);
    });

    test('packing preserves CCW index order', () {
      final packed = _packWithIndices();
      final indices = Uint16List.sublistView(packed.indexBytes);
      final vertices = Float32List.sublistView(packed.vertexBytes);

      expect(indices, [0, 1, 2]);

      Vector3 vertex(int index) {
        final v = indices[index];
        return Vector3(
          vertices[v * 18],
          vertices[v * 18 + 1],
          vertices[v * 18 + 2],
        );
      }

      // The source triangle winds counter-clockwise seen from +Z, so its
      // geometric normal faces the default camera.
      final normal = (vertex(1) - vertex(0)).cross(vertex(2) - vertex(0));
      _expectVectorNear(normal, Vector3(0, 0, 1));
    });
  });
}

PackedPrimitive _pack() {
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
  );
}

PackedPrimitive _packWithIndices() {
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
