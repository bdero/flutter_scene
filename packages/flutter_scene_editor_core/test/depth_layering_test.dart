// The checkDepthLayering query, over documents built the way a tool builds
// them: commands that create geometry, materials, and mesh nodes.
import 'package:flutter_scene_editor_core/flutter_scene_editor_core.dart';
import 'package:scene/scene.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

LocalId _created(Transaction transaction) => transaction.records.first.targetId;

LocalId _cuboid(EditorSession s, Vector3 extents) => _created(
  s.run('createCuboidGeometry', {
    'extents': {'x': extents.x, 'y': extents.y, 'z': extents.z},
  }),
);

LocalId _material(EditorSession s, {int? layer}) => _created(
  s.run('createMaterial', {
    'type': 'unlit',
    if (layer != null) 'properties': {'depthLayer': layer},
  }),
);

LocalId _meshNode(
  EditorSession s,
  String name,
  LocalId geometry,
  LocalId material,
  Vector3 position,
) {
  final node = _created(s.run('createNode', {'name': name}));
  s.run('setNodeTransform', {
    'nodeId': node.toToken(),
    'translation': {'x': position.x, 'y': position.y, 'z': position.z},
  });
  s.run('addComponent', {
    'nodeId': node.toToken(),
    'componentType': 'mesh',
    'properties': {
      'geometry': {r'$resource': geometry.toToken()},
      'material': {r'$resource': material.toToken()},
    },
  });
  return node;
}

void main() {
  test('finds barriers longer than their spacing, with the fix', () {
    final session = EditorSession.empty();
    final piece = _cuboid(session, Vector3(0.5, 0.9, 8.4));
    final red = _material(session);
    final white = _material(session);
    _meshNode(session, 'red_0', piece, red, Vector3(0, 0.45, 0));
    _meshNode(session, 'white_1', piece, white, Vector3(0, 0.45, 8));
    _meshNode(session, 'red_2', piece, red, Vector3(0, 0.45, 16));

    final result = session.ask('checkDepthLayering');
    final overlaps = (result.body['overlaps'] as List)
        .cast<Map<String, Object?>>();
    // Two joints, each with side, top, and bottom faces in one plane.
    expect(result.body['overlapCount'], 8);
    final side = overlaps.firstWhere(
      (o) => ((o['normal'] as Map)['x'] as double).abs() > 0.9,
    );
    expect(side['area'] as double, closeTo(0.4 * 0.9, 1e-6));
    expect(side['hint'], contains('make them 8.00 m long'));
    expect({
      ...overlaps.map((o) => o['pathA']),
      ...overlaps.map((o) => o['pathB']),
    }, containsAll(['red_0', 'white_1', 'red_2']));
    expect(result.body['summary'], contains('flicker (z-fighting)'));
  });

  test('abutting pieces, one material, and separate layers do not fight', () {
    final session = EditorSession.empty();
    final abutting = _cuboid(session, Vector3(0.5, 0.9, 8.0));
    final a = _material(session);
    final b = _material(session);
    _meshNode(session, 'a', abutting, a, Vector3(0, 0, 0));
    _meshNode(session, 'b', abutting, b, Vector3(0, 0, 8));

    final long = _cuboid(session, Vector3(0.5, 0.9, 8.4));
    final shared = _material(session);
    _meshNode(session, 'c', long, shared, Vector3(10, 0, 0));
    _meshNode(session, 'd', long, shared, Vector3(10, 0, 8));

    final base = _material(session);
    final overlay = _material(session, layer: 1);
    _meshNode(session, 'wall', long, base, Vector3(20, 0, 0));
    _meshNode(session, 'screen', long, overlay, Vector3(20, 0, 8));

    expect(session.ask('checkDepthLayering').body['overlapCount'], 0);
  });

  test('hidden nodes and planes', () {
    final session = EditorSession.empty();
    final plane = GeometryResource(
      session.document.newId(),
      procedural: PlaneGeometrySpec(width: 4, depth: 4),
    );
    session.document.resources[plane.id] = plane;
    final ground = _material(session);
    final patch = _material(session);
    _meshNode(session, 'ground', plane.id, ground, Vector3(0, 0, 0));
    final hidden = _meshNode(
      session,
      'patch',
      plane.id,
      patch,
      Vector3(1, 0, 1),
    );

    final result = session.ask('checkDepthLayering');
    expect(result.body['overlapCount'], 1);
    final overlap = (result.body['overlaps'] as List).single as Map;
    expect(overlap['area'] as double, closeTo(9.0, 1e-6));
    expect((overlap['normal'] as Map)['y'], closeTo(1.0, 1e-9));

    session.run('setNodeVisible', {
      'nodeId': hidden.toToken(),
      'visible': false,
    });
    expect(session.ask('checkDepthLayering').body['overlapCount'], 0);
  });
}
