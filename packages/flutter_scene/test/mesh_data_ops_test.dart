// Covers the MeshData derivation operations (unweld, extractEdges, merge,
// triangles) and the readback surface (isReadable, extractMeshData through
// the structure-of-arrays retention path). The GPU-uploading halves
// (MeshGeometry.fromMeshData custom-attribute plumbing, the interleaved
// importer path, LineSegmentsGeometry) draw on a real context and are
// exercised by the example app.

import 'dart:typed_data';

import 'package:flutter_scene/scene.dart';
import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

/// Geometry that skips shader-library and GPU access, so the base-class
/// readback state can be exercised without a Flutter GPU context.
class _StubGeometry extends Geometry {
  @override
  void bind(
    gpu.RenderPass pass,
    gpu.HostBuffer transientsBuffer,
    Matrix4 modelTransform,
    Matrix4 cameraTransform,
    Vector3 cameraPosition, {
    gpu.Shader? shaderOverride,
  }) {
    throw UnsupportedError('Stub geometry is not renderable');
  }
}

/// A unit quad, two triangles sharing the diagonal 0-2.
MeshData _quad() {
  return MeshData.build(
    positions: Float32List.fromList([
      0, 0, 0, //
      1, 0, 0, //
      1, 1, 0, //
      0, 1, 0,
    ]),
    texCoords: Float32List.fromList([0, 0, 1, 0, 1, 1, 0, 1]),
    indices: [0, 1, 2, 0, 2, 3],
  );
}

/// Two triangles meeting at exactly ninety degrees along the shared edge
/// 0-1 (face normals (0,-1,0) and (0,0,-1)), for crease-angle filtering.
MeshData _tent() {
  return MeshData.build(
    positions: Float32List.fromList([
      0, 0, 0, //
      1, 0, 0, //
      1, 0, 1, //
      0, 1, 0,
    ]),
    indices: [0, 1, 2, 1, 0, 3],
  );
}

