// The command that persists a painting stroke. The sibling of the sculpting
// one, and the same bargain: one stroke is one command, so undo restores the
// control map as it was before the stroke began.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_scene_editor_core/flutter_scene_editor_core.dart';
// ignore: implementation_imports
import 'package:flutter_scene_editor_core/src/builtin_commands.dart'
    show setTerrainHeights, setTerrainSplat;
import 'package:scene/scene.dart';
import 'package:vector_math/vector_math.dart';
import 'package:test/test.dart';

const _texels = 8;

({SceneDocument doc, LocalId terrain}) sceneWithTerrain() {
  final doc = SceneDocument();
  final id = doc.newId();
  doc.addResource(
    GeometryResource(
      id,
      procedural: TerrainGeometrySpec(
        columns: 5,
        rows: 4,
        splatColumns: _texels,
        splatRows: _texels,
      ),
    ),
  );
  return (doc: doc, terrain: id);
}

/// A control map where every texel is entirely [layer].
String controlMap(int layer, {int columns = _texels, int rows = _texels}) {
  final bytes = Uint8List(columns * rows * 4);
  for (var texel = 0; texel < columns * rows; texel++) {
    bytes[texel * 4 + layer] = 255;
  }
  return base64Encode(bytes);
}

TerrainGeometrySpec terrainIn(SceneDocument doc, LocalId id) =>
    (doc.resource(id)! as GeometryResource).procedural as TerrainGeometrySpec;

