// The command that persists a sculpting stroke. One stroke is one command,
// so undo restores the heightmap as it was before the stroke began.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_scene_editor_core/flutter_scene_editor_core.dart';
// ignore: implementation_imports
import 'package:flutter_scene_editor_core/src/builtin_commands.dart'
    show setTerrainHeights;
import 'package:scene/scene.dart';
import 'package:test/test.dart';

const _columns = 5;
const _rows = 4;

/// A document holding one generated terrain, plus its resource id.
({SceneDocument doc, LocalId terrain}) sceneWithTerrain() {
  final doc = SceneDocument();
  final id = doc.newId();
  doc.addResource(
    GeometryResource(
      id,
      procedural: TerrainGeometrySpec(columns: _columns, rows: _rows),
    ),
  );
  return (doc: doc, terrain: id);
}

String samples(double fill) => base64Encode(
  Uint8List.view(
    Float32List.fromList(List<double>.filled(_columns * _rows, fill)).buffer,
  ),
);

TerrainGeometrySpec terrainIn(SceneDocument doc, LocalId id) =>
    (doc.resource(id)! as GeometryResource).procedural as TerrainGeometrySpec;

void main() {
  test('the first stroke mints a heightmap and points the terrain at it', () {
    final scene = sceneWithTerrain();
    expect(terrainIn(scene.doc, scene.terrain).isSculpted, isFalse);

    final session = EditorSession(scene.doc);
    session.run(setTerrainHeights.name, {
      'resourceId': scene.terrain.toToken(),
      'heights': samples(3),
    });

    final terrain = terrainIn(scene.doc, scene.terrain);
    expect(terrain.isSculpted, isTrue);
    final payload = scene.doc.payload(terrain.heights!)!;
    expect(payload.encoding, PayloadEncoding.floats);
    expect(payload.bytes!.lengthInBytes, _columns * _rows * 4);
  });

  test('a later stroke replaces the bytes without minting another', () {
    final scene = sceneWithTerrain();
    final session = EditorSession(scene.doc);
    session.run(setTerrainHeights.name, {
      'resourceId': scene.terrain.toToken(),
      'heights': samples(1),
    });
    final first = terrainIn(scene.doc, scene.terrain).heights;

    session.run(setTerrainHeights.name, {
      'resourceId': scene.terrain.toToken(),
      'heights': samples(2),
    });

    expect(terrainIn(scene.doc, scene.terrain).heights, first);
    expect(scene.doc.payloads, hasLength(1));
  });

  test('undo restores the ground as it was before the stroke', () {
    final scene = sceneWithTerrain();
    final session = EditorSession(scene.doc);
    session.run(setTerrainHeights.name, {
      'resourceId': scene.terrain.toToken(),
      'heights': samples(1),
    });
    final payloadId = terrainIn(scene.doc, scene.terrain).heights!;

    session.run(setTerrainHeights.name, {
      'resourceId': scene.terrain.toToken(),
      'heights': samples(7),
    });
    session.undo();

    final bytes = scene.doc.payload(payloadId)!.bytes!;
    final heights = bytes.buffer.asFloat32List(bytes.offsetInBytes);
    expect(heights.first, 1, reason: 'the earlier stroke is what remains');
  });

  test('undoing the first stroke leaves a generated terrain again', () {
    // The stroke created the heightmap, so undoing it has to take the
    // reference off the terrain too, not just empty the payload.
    final scene = sceneWithTerrain();
    final session = EditorSession(scene.doc);
    session.run(setTerrainHeights.name, {
      'resourceId': scene.terrain.toToken(),
      'heights': samples(4),
    });
    session.undo();

    expect(terrainIn(scene.doc, scene.terrain).isSculpted, isFalse);
    expect(scene.doc.payloads, isEmpty);
  });

  group('it refuses what it cannot apply', () {
    test('a sample count that does not match the grid', () {
      final scene = sceneWithTerrain();
      final session = EditorSession(scene.doc);
      expect(
        () => session.run(setTerrainHeights.name, {
          'resourceId': scene.terrain.toToken(),
          'heights': base64Encode(Uint8List(8)),
        }),
        throwsA(isA<CommandException>()),
      );
    });

    test('a resource that is not a terrain', () {
      final doc = SceneDocument();
      final id = doc.newId();
      doc.addResource(
        GeometryResource(id, procedural: SphereGeometrySpec(radius: 1)),
      );
      final session = EditorSession(doc);
      expect(
        () => session.run(setTerrainHeights.name, {
          'resourceId': id.toToken(),
          'heights': samples(1),
        }),
        throwsA(isA<CommandException>()),
      );
    });
  });
}
