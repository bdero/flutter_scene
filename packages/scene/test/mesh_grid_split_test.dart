import 'dart:typed_data';

import 'package:scene/scene.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

const _streams = [3, 3, 2, 2, 4, 4]; // floats per vertex per SoA stream
const _floatsPerVertex = 18;

/// A quad strip along +X (see the editor core's mesh_split_test for the
/// full derivation): vertices at integer (x, z in {0, 1}), position
/// (x, 0, z), every non-position float stamped `100 * vertex + slot`.
({Uint8List soa, Uint8List indices, int vertexCount}) _stripData(int quads) {
  final vertexCount = (quads + 1) * 2;
  final soa = Float32List(vertexCount * _floatsPerVertex);
  var offset = 0;
  for (var stream = 0; stream < _streams.length; stream++) {
    final width = _streams[stream];
    for (var v = 0; v < vertexCount; v++) {
      for (var c = 0; c < width; c++) {
        soa[offset + v * width + c] = stream == 0
            ? [v ~/ 2, 0, v % 2][c].toDouble()
            : 100.0 * v + stream * 4 + c;
      }
    }
    offset += vertexCount * width;
  }
  final indices = Uint16List(quads * 6);
  for (var q = 0; q < quads; q++) {
    final v00 = q * 2, v01 = q * 2 + 1, v10 = q * 2 + 2, v11 = q * 2 + 3;
    indices.setAll(q * 6, [v00, v10, v11, v00, v11, v01]);
  }
  return (
    soa: soa.buffer.asUint8List(),
    indices: indices.buffer.asUint8List(),
    vertexCount: vertexCount,
  );
}

LocalId _addStripNode(SceneDocument doc, {required String name}) {
  final data = _stripData(4);
  final vertexPayload = doc.addPayload(
    PayloadSpec(
      doc.newId(),
      encoding: PayloadEncoding.vertexBuffer,
      layout: 'unskinned_soa_uv1_tangent',
      bytes: data.soa,
      length: data.soa.length,
    ),
  );
  final indexPayload = doc.addPayload(
    PayloadSpec(
      doc.newId(),
      encoding: PayloadEncoding.indexBuffer,
      format: 'uint16',
      bytes: data.indices,
      length: data.indices.length,
    ),
  );
  final geometry = GeometryResource(
    doc.newId(),
    vertices: vertexPayload.id,
    indices: indexPayload.id,
  );
  doc.resources[geometry.id] = geometry;
  final node = doc.createNode(name: name, root: true);
  node.components.add(
    ComponentSpec(
      'mesh',
      properties: {'geometry': ResourceRefValue(geometry.id)},
    ),
  );
  return node.id;
}

void main() {
  group('splitTriangleMeshByGrid', () {
    test('bins whole triangles into deterministic cells', () {
      final data = _stripData(4);
      final cells = splitTriangleMeshByGrid(
        vertexBytes: data.soa,
        layout: 'unskinned_soa_uv1_tangent',
        indices: Uint16List.sublistView(data.indices),
        worldTransform: Matrix4.identity(),
        cellSize: 2.0,
      );
      expect(cells, hasLength(2));
      expect([for (final c in cells) c.suffix], ['x0_z0', 'x1_z0']);
      for (final cell in cells) {
        expect(cell.vertexBytes.length ~/ 72, 6);
        expect(cell.indexFormat, 'uint16');
        expect(Uint16List.sublistView(cell.indexBytes), hasLength(12));
        expect(cell.boundsMax.x - cell.boundsMin.x, 2.0);
      }
    });

    test('the world transform shifts cell assignment', () {
      final data = _stripData(4);
      final cells = splitTriangleMeshByGrid(
        vertexBytes: data.soa,
        layout: 'unskinned_soa_uv1_tangent',
        indices: Uint16List.sublistView(data.indices),
        worldTransform: Matrix4.translationValues(2, 0, 0),
        cellSize: 2.0,
      );
      expect([for (final c in cells) c.suffix], ['x1_z0', 'x2_z0']);
    });

    test('rejects unknown layouts and bad cell sizes', () {
      final data = _stripData(1);
      expect(
        () => splitTriangleMeshByGrid(
          vertexBytes: data.soa,
          layout: 'skinned_uv1_tangent',
          worldTransform: Matrix4.identity(),
          cellSize: 1.0,
        ),
        throwsArgumentError,
      );
      expect(
        () => splitTriangleMeshByGrid(
          vertexBytes: data.soa,
          layout: 'unskinned_soa_uv1_tangent',
          worldTransform: Matrix4.identity(),
          cellSize: 0.0,
        ),
        throwsArgumentError,
      );
    });
  });

  group('applyMeshSplitHints', () {
    test('splits a hinted node in place and strips the hint', () {
      final doc = SceneDocument(allocator: IdAllocator(session: 1));
      final id = _addStripNode(doc, name: 'Ground-split2');
      final payloadsBefore = doc.payloads.length;

      expect(applyMeshSplitHints(doc), 1);

      final node = doc.nodes[id]!;
      expect(node.name, 'Ground');
      expect(node.components.where((c) => c.type == 'mesh'), isEmpty);
      expect(node.children, hasLength(2));
      expect(
        [for (final c in node.children) doc.nodes[c]!.name],
        ['Ground_x0_z0', 'Ground_x1_z0'],
      );
      // Source vertex + index payloads removed, 2 cells x 2 payloads added.
      expect(doc.payloads.length, payloadsBefore - 2 + 4);
      // Idempotent: no hint remains, so a second pass is a no-op.
      expect(applyMeshSplitHints(doc), 0);
    });

    test('supports fractional cell sizes in the hint', () {
      final doc = SceneDocument(allocator: IdAllocator(session: 1));
      final id = _addStripNode(doc, name: 'Ground-split0.5');
      expect(applyMeshSplitHints(doc), 1);
      // 4 quads at 0.5m cells, each quad's two triangle centroids land in
      // different (x, z) half-cells: 8 occupied cells.
      expect(doc.nodes[id]!.children, hasLength(8));
    });

    test('an unsplittable hinted node keeps its mesh and name', () {
      final doc = SceneDocument(allocator: IdAllocator(session: 1));
      final id = _addStripNode(doc, name: 'Rig-split2');
      doc.nodes[id]!.skin = doc.newId();
      expect(applyMeshSplitHints(doc), 0);
      expect(doc.nodes[id]!.name, 'Rig-split2');
      expect(doc.nodes[id]!.components.single.type, 'mesh');
    });

    test('a single-cell hinted node just loses the hint', () {
      final doc = SceneDocument(allocator: IdAllocator(session: 1));
      final id = _addStripNode(doc, name: 'Small-split100');
      expect(applyMeshSplitHints(doc), 1);
      expect(doc.nodes[id]!.name, 'Small');
      expect(doc.nodes[id]!.components.single.type, 'mesh');
      expect(doc.nodes[id]!.children, isEmpty);
    });
  });
}