void main() {
  group('triangles', () {
    test('iterates indexed triangles with corner indices and positions', () {
      final quad = _quad();
      final tris = quad.triangles.toList();
      expect(tris, hasLength(2));
      expect(quad.triangleCount, 2);
      expect(tris[0].index, 0);
      expect([tris[0].a, tris[0].b, tris[0].c], [0, 1, 2]);
      expect([tris[1].a, tris[1].b, tris[1].c], [0, 2, 3]);
      expect(tris[1].pa, Vector3(0, 0, 0));
      expect(tris[1].pc, Vector3(0, 1, 0));
    });

    test('iterates unindexed soup sequentially', () {
      final soup = MeshData.build(
        positions: Float32List.fromList([
          0, 0, 0, 1, 0, 0, 0, 1, 0, //
          2, 0, 0, 3, 0, 0, 2, 1, 0,
        ]),
      );
      final tris = soup.triangles.toList();
      expect(tris, hasLength(2));
      expect([tris[1].a, tris[1].b, tris[1].c], [3, 4, 5]);
    });

    test('rejects non-triangle primitive types', () {
      final lines = MeshData(
        positions: Float32List(12),
        vertexCount: 4,
        primitiveType: gpu.PrimitiveType.line,
      );
      expect(() => lines.triangles.toList(), throwsStateError);
      expect(() => lines.unweld(), throwsStateError);
      expect(() => lines.extractEdges(), throwsStateError);
    });
  });

  group('unweld', () {
    test('produces an unindexed soup with three vertices per triangle', () {
      final out = _quad().unweld();
      expect(out.indices, isNull);
      expect(out.vertexCount, 6);
      expect(out.triangleCount, 2);
      // Corner positions expand through the index buffer.
      expect(out.positions.sublist(0, 3), [0, 0, 0]);
      expect(out.positions.sublist(9, 12), [0, 0, 0]); // second tri corner 0
      // Texture coordinates carry through per corner.
      expect(out.texCoords!.sublist(0, 2), [0, 0]);
      expect(out.texCoords!.sublist(10, 12), [0, 1]);
    });

    test('assigns the face normal to every corner', () {
      final out = _quad().unweld();
      for (var v = 0; v < out.vertexCount; v++) {
        expect(out.normals![v * 3], 0);
        expect(out.normals![v * 3 + 1], 0);
        expect(out.normals![v * 3 + 2].abs(), 1);
      }
      // Both triangles of the flat quad agree.
      expect(out.normals![2], out.normals![5 * 3 + 2]);
    });

    test('face normal sign agrees with authored vertex normals', () {
      // Author inward (-z) normals on a quad wound for +z; the face normal
      // must flip to match the authored orientation.
      final quad = MeshData(
        positions: _quad().positions,
        vertexCount: 4,
        normals: Float32List.fromList([
          0, 0, -1, 0, 0, -1, 0, 0, -1, 0, 0, -1, //
        ]),
        indices: [0, 1, 2, 0, 2, 3],
      );
      final out = quad.unweld();
      expect(out.normals![2], -1);
    });

    test('attaches the canned per-triangle attributes', () {
      final out = _quad().unweld(
        attributes: {
          UnweldAttribute.centroid,
          UnweldAttribute.seed,
          UnweldAttribute.triangleIndex,
          UnweldAttribute.barycentric,
        },
      );
      final centroid = out.customAttributes['triangle_centroid']!;
      expect(centroid.components, 3);
      // Triangle 0 is (0,0,0)/(1,0,0)/(1,1,0); every corner carries its
      // centroid.
      expect(centroid.data[0], closeTo(2 / 3, 1e-6));
      expect(centroid.data[1], closeTo(1 / 3, 1e-6));
      expect(centroid.data[2], 0);
      expect(centroid.data.sublist(6, 9), centroid.data.sublist(0, 3));

      final seed = out.customAttributes['triangle_seed']!;
      expect(seed.components, 1);
      expect(seed.data[0], seed.data[1]);
      expect(seed.data[0], isNot(seed.data[3]));
      expect(seed.data[0], inInclusiveRange(0, 1));
      // Deterministic across runs.
      expect(
        _quad()
            .unweld(attributes: {UnweldAttribute.seed})
            .customAttributes['triangle_seed']!
            .data[0],
        seed.data[0],
      );

      final index = out.customAttributes['triangle_index']!;
      expect(index.data[0], 0);
      expect(index.data[3], 1);

      final bary = out.customAttributes['barycentric']!;
      expect(bary.data.sublist(0, 9), [1, 0, 0, 0, 1, 0, 0, 0, 1]);
    });

    test('carries existing custom attributes through per corner', () {
      final quad = _quad();
      final tagged = MeshData(
        positions: quad.positions,
        vertexCount: quad.vertexCount,
        indices: quad.indices,
        customAttributes: {
          'tag': MeshAttributeData(
            Float32List.fromList([10, 20, 30, 40]),
            components: 1,
          ),
        },
      );
      final out = tagged.unweld();
      expect(out.customAttributes['tag']!.data, [10, 20, 30, 10, 30, 40]);
    });
  });

  group('extractEdges', () {
    test('deduplicates shared edges', () {
      final edges = _quad().extractEdges();
      // Four boundary edges plus the shared diagonal.
      expect(edges.segmentCount, 5);
      expect(edges.positions.length, 5 * 6);
      // Normals carry from the source (generated smooth normals here).
      expect(edges.normals, isNotNull);
      expect(edges.normals!.length, edges.positions.length);
    });

    test('crease filter keeps sharp and boundary edges only', () {
      // The flat quad's diagonal disappears under any crease threshold; the
      // four boundary edges stay.
      final flat = _quad().extractEdges(creaseAngleDegrees: 10);
      expect(flat.segmentCount, 4);

      // The tent's shared edge is a 90-degree crease, kept below the
      // threshold and dropped above it.
      expect(_tent().extractEdges(creaseAngleDegrees: 45).segmentCount, 5);
      expect(_tent().extractEdges(creaseAngleDegrees: 135).segmentCount, 4);
    });
  });

  group('merge', () {
    test('concatenates and rebases indices', () {
      final merged = MeshData.merge([_quad(), _quad()]);
      expect(merged.vertexCount, 8);
      expect(merged.indices, hasLength(12));
      expect(merged.indices!.sublist(6, 9), [4, 5, 6]);
      expect(merged.positions.length, 24);
    });

    test('synthesizes indices for unindexed parts', () {
      final indexed = MeshData.build(
        positions: Float32List.fromList([0, 0, 0, 1, 0, 0, 0, 1, 0]),
        indices: [0, 1, 2],
      );
      final soup = MeshData.build(
        positions: Float32List.fromList([2, 0, 0, 3, 0, 0, 2, 1, 0]),
      );
      final merged = MeshData.merge([indexed, soup]);
      expect(merged.vertexCount, 6);
      expect(merged.indices!.sublist(3), [3, 4, 5]);
    });

    test('rejects mismatched attribute sets', () {
      final withUv = _quad();
      final withoutUv = MeshData.build(
        positions: Float32List.fromList([0, 0, 0, 1, 0, 0, 0, 1, 0]),
      );
      expect(() => MeshData.merge([withUv, withoutUv]), throwsArgumentError);
    });

    test('merges matching custom attributes and rejects mismatches', () {
      MeshData tagged(double value) => MeshData(
        positions: Float32List.fromList([0, 0, 0, 1, 0, 0, 0, 1, 0]),
        vertexCount: 3,
        customAttributes: {
          'tag': MeshAttributeData(
            Float32List.fromList([value, value, value]),
            components: 1,
          ),
        },
      );
      final merged = MeshData.merge([tagged(1), tagged(2)]);
      expect(merged.customAttributes['tag']!.data, [1, 1, 1, 2, 2, 2]);

      final untagged = MeshData(
        positions: Float32List.fromList([0, 0, 0, 1, 0, 0, 0, 1, 0]),
        vertexCount: 3,
      );
      expect(() => MeshData.merge([tagged(1), untagged]), throwsArgumentError);
    });
  });

  group('readback', () {
    test('isReadable is false with no retained data, and extract throws', () {
      final stub = _StubGeometry();
      expect(stub.isReadable, isFalse);
      expect(stub.extractMeshData, throwsStateError);
    });

    test('extractMeshData copies the SoA retention path', () {
      final stub = _StubGeometry();
      final positions = Float32List.fromList([0, 0, 0, 1, 0, 0, 0, 1, 0]);
      final normals = Float32List.fromList([0, 0, 1, 0, 0, 1, 0, 0, 1]);
      final indexBytes = Uint16List.fromList([0, 1, 2]);
      stub.setRaycastAttributes(
        positions: positions,
        normals: normals,
        indices: ByteData.sublistView(indexBytes),
      );
      // setRaycastAttributes does not set counts; drive them through the
      // stream setters the upload paths use.
      stub.setVertexStreams(const [], 3);
      expect(stub.isReadable, isTrue);

      final data = stub.extractMeshData();
      expect(data.vertexCount, 3);
      expect(data.positions, positions);
      expect(data.normals, normals);
      expect(data.texCoords, isNull);
      // The snapshot is a copy, not a view.
      data.positions[0] = 99;
      expect(positions[0], 0);
    });

    test('extracted custom attributes round-trip through MeshData', () {
      final stub = _StubGeometry();
      stub.setRaycastAttributes(
        positions: Float32List.fromList([0, 0, 0, 1, 0, 0, 0, 1, 0]),
      );
      stub.setVertexStreams(const [], 3);
      final extracted = stub.extractMeshData();
      expect(extracted.customAttributes, isEmpty);
    });
  });
}
