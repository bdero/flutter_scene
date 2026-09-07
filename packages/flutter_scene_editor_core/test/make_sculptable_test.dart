// Turning a plane into sculptable ground. The conversion has to leave the
// shape alone: a plane that changes when you pick up the brush would be the
// tool editing before you did.
import 'package:flutter_scene_editor_core/flutter_scene_editor_core.dart';
// ignore: implementation_imports
import 'package:flutter_scene_editor_core/src/builtin_commands.dart'
    show makeTerrainSculptable;
import 'package:scene/scene.dart';
import 'package:test/test.dart';

({SceneDocument doc, LocalId id}) sceneWithPlane({
  int segmentsX = 1,
  int segmentsZ = 1,
}) {
  final doc = SceneDocument();
  final id = doc.newId();
  doc.addResource(
    GeometryResource(
      id,
      procedural: PlaneGeometrySpec(
        width: 12,
        depth: 8,
        segmentsX: segmentsX,
        segmentsZ: segmentsZ,
      ),
    ),
  );
  return (doc: doc, id: id);
}

TerrainGeometrySpec terrainIn(SceneDocument doc, LocalId id) =>
    (doc.resource(id)! as GeometryResource).procedural as TerrainGeometrySpec;

void main() {
  test('a plane becomes a flat terrain of the same size', () {
    final scene = sceneWithPlane();
    EditorSession(
      scene.doc,
    ).run(makeTerrainSculptable.name, {'resourceId': scene.id.toToken()});

    final terrain = terrainIn(scene.doc, scene.id);
    expect(terrain.width, 12);
    expect(terrain.depth, 8);
    // Flat, or converting would change what is on screen before the first
    // stroke.
    expect(terrain.amplitude, 0);
    expect(terrain.isSculpted, isFalse);
  });

  test('an unsubdivided plane gets a grid it can hold a shape in', () {
    // Two triangles have nowhere to put a hill.
    final scene = sceneWithPlane();
    EditorSession(
      scene.doc,
    ).run(makeTerrainSculptable.name, {'resourceId': scene.id.toToken()});
    final terrain = terrainIn(scene.doc, scene.id);
    expect(terrain.columns, greaterThan(2));
    expect(terrain.rows, greaterThan(2));
  });

  test('a subdivided plane keeps its own resolution', () {
    // Somebody chose that number; coarsening or refining it behind their back
    // would be the editor overruling them.
    final scene = sceneWithPlane(segmentsX: 20, segmentsZ: 10);
    EditorSession(
      scene.doc,
    ).run(makeTerrainSculptable.name, {'resourceId': scene.id.toToken()});
    final terrain = terrainIn(scene.doc, scene.id);
    expect(terrain.columns, 21);
    expect(terrain.rows, 11);
  });

  test('an explicit resolution wins over both', () {
    final scene = sceneWithPlane(segmentsX: 20, segmentsZ: 10);
    EditorSession(scene.doc).run(makeTerrainSculptable.name, {
      'resourceId': scene.id.toToken(),
      'resolution': 129,
    });
    final terrain = terrainIn(scene.doc, scene.id);
    expect(terrain.columns, 129);
    expect(terrain.rows, 129);
  });

  test('undo puts the plane back', () {
    final scene = sceneWithPlane();
    final session = EditorSession(scene.doc)
      ..run(makeTerrainSculptable.name, {'resourceId': scene.id.toToken()});
    session.undo();
    expect(
      (scene.doc.resource(scene.id)! as GeometryResource).procedural,
      isA<PlaneGeometrySpec>(),
    );
  });

  group('it refuses what it cannot convert', () {
    test('something already sculptable', () {
      final doc = SceneDocument();
      final id = doc.newId();
      doc.addResource(GeometryResource(id, procedural: TerrainGeometrySpec()));
      expect(
        () => EditorSession(
          doc,
        ).run(makeTerrainSculptable.name, {'resourceId': id.toToken()}),
        throwsA(isA<CommandException>()),
      );
    });

    test('a geometry that is not a plane', () {
      final doc = SceneDocument();
      final id = doc.newId();
      doc.addResource(
        GeometryResource(id, procedural: SphereGeometrySpec(radius: 1)),
      );
      expect(
        () => EditorSession(
          doc,
        ).run(makeTerrainSculptable.name, {'resourceId': id.toToken()}),
        throwsA(isA<CommandException>()),
      );
    });
  });
}
