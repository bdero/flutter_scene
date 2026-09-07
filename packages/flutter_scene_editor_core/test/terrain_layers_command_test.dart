// Giving a painted terrain something to draw the painting with. Painting
// writes a control map; nothing shows it until the terrain is using the
// terrain material with that map bound, and this is the step between.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_scene_editor_core/flutter_scene_editor_core.dart';
// ignore: implementation_imports
import 'package:flutter_scene_editor_core/src/builtin_commands.dart'
    show addTerrainLayers, setTerrainSplat, terrainMaterialAsset;
import 'package:scene/scene.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

const _texels = 8;

/// A document with one terrain node, and the ids to reach it by.
({SceneDocument doc, LocalId node, LocalId geometry}) sceneWithTerrain() {
  final doc = SceneDocument();
  final geometry = doc.newId();
  doc.addResource(
    GeometryResource(
      geometry,
      procedural: TerrainGeometrySpec(
        columns: 5,
        rows: 4,
        splatColumns: _texels,
        splatRows: _texels,
      ),
    ),
  );
  final node = doc.newId();
  doc.addNode(
    NodeSpec(
      id: node,
      name: 'Terrain',
      components: [
        ComponentSpec(
          'mesh',
          properties: {'geometry': ResourceRefValue(geometry)},
        ),
      ],
    ),
    root: true,
  );
  return (doc: doc, node: node, geometry: geometry);
}

String controlMap() =>
    base64Encode(Uint8List(_texels * _texels * 4)..[0] = 255);

ComponentSpec meshIn(SceneDocument doc, LocalId node) =>
    doc.node(node)!.components.firstWhere((c) => c.type == 'mesh');

void main() {
  test('a terrain with painting gets a material bound to its control map', () {
    final scene = sceneWithTerrain();
    final session = EditorSession(scene.doc);
    session.run(setTerrainSplat.name, {
      'resourceId': scene.geometry.toToken(),
      'splat': controlMap(),
    });
    session.run(addTerrainLayers.name, {'nodeId': scene.node.toToken()});

    final materialId = switch (meshIn(
      scene.doc,
      scene.node,
    ).properties['material']) {
      ResourceRefValue(:final id) => id,
      _ => null,
    };
    expect(materialId, isNotNull);

    final material = scene.doc.resource(materialId!)! as MaterialResource;
    expect(material.type, 'fmat');
    expect(material.asset?.key, terrainMaterialAsset);

    final textureId = switch (material.properties['control_map']) {
      ResourceRefValue(:final id) => id,
      _ => null,
    };
    expect(textureId, isNotNull);

    final terrain =
        (scene.doc.resource(scene.geometry)! as GeometryResource).procedural
            as TerrainGeometrySpec;
    final texture = scene.doc.resource(textureId!)! as TextureResource;
    expect(
      texture.payload,
      terrain.splat,
      reason: 'the texture is the control map the tool painted',
    );
  });

  test('the control map is data, not colour', () {
    // Its four channels are weights. Decoding them as sRGB, or averaging mips
    // as colour, would drift the blend -- visibly, and worse at distance.
    final scene = sceneWithTerrain();
    final session = EditorSession(scene.doc);
    session.run(setTerrainSplat.name, {
      'resourceId': scene.geometry.toToken(),
      'splat': controlMap(),
    });
    session.run(addTerrainLayers.name, {'nodeId': scene.node.toToken()});

    final texture = scene.doc.resources.values
        .whereType<TextureResource>()
        .single;
    expect(texture.content, 'data');
  });

  test('it is one undo step, not three', () {
    // A texture, a material and a mesh change are one thing the user did.
    final scene = sceneWithTerrain();
    final session = EditorSession(scene.doc);
    session.run(setTerrainSplat.name, {
      'resourceId': scene.geometry.toToken(),
      'splat': controlMap(),
    });
    session.run(addTerrainLayers.name, {'nodeId': scene.node.toToken()});

    session.undo();
    expect(meshIn(scene.doc, scene.node).properties['material'], isNull);
    expect(scene.doc.resources.values.whereType<MaterialResource>(), isEmpty);
    expect(scene.doc.resources.values.whereType<TextureResource>(), isEmpty);
  });

  test('an unpainted terrain is refused, and says what to do', () {
    // There is no control map to blend by yet, and inventing a blank one would
    // put a material on the terrain that changes nothing.
    final scene = sceneWithTerrain();
    final session = EditorSession(scene.doc);
    expect(
      () =>
          session.run(addTerrainLayers.name, {'nodeId': scene.node.toToken()}),
      throwsA(
        isA<CommandException>().having(
          (e) => e.toString(),
          'message',
          contains('Paint a stroke first'),
        ),
      ),
    );
  });

  test('a node that is not a terrain is refused', () {
    final doc = SceneDocument();
    final geometry = doc.newId();
    doc.addResource(
      GeometryResource(
        geometry,
        procedural: CuboidGeometrySpec(extents: Vector3.all(1)),
      ),
    );
    final node = doc.newId();
    doc.addNode(
      NodeSpec(
        id: node,
        name: 'Box',
        components: [
          ComponentSpec(
            'mesh',
            properties: {'geometry': ResourceRefValue(geometry)},
          ),
        ],
      ),
      root: true,
    );
    final session = EditorSession(doc);
    expect(
      () => session.run(addTerrainLayers.name, {'nodeId': node.toToken()}),
      throwsA(isA<CommandException>()),
    );
  });

  test('a node with no mesh is refused', () {
    final doc = SceneDocument();
    final node = doc.newId();
    doc.addNode(NodeSpec(id: node, name: 'Empty'), root: true);
    final session = EditorSession(doc);
    expect(
      () => session.run(addTerrainLayers.name, {'nodeId': node.toToken()}),
      throwsA(isA<CommandException>()),
    );
  });

  test('running it twice replaces the material rather than stacking', () {
    final scene = sceneWithTerrain();
    final session = EditorSession(scene.doc);
    session.run(setTerrainSplat.name, {
      'resourceId': scene.geometry.toToken(),
      'splat': controlMap(),
    });
    session.run(addTerrainLayers.name, {'nodeId': scene.node.toToken()});
    session.run(addTerrainLayers.name, {'nodeId': scene.node.toToken()});

    // The mesh points at exactly one material, whichever it is.
    final materialId = switch (meshIn(
      scene.doc,
      scene.node,
    ).properties['material']) {
      ResourceRefValue(:final id) => id,
      _ => null,
    };
    expect(materialId, isNotNull);
    expect(scene.doc.resource(materialId!), isA<MaterialResource>());
  });
}
