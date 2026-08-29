import 'dart:typed_data';

import 'package:scene/scene.dart';
import 'package:flutter_scene_editor_core/src/builtin_commands.dart';
import 'package:flutter_scene_editor_core/src/change.dart';
import 'package:flutter_scene_editor_core/src/command.dart';
import 'package:flutter_scene_editor_core/src/history.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

({SceneDocument doc, EditHistory history, CommandRegistry registry})
_harness() {
  final doc = SceneDocument(allocator: IdAllocator(session: 1));
  final registry = CommandRegistry();
  registerBuiltinCommands(registry);
  return (
    doc: doc,
    history: EditHistory(DocumentMutator(doc)),
    registry: registry,
  );
}

Transaction _run(
  ({SceneDocument doc, EditHistory history, CommandRegistry registry}) h,
  String command,
  Map<String, Object?> params,
) {
  final entry = h.registry.lookup(command)!;
  final tx = entry.execute(CommandContext(h.doc), params);
  h.history.commit(tx);
  return tx;
}

const _streams = [3, 3, 2, 2, 4, 4]; // floats per vertex per SoA stream
const _floatsPerVertex = 18;

/// A quad strip along +X: vertices at integer (x, z in {0, 1}) with position
/// (x, 0, z); vertex index = x * 2 + z. Every non-position float is stamped
/// `100 * vertex + slot` so remapped data is attributable to its source
/// vertex exactly.
({Uint8List soa, Uint8List interleaved, Uint8List indices, int vertexCount})
_stripData(int quads) {
  final vertexCount = (quads + 1) * 2;
  double stamp(int vertex, int slot) => 100.0 * vertex + slot;

  final soa = Float32List(vertexCount * _floatsPerVertex);
  var offset = 0;
  for (var stream = 0; stream < _streams.length; stream++) {
    final width = _streams[stream];
    for (var v = 0; v < vertexCount; v++) {
      for (var c = 0; c < width; c++) {
        final value = stream == 0
            ? [v ~/ 2, 0, v % 2][c].toDouble()
            : stamp(v, stream * 4 + c);
        soa[offset + v * width + c] = value;
      }
    }
    offset += vertexCount * width;
  }

  final interleaved = Float32List(vertexCount * _floatsPerVertex);
  for (var v = 0; v < vertexCount; v++) {
    var base = v * _floatsPerVertex;
    for (var stream = 0; stream < _streams.length; stream++) {
      final width = _streams[stream];
      for (var c = 0; c < width; c++) {
        interleaved[base + c] = stream == 0
            ? [v ~/ 2, 0, v % 2][c].toDouble()
            : stamp(v, stream * 4 + c);
      }
      base += width;
    }
  }

  final indices = Uint16List(quads * 6);
  for (var q = 0; q < quads; q++) {
    final v00 = q * 2, v01 = q * 2 + 1, v10 = q * 2 + 2, v11 = q * 2 + 3;
    indices.setAll(q * 6, [v00, v10, v11, v00, v11, v01]);
  }
  return (
    soa: soa.buffer.asUint8List(),
    interleaved: interleaved.buffer.asUint8List(),
    indices: indices.buffer.asUint8List(),
    vertexCount: vertexCount,
  );
}

/// Adds a strip-mesh node to [doc] and returns its id.
LocalId _addStripNode(
  SceneDocument doc, {
  required int quads,
  required String layout,
  bool indexed = true,
  String name = 'Ground',
  Vector3? translation,
}) {
  final data = _stripData(quads);
  final vertexPayload = doc.addPayload(
    PayloadSpec(
      doc.newId(),
      encoding: PayloadEncoding.vertexBuffer,
      layout: layout,
      bytes: layout.contains('soa') ? data.soa : data.interleaved,
      length: data.vertexCount * _floatsPerVertex * 4,
    ),
  );
  PayloadSpec? indexPayload;
  if (indexed) {
    indexPayload = doc.addPayload(
      PayloadSpec(
        doc.newId(),
        encoding: PayloadEncoding.indexBuffer,
        format: 'uint16',
        bytes: data.indices,
        length: data.indices.length,
      ),
    );
  }
  final geometry = GeometryResource(
    doc.newId(),
    vertices: vertexPayload.id,
    indices: indexPayload?.id,
    legacyWinding: true,
  );
  doc.resources[geometry.id] = geometry;
  final material = MaterialResource(doc.newId(), type: 'physicallyBased');
  doc.resources[material.id] = material;
  final node = doc.createNode(name: name, root: true);
  if (translation != null) {
    node.transform = TrsTransform(translation: translation);
  }
  node.components.add(
    ComponentSpec(
      'mesh',
      properties: {
        'geometry': ResourceRefValue(geometry.id),
        'material': ResourceRefValue(material.id),
      },
    ),
  );
  return node.id;
}

