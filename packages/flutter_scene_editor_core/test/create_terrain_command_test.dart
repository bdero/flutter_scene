// Creating a terrain. This is the step that was missing: there was no Terrain
// object, so there was nothing to select, so the sculpt button was always
// disabled and dragging over the ground moved it with the gizmo instead.
import 'package:flutter_scene_editor_core/flutter_scene_editor_core.dart';
// ignore: implementation_imports
import 'package:flutter_scene_editor_core/src/builtin_commands.dart'
    show createTerrainGeometry;
import 'package:scene/scene.dart';
import 'package:test/test.dart';

TerrainGeometrySpec only(SceneDocument doc) => doc.resources.values
    .whereType<GeometryResource>()
    .map((resource) => resource.procedural)
    .whereType<TerrainGeometrySpec>()
    .single;

void main() {
  test('it is registered, so the Add menu can reach it', () {
    expect(builtinCommands.any((c) => c.name == 'createTerrainGeometry'), true);
  });

  test('a new terrain is flat', () {
    // What a terrain is before anyone shapes it. Starting from a landscape
    // somebody else generated means undoing it first.
    final doc = SceneDocument();
    EditorSession(doc).run(createTerrainGeometry.name, {});
    expect(only(doc).amplitude, 0);
  });

  test('and big enough and fine enough to sculpt on', () {
    final doc = SceneDocument();
    EditorSession(doc).run(createTerrainGeometry.name, {});
    final terrain = only(doc);
    expect(terrain.width, 100);
    expect(terrain.depth, 100);
    // A cell a little under a metre: fine enough for a footpath, coarse
    // enough that the field is a payload rather than a download.
    expect(terrain.columns, 129);
    expect(terrain.rows, 129);
    expect(terrain.width / (terrain.columns - 1), lessThan(1.0));
  });

  test('the size and resolution can be asked for', () {
    final doc = SceneDocument();
    EditorSession(
      doc,
    ).run(createTerrainGeometry.name, {'size': 250.0, 'resolution': 257.0});
    final terrain = only(doc);
    expect(terrain.width, 250);
    expect(terrain.depth, 250);
    expect(terrain.columns, 257);
  });

  test('an amplitude still gets the noise terrain', () {
    // The command used to only make noise terrain; asking for it explicitly
    // has to keep working.
    final doc = SceneDocument();
    EditorSession(
      doc,
    ).run(createTerrainGeometry.name, {'amplitude': 12.0, 'seed': 99.0});
    expect(only(doc).amplitude, 12);
    expect(only(doc).seed, 99);
  });

  test('a grid too small to hold a hill is refused', () {
    final doc = SceneDocument();
    expect(
      () => EditorSession(
        doc,
      ).run(createTerrainGeometry.name, {'resolution': 1.0}),
      throwsA(isA<CommandException>()),
    );
  });

  test('a terrain with no size is refused', () {
    final doc = SceneDocument();
    expect(
      () => EditorSession(doc).run(createTerrainGeometry.name, {'size': 0.0}),
      throwsA(isA<CommandException>()),
    );
  });

  test('undo takes it away again', () {
    final doc = SceneDocument();
    final session = EditorSession(doc)..run(createTerrainGeometry.name, {});
    expect(doc.resources, isNotEmpty);
    session.undo();
    expect(doc.resources, isEmpty);
  });
}
