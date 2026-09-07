// The Terrain inspector section: the route by which terrain editing is
// actually reached. The bug this closes is that there wasn't one — the only
// way to arm a brush was a small unlabelled button in the corner of the scene
// view, so dragging over a terrain moved the object with the gizmo.

import 'package:flutter_scene_editor/src/inspector/terrain_section.dart';
import 'package:flutter_scene_editor/src/tools/terrain_tool_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scene/scene.dart';

/// A document with one node whose mesh is [procedural].
({SceneDocument doc, LocalId node}) sceneWith(ProceduralGeometry procedural) {
  final doc = SceneDocument();
  final geometry = doc.newId();
  doc.addResource(GeometryResource(geometry, procedural: procedural));
  final node = doc.newId();
  doc.addNode(
    NodeSpec(
      id: node,
      name: 'Object',
      components: [
        ComponentSpec(
          'mesh',
          properties: {'geometry': ResourceRefValue(geometry)},
        ),
      ],
    ),
    root: true,
  );
  return (doc: doc, node: node);
}

void main() {
  group('the toolbar', () {
    test('offers every tool Unity does, in its order', () {
      // A gap you can see is a roadmap; a missing button is a thing people
      // hunt for and conclude is broken.
      expect(terrainTools.map((entry) => entry.tool).toList(), [
        TerrainTool.neighbors,
        TerrainTool.paint,
        TerrainTool.trees,
        TerrainTool.details,
        TerrainTool.settings,
      ]);
    });

    test('every tool has a label and a tooltip', () {
      for (final entry in terrainTools) {
        expect(entry.label, isNotEmpty, reason: entry.tool.name);
        expect(entry.tip, isNotEmpty, reason: entry.tool.name);
      }
    });

    test('the toolbar covers the whole enum, so none is unreachable', () {
      expect(
        terrainTools.map((entry) => entry.tool).toSet(),
        TerrainTool.values.toSet(),
      );
    });
  });

  group('finding the terrain to edit', () {
    test('a terrain mesh is recognised', () {
      final scene = sceneWith(TerrainGeometrySpec(columns: 9, rows: 9));
      expect(terrainSpecOfDocument(scene.doc, scene.node), isNotNull);
    });

    test('an ordinary mesh is not', () {
      // The section has to stay off a cube, or every object grows terrain
      // tools it cannot use.
      final scene = sceneWith(PlaneGeometrySpec());
      expect(terrainSpecOfDocument(scene.doc, scene.node), isNull);
    });

    test('a node with no mesh is not', () {
      final doc = SceneDocument();
      final node = doc.newId();
      doc.addNode(NodeSpec(id: node, name: 'Empty'), root: true);
      expect(terrainSpecOfDocument(doc, node), isNull);
    });

    test('a mesh whose geometry resource is gone is not', () {
      // A dangling reference should read as "not terrain" rather than throw
      // while the inspector is drawing.
      final doc = SceneDocument();
      final node = doc.newId();
      doc.addNode(
        NodeSpec(
          id: node,
          name: 'Broken',
          components: [
            ComponentSpec(
              'mesh',
              properties: {'geometry': ResourceRefValue(doc.newId())},
            ),
          ],
        ),
        root: true,
      );
      expect(terrainSpecOfDocument(doc, node), isNull);
    });
  });
}
