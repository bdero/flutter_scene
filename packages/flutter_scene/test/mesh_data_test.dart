// Covers the MeshData snapshot: pure construction (normal generation,
// validation) and that it survives an isolate round-trip, the property
// that lets meshing run off the render isolate. Turning a MeshData into a
// live MeshGeometry uploads to the GPU and is exercised by the example app.

import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter_scene/src/geometry/mesh_data.dart';
import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_test/flutter_test.dart';

// Top-level so it can run on a background isolate via compute.
MeshData buildTriangleData(Float32List positions) =>
    MeshData.build(positions: positions, indices: <int>[0, 1, 2]);

void main() {
  // A triangle wound per the engine front-face convention (clockwise in
  // model space), whose generated face normal points at +Z.
  final triangle = Float32List.fromList(<double>[0, 0, 0, 0, 1, 0, 1, 0, 0]);

  group('MeshData.build', () {
    test('generates face normals when normals are absent', () {
      final data = MeshData.build(positions: triangle, indices: <int>[0, 1, 2]);
      expect(data.vertexCount, 3);
      expect(data.normals, isNotNull);
      expect(data.normals!, hasLength(3 * 3));
      // Vertex 0's generated normal is +Z.
      expect(data.normals![0], closeTo(0, 1e-6));
      expect(data.normals![1], closeTo(0, 1e-6));
      expect(data.normals![2], closeTo(1, 1e-6));
    });

    test('preserves authored normals', () {
      final normals = Float32List.fromList(<double>[0, 1, 0, 0, 1, 0, 0, 1, 0]);
      final data = MeshData.build(positions: triangle, normals: normals);
      expect(data.normals, same(normals));
    });

    test('leaves normals null for a point primitive', () {
      final data = MeshData.build(
        positions: triangle,
        primitiveType: gpu.PrimitiveType.point,
      );
      expect(data.normals, isNull);
    });

    test('rejects a position array that is not whole vertices', () {
      expect(
        () => MeshData.build(positions: Float32List(4)),
        throwsArgumentError,
      );
    });
  });

  test('a MeshData survives an isolate round-trip', () async {
    final data = await compute(buildTriangleData, triangle);
    expect(data.vertexCount, 3);
    expect(data.positions, triangle);
    expect(data.indices, <int>[0, 1, 2]);
    // The off-isolate build generated the same +Z normal.
    expect(data.normals![2], closeTo(1, 1e-6));
  });
}
