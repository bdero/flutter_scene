// Covers GeometryBuilder accumulation: vertex indexing, deduplication,
// triangle validation, sticky attributes, and interleaved packing.
// GeometryBuilder.build() and MeshGeometry.fromArrays() upload to the
// GPU and are exercised by the example app, not here.

import 'dart:typed_data';

import 'package:flutter_scene/src/geometry/mesh_geometry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

void main() {
  group('GeometryBuilder', () {
    test('addVertex returns sequential indices', () {
      final builder = GeometryBuilder(deduplicate: false);
      expect(builder.addVertex(Vector3(0, 0, 0)), 0);
      expect(builder.addVertex(Vector3(1, 0, 0)), 1);
      expect(builder.addVertex(Vector3(2, 0, 0)), 2);
      expect(builder.vertexCount, 3);
    });

    test('deduplicate merges a vertex equal to one already added', () {
      final builder = GeometryBuilder();
      final first = builder.addVertex(Vector3(1, 2, 3));
      final second = builder.addVertex(Vector3(1, 2, 3));
      expect(second, first);
      expect(builder.vertexCount, 1);
    });

    test('deduplicate distinguishes vertices by sticky attributes', () {
      final builder = GeometryBuilder();
      builder.color(Vector4(1, 0, 0, 1));
      builder.addVertex(Vector3(1, 2, 3));
      builder.color(Vector4(0, 1, 0, 1));
      builder.addVertex(Vector3(1, 2, 3));
      // Same position, different color: not merged.
      expect(builder.vertexCount, 2);
    });

    test('deduplicate: false keeps identical vertices', () {
      final builder = GeometryBuilder(deduplicate: false);
      builder.addVertex(Vector3(1, 2, 3));
      builder.addVertex(Vector3(1, 2, 3));
      expect(builder.vertexCount, 2);
    });

    test('addTriangle records indices and reports triangle count', () {
      final builder =
          GeometryBuilder(deduplicate: false)
            ..addVertex(Vector3(0, 0, 0))
            ..addVertex(Vector3(1, 0, 0))
            ..addVertex(Vector3(0, 1, 0))
            ..addTriangle(0, 1, 2);
      expect(builder.triangleCount, 1);
    });

    test('addTriangle rejects an out-of-range vertex index', () {
      final builder = GeometryBuilder()..addVertex(Vector3(0, 0, 0));
      expect(() => builder.addTriangle(0, 1, 2), throwsRangeError);
    });

    test('sticky attributes apply to subsequently added vertices', () {
      final builder =
          GeometryBuilder(deduplicate: false)
            ..color(Vector4(1, 0, 0, 1))
            ..addVertex(Vector3(0, 0, 0))
            ..color(Vector4(0, 1, 0, 1))
            ..texCoord(Vector2(0.5, 0.5))
            ..addVertex(Vector3(1, 0, 0));

      final floats = Float32List.sublistView(builder.packVertices());
      // Vertex 0 color (floats 8..11) is the first sticky color.
      expect(floats.sublist(8, 12), [1, 0, 0, 1]);
      // Vertex 1 color and texCoord (floats 6..7) are the later values.
      expect(floats.sublist(12 + 6, 12 + 8), [0.5, 0.5]);
      expect(floats.sublist(12 + 8, 12 + 12), [0, 1, 0, 1]);
    });

    test('packVertices generates normals for an authored triangle', () {
      final builder =
          GeometryBuilder(deduplicate: false)
            ..addVertex(Vector3(0, 0, 0))
            ..addVertex(Vector3(1, 0, 0))
            ..addVertex(Vector3(0, 1, 0))
            ..addTriangle(0, 1, 2);
      final floats = Float32List.sublistView(builder.packVertices());
      // Vertex 0 normal (floats 3..5) is the generated face normal +Z.
      expect(floats[3], closeTo(0, 1e-6));
      expect(floats[4], closeTo(0, 1e-6));
      expect(floats[5], closeTo(1, 1e-6));
    });

    test('authored normals override generation', () {
      final builder =
          GeometryBuilder(deduplicate: false)
            ..normal(Vector3(0, 1, 0))
            ..addVertex(Vector3(0, 0, 0))
            ..addVertex(Vector3(1, 0, 0))
            ..addVertex(Vector3(0, 1, 0))
            ..addTriangle(0, 1, 2);
      final floats = Float32List.sublistView(builder.packVertices());
      expect(floats.sublist(3, 6), [0, 1, 0]);
    });
  });

  group('nextBufferCapacity', () {
    test('returns the minimum when the need is small', () {
      expect(nextBufferCapacity(0), 16);
      expect(nextBufferCapacity(16), 16);
    });

    test('rounds up to the next power of two', () {
      expect(nextBufferCapacity(17), 32);
      expect(nextBufferCapacity(100), 128);
      expect(nextBufferCapacity(128), 128);
      expect(nextBufferCapacity(1000), 1024);
    });

    test('honors a custom minimum', () {
      expect(nextBufferCapacity(3, minimum: 8), 8);
      expect(nextBufferCapacity(9, minimum: 8), 16);
    });
  });
}