/// The float slab of one child's vertex payload, de-interleaved back into
/// per-vertex rows for comparison.
List<List<double>> _childVertexRows(SceneDocument doc, LocalId childId) {
  final node = doc.nodes[childId]!;
  final mesh = node.components.singleWhere((c) => c.type == 'mesh');
  final geometry =
      doc.resources[(mesh.properties['geometry'] as ResourceRefValue).id]
          as GeometryResource;
  final payload = doc.payloads[geometry.vertices]!;
  final floats = Float32List.sublistView(payload.bytes!);
  final vertexCount = floats.length ~/ _floatsPerVertex;
  final rows = <List<double>>[];
  if (payload.layout!.contains('soa')) {
    var offset = 0;
    final byVertex = List.generate(vertexCount, (_) => <double>[]);
    for (final width in _streams) {
      for (var v = 0; v < vertexCount; v++) {
        for (var c = 0; c < width; c++) {
          byVertex[v].add(floats[offset + v * width + c]);
        }
      }
      offset += vertexCount * width;
    }
    rows.addAll(byVertex);
  } else {
    for (var v = 0; v < vertexCount; v++) {
      rows.add(
        floats.sublist(v * _floatsPerVertex, (v + 1) * _floatsPerVertex),
      );
    }
  }
  return rows;
}

List<int> _childIndices(SceneDocument doc, LocalId childId) {
  final node = doc.nodes[childId]!;
  final mesh = node.components.singleWhere((c) => c.type == 'mesh');
  final geometry =
      doc.resources[(mesh.properties['geometry'] as ResourceRefValue).id]
          as GeometryResource;
  final payload = doc.payloads[geometry.indices!]!;
  return payload.format == 'uint32'
      ? Uint32List.sublistView(payload.bytes!)
      : Uint16List.sublistView(payload.bytes!);
}