void main() {
  test('the first stroke mints a control map and points the terrain at it', () {
    final scene = sceneWithTerrain();
    expect(terrainIn(scene.doc, scene.terrain).isPainted, isFalse);

    final session = EditorSession(scene.doc);
    session.run(setTerrainSplat.name, {
      'resourceId': scene.terrain.toToken(),
      'splat': controlMap(1),
    });

    final terrain = terrainIn(scene.doc, scene.terrain);
    expect(terrain.isPainted, isTrue);
    final payload = scene.doc.payload(terrain.splat!)!;
    expect(payload.encoding, PayloadEncoding.image);
    // The payload is the texture the shader samples, so it says so.
    expect(payload.format, 'rgba8');
    expect(payload.width, _texels);
    expect(payload.height, _texels);
  });

  test('a later stroke replaces the bytes in the map it already has', () {
    final scene = sceneWithTerrain();
    final session = EditorSession(scene.doc);
    session.run(setTerrainSplat.name, {
      'resourceId': scene.terrain.toToken(),
      'splat': controlMap(1),
    });
    final first = terrainIn(scene.doc, scene.terrain).splat;

    session.run(setTerrainSplat.name, {
      'resourceId': scene.terrain.toToken(),
      'splat': controlMap(2),
    });
    expect(terrainIn(scene.doc, scene.terrain).splat, first);
    expect(scene.doc.payload(first!)!.bytes![2], 255);
  });

  test('undo restores the painting as it was before the stroke', () {
    final scene = sceneWithTerrain();
    final session = EditorSession(scene.doc);
    session.run(setTerrainSplat.name, {
      'resourceId': scene.terrain.toToken(),
      'splat': controlMap(1),
    });
    session.run(setTerrainSplat.name, {
      'resourceId': scene.terrain.toToken(),
      'splat': controlMap(3),
    });

    session.undo();
    final id = terrainIn(scene.doc, scene.terrain).splat!;
    expect(scene.doc.payload(id)!.bytes![1], 255);
  });

  test('undoing the first stroke leaves the terrain unpainted again', () {
    final scene = sceneWithTerrain();
    final session = EditorSession(scene.doc);
    session.run(setTerrainSplat.name, {
      'resourceId': scene.terrain.toToken(),
      'splat': controlMap(1),
    });
    session.undo();
    expect(terrainIn(scene.doc, scene.terrain).isPainted, isFalse);
  });

  test('painting and sculpting do not overwrite each other', () {
    // Both commands write a new spec for the terrain, and either one dropping
    // the other's payload reference would lose that work silently -- a save
    // later, when there is nothing left to undo.
    final scene = sceneWithTerrain();
    final session = EditorSession(scene.doc);
    session.run(setTerrainSplat.name, {
      'resourceId': scene.terrain.toToken(),
      'splat': controlMap(1),
    });
    final painted = terrainIn(scene.doc, scene.terrain).splat;

    session.run(setTerrainHeights.name, {
      'resourceId': scene.terrain.toToken(),
      'heights': base64Encode(
        Uint8List.view(Float32List.fromList(List.filled(5 * 4, 1.5)).buffer),
      ),
    });

    final terrain = terrainIn(scene.doc, scene.terrain);
    expect(terrain.isSculpted, isTrue);
    expect(terrain.splat, painted, reason: 'sculpting kept the painting');
    expect(terrain.splatColumns, _texels);
  });

  test('sculpting first, then painting, keeps the heightmap', () {
    final scene = sceneWithTerrain();
    final session = EditorSession(scene.doc);
    session.run(setTerrainHeights.name, {
      'resourceId': scene.terrain.toToken(),
      'heights': base64Encode(
        Uint8List.view(Float32List.fromList(List.filled(5 * 4, 2.0)).buffer),
      ),
    });
    final heights = terrainIn(scene.doc, scene.terrain).heights;

    session.run(setTerrainSplat.name, {
      'resourceId': scene.terrain.toToken(),
      'splat': controlMap(2),
    });
    expect(terrainIn(scene.doc, scene.terrain).heights, heights);
  });

  test('the first stroke may set the control-map resolution', () {
    final scene = sceneWithTerrain();
    final session = EditorSession(scene.doc);
    session.run(setTerrainSplat.name, {
      'resourceId': scene.terrain.toToken(),
      'splat': controlMap(0, columns: 16, rows: 4),
      'columns': 16,
      'rows': 4,
    });
    final terrain = terrainIn(scene.doc, scene.terrain);
    expect(terrain.splatColumns, 16);
    expect(terrain.splatRows, 4);
  });

  test('a map that is the wrong size is refused, not written', () {
    // A short map would paint whatever it ran out on across the rest of the
    // ground, and only on the next load.
    final scene = sceneWithTerrain();
    final session = EditorSession(scene.doc);
    expect(
      () => session.run(setTerrainSplat.name, {
        'resourceId': scene.terrain.toToken(),
        'splat': controlMap(0, columns: 4, rows: 4),
      }),
      throwsA(isA<CommandException>()),
    );
    expect(terrainIn(scene.doc, scene.terrain).isPainted, isFalse);
  });

  test('repainting at a different resolution is refused', () {
    // Resampling a painting is a real operation with real choices in it;
    // silently reinterpreting the bytes at a new size is not that.
    final scene = sceneWithTerrain();
    final session = EditorSession(scene.doc);
    session.run(setTerrainSplat.name, {
      'resourceId': scene.terrain.toToken(),
      'splat': controlMap(1),
    });
    expect(
      () => session.run(setTerrainSplat.name, {
        'resourceId': scene.terrain.toToken(),
        'splat': controlMap(1, columns: 16, rows: 16),
        'columns': 16,
        'rows': 16,
      }),
      throwsA(isA<CommandException>()),
    );
  });

  test('a geometry that is not a terrain is refused', () {
    final doc = SceneDocument();
    final id = doc.newId();
    doc.addResource(
      GeometryResource(
        id,
        procedural: CuboidGeometrySpec(extents: Vector3.all(1)),
      ),
    );
    final session = EditorSession(doc);
    expect(
      () => session.run(setTerrainSplat.name, {
        'resourceId': id.toToken(),
        'splat': controlMap(0),
      }),
      throwsA(isA<CommandException>()),
    );
  });
}