void main() {
  for (final layout in ['unskinned_soa_uv1_tangent', 'unskinned_uv1_tangent']) {
    test('splits a $layout strip into world-grid cells, byte-exact', () {
      final h = _harness();
      // 4 quads spanning x in [0, 4]; cellSize 2 bins them into x0 and x1.
      final id = _addStripNode(h.doc, quads: 4, layout: layout);
      final sourceRows = _childVertexRows(h.doc, id);

      _run(h, 'splitMeshByGrid', {
        'nodeIds': [id.toToken()],
        'cellSize': 2.0,
      });

      final node = h.doc.nodes[id]!;
      expect(node.components.where((c) => c.type == 'mesh'), isEmpty);
      expect(node.children, hasLength(2));
      final names = [for (final c in node.children) h.doc.nodes[c]!.name];
      expect(names, ['Ground_x0_z0', 'Ground_x1_z0']);

      for (final childId in node.children) {
        final child = h.doc.nodes[childId]!;
        final rows = _childVertexRows(h.doc, childId);
        final indices = _childIndices(h.doc, childId);
        // 2 quads per cell, shared interior vertex column remapped, border
        // column duplicated into both cells: 6 vertices, 12 indices.
        expect(rows, hasLength(6));
        expect(indices, hasLength(12));
        // Every remapped vertex matches its source row byte-for-byte
        // (position identifies the source vertex; the stamps prove every
        // other attribute rode along).
        for (final row in rows) {
          final sourceVertex = (row[0] * 2 + row[2]).round();
          expect(row, sourceRows[sourceVertex]);
        }
        // The child's mesh kept the source material reference.
        final mesh = child.components.singleWhere((c) => c.type == 'mesh');
        expect(mesh.properties['material'], isA<ResourceRefValue>());
        // Bounds cover the cell's actual triangles.
        final geometry =
            h.doc.resources[(mesh.properties['geometry'] as ResourceRefValue)
                    .id]
                as GeometryResource;
        expect(geometry.bounds!.max.x - geometry.bounds!.min.x, 2.0);
        expect(geometry.legacyWinding, isTrue);
      }
    });
  }

  test('binning uses world space, so a translated node shifts cells', () {
    final h = _harness();
    // Translated by 2 along x, the same strip occupies x in [2, 6]: cells
    // x1 and x2 on a world-anchored grid.
    final id = _addStripNode(
      h.doc,
      quads: 4,
      layout: 'unskinned_soa_uv1_tangent',
      translation: Vector3(2, 0, 0),
    );
    _run(h, 'splitMeshByGrid', {
      'nodeIds': [id.toToken()],
      'cellSize': 2.0,
    });
    final names = [
      for (final c in h.doc.nodes[id]!.children) h.doc.nodes[c]!.name,
    ];
    expect(names, ['Ground_x1_z0', 'Ground_x2_z0']);
  });

  test('non-indexed geometry splits via implicit indices', () {
    final h = _harness();
    // Without shared indices the strip data is not a valid soup, so build a
    // 2-quad strip and split at cellSize 1 (one quad per cell); the implicit
    // triples still bin by centroid.
    final id = _addStripNode(
      h.doc,
      quads: 2,
      layout: 'unskinned_soa_uv1_tangent',
      indexed: false,
    );
    // 6 vertices = 2 triangles; centroids at x 1/3 and x 5/3 with cell 1.
    _run(h, 'splitMeshByGrid', {
      'nodeIds': [id.toToken()],
      'cellSize': 1.0,
    });
    final children = h.doc.nodes[id]!.children;
    expect(children, hasLength(2));
    for (final childId in children) {
      expect(_childIndices(h.doc, childId), hasLength(3));
    }
  });

  test('sole-user source geometry and payloads are removed, shared kept', () {
    final h = _harness();
    final soleId = _addStripNode(
      h.doc,
      quads: 4,
      layout: 'unskinned_soa_uv1_tangent',
      name: 'Sole',
    );
    final payloadsBefore = h.doc.payloads.length;
    _run(h, 'splitMeshByGrid', {
      'nodeIds': [soleId.toToken()],
      'cellSize': 2.0,
    });
    // Old vertex + index payloads removed, 2 cells x 2 payloads added.
    expect(h.doc.payloads.length, payloadsBefore - 2 + 4);

    // A geometry shared by a second node survives the other node's split.
    final sharedA = _addStripNode(
      h.doc,
      quads: 4,
      layout: 'unskinned_soa_uv1_tangent',
      name: 'SharedA',
    );
    final meshA = h.doc.nodes[sharedA]!.components.single;
    final sharedGeometry =
        (meshA.properties['geometry'] as ResourceRefValue).id;
    final other = h.doc.createNode(name: 'SharedB', root: true);
    other.components.add(
      ComponentSpec(
        'mesh',
        properties: {'geometry': ResourceRefValue(sharedGeometry)},
      ),
    );
    _run(h, 'splitMeshByGrid', {
      'nodeIds': [sharedA.toToken()],
      'cellSize': 2.0,
    });
    expect(h.doc.resources[sharedGeometry], isNotNull);
  });

  test('undo restores the document exactly', () {
    final h = _harness();
    final id = _addStripNode(
      h.doc,
      quads: 4,
      layout: 'unskinned_soa_uv1_tangent',
    );
    final nodesBefore = Map.of(h.doc.nodes);
    final resourcesBefore = Map.of(h.doc.resources);
    final payloadsBefore = Map.of(h.doc.payloads);
    final childrenBefore = List.of(h.doc.nodes[id]!.children);
    final componentsBefore = List.of(h.doc.nodes[id]!.components);

    _run(h, 'splitMeshByGrid', {
      'nodeIds': [id.toToken()],
      'cellSize': 2.0,
    });
    expect(h.doc.nodes.length, greaterThan(nodesBefore.length));

    h.history.undo();
    expect(h.doc.nodes.keys.toSet(), nodesBefore.keys.toSet());
    expect(h.doc.resources.keys.toSet(), resourcesBefore.keys.toSet());
    expect(h.doc.payloads.keys.toSet(), payloadsBefore.keys.toSet());
    expect(h.doc.nodes[id]!.children, childrenBefore);
    expect(h.doc.nodes[id]!.components, componentsBefore);
  });

  test('a mesh landing in one cell is left untouched', () {
    final h = _harness();
    final id = _addStripNode(
      h.doc,
      quads: 2,
      layout: 'unskinned_soa_uv1_tangent',
    );
    final tx = _run(h, 'splitMeshByGrid', {
      'nodeIds': [id.toToken()],
      'cellSize': 100.0,
    });
    expect(tx.isEmpty, isTrue);
    expect(h.doc.nodes[id]!.components.single.type, 'mesh');
  });

  test('rejects skinned nodes, procedural geometry, and missing meshes', () {
    final h = _harness();
    final entry = h.registry.lookup('splitMeshByGrid')!;

    final plain = h.doc.createNode(name: 'Empty', root: true);
    expect(
      () => entry.execute(CommandContext(h.doc), {
        'nodeIds': [plain.id.toToken()],
        'cellSize': 2.0,
      }),
      throwsA(isA<CommandException>()),
    );

    final skinnedId = _addStripNode(
      h.doc,
      quads: 2,
      layout: 'unskinned_soa_uv1_tangent',
      name: 'Skinned',
    );
    h.doc.nodes[skinnedId]!.skin = h.doc.newId();
    expect(
      () => entry.execute(CommandContext(h.doc), {
        'nodeIds': [skinnedId.toToken()],
        'cellSize': 2.0,
      }),
      throwsA(isA<CommandException>()),
    );

    final procedural = GeometryResource(
      h.doc.newId(),
      procedural: CuboidGeometrySpec(extents: Vector3(1, 1, 1)),
    );
    h.doc.resources[procedural.id] = procedural;
    final proceduralNode = h.doc.createNode(name: 'Cube', root: true);
    proceduralNode.components.add(
      ComponentSpec(
        'mesh',
        properties: {'geometry': ResourceRefValue(procedural.id)},
      ),
    );
    expect(
      () => entry.execute(CommandContext(h.doc), {
        'nodeIds': [proceduralNode.id.toToken()],
        'cellSize': 2.0,
      }),
      throwsA(isA<CommandException>()),
    );
  });
}
