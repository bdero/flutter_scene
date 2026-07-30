// Dev tool. Generates a few sample `.fscene` files under examples/scenes/ so
// the editor has concrete documents to open. Run from the workspace root:
//
//   dart run packages/flutter_scene_mcp/tool/gen_sample_scenes.dart
//
// The scenes use only procedural geometry and physically-based materials, so
// they realize without any external assets.
import 'dart:io';

import 'package:scene/scene.dart';
import 'package:flutter_scene_editor_core/flutter_scene_editor_core.dart';

Map<String, Object?> _vec3(double x, double y, double z) => {
  'x': x,
  'y': y,
  'z': z,
};

Map<String, Object?> _color(double r, double g, double b) => {
  'r': r,
  'g': g,
  'b': b,
  'a': 1.0,
};

/// Adds a cube node with a material colour, optional position and scale.
/// Returns the node id token.
String _cube(
  EditorSession s, {
  required String name,
  required Map<String, Object?> color,
  Map<String, Object?>? translation,
  Map<String, Object?>? scale,
  String? parentId,
}) {
  final geo = s.run('createCuboidGeometry').records.first.targetId;
  final mat = s
      .run('createMaterial', {
        'type': 'physicallyBased',
        'properties': {'baseColor': color},
      })
      .records
      .first
      .targetId;
  final node = s
      .run('createNode', {
        'name': name,
        if (parentId != null) 'parentId': parentId,
      })
      .records
      .first
      .targetId;
  s.run('addComponent', {
    'nodeId': node.toToken(),
    'componentType': 'mesh',
    'properties': {
      'geometry': {r'$resource': geo.toToken()},
      'material': {r'$resource': mat.toToken()},
    },
  });
  if (translation != null || scale != null) {
    s.run('setNodeTransform', {
      'nodeId': node.toToken(),
      if (translation != null) 'translation': translation,
      if (scale != null) 'scale': scale,
    });
  }
  return node.toToken();
}

String _sphere(
  EditorSession s, {
  required String name,
  required Map<String, Object?> color,
  Map<String, Object?>? translation,
  String? parentId,
}) {
  final geo = s.run('createSphereGeometry').records.first.targetId;
  final mat = s
      .run('createMaterial', {
        'type': 'physicallyBased',
        'properties': {'baseColor': color},
      })
      .records
      .first
      .targetId;
  final node = s
      .run('createNode', {
        'name': name,
        if (parentId != null) 'parentId': parentId,
      })
      .records
      .first
      .targetId;
  s.run('addComponent', {
    'nodeId': node.toToken(),
    'componentType': 'mesh',
    'properties': {
      'geometry': {r'$resource': geo.toToken()},
      'material': {r'$resource': mat.toToken()},
    },
  });
  if (translation != null) {
    s.run('setNodeTransform', {
      'nodeId': node.toToken(),
      'translation': translation,
    });
  }
  return node.toToken();
}

EditorSession _session(int seed) =>
    EditorSession(SceneDocument(allocator: IdAllocator(session: seed)));

void _write(String path, EditorSession s) {
  File(path)
    ..createSync(recursive: true)
    ..writeAsStringSync(s.toFscene());
  stdout.writeln('wrote $path');
}

void main() {
  // A single red cube, the simplest openable scene.
  final cube = _session(101);
  _cube(cube, name: 'Cube', color: _color(0.8, 0.2, 0.2));
  _write('examples/scenes/cube.fscene', cube);

  // A small playground of primitives at various positions and scales.
  final playground = _session(102);
  _cube(
    playground,
    name: 'Floor',
    color: _color(0.5, 0.5, 0.55),
    translation: _vec3(0, -1, 0),
    scale: _vec3(6, 0.2, 6),
  );
  _cube(
    playground,
    name: 'RedBox',
    color: _color(0.85, 0.2, 0.2),
    translation: _vec3(-1.5, 0, 0),
  );
  _sphere(
    playground,
    name: 'GreenBall',
    color: _color(0.2, 0.75, 0.3),
    translation: _vec3(1.5, 0, 0),
  );
  _cube(
    playground,
    name: 'BlueTower',
    color: _color(0.2, 0.4, 0.85),
    translation: _vec3(0, 0.5, -1.5),
    scale: _vec3(0.6, 2.0, 0.6),
  );
  _write('examples/scenes/playground.fscene', playground);

  // A small assembly meant to be reused as a prefab (a trunk plus foliage),
  // parented under one root node so it instances cleanly.
  final tree = _session(103);
  final root = tree.run('createNode', {'name': 'Tree'}).records.first.targetId;
  _cube(
    tree,
    name: 'Trunk',
    color: _color(0.4, 0.26, 0.13),
    translation: _vec3(0, 0, 0),
    scale: _vec3(0.3, 1.0, 0.3),
    parentId: root.toToken(),
  );
  _sphere(
    tree,
    name: 'Foliage',
    color: _color(0.18, 0.55, 0.2),
    translation: _vec3(0, 1.0, 0),
    parentId: root.toToken(),
  );
  _write('examples/scenes/tree_prefab.fscene', tree);

  // A scene that instances tree_prefab.fscene as a sub-scene twice, at
  // different positions, plus a ground plane. Opening this exercises prefab
  // composition (the referenced .fscene is loaded and inlined on open).
  final demo = _session(104);
  _cube(
    demo,
    name: 'Ground',
    color: _color(0.5, 0.5, 0.55),
    translation: _vec3(0, -1, 0),
    scale: _vec3(8, 0.2, 8),
  );
  final treeA = demo
      .run('instantiatePrefab', {
        'prefabAsset': 'tree_prefab.fscene',
        'name': 'Tree A',
      })
      .records
      .first
      .targetId;
  demo.run('setNodeTransform', {
    'nodeId': treeA.toToken(),
    'translation': _vec3(-2, 0, 0),
  });
  final treeB = demo
      .run('instantiatePrefab', {
        'prefabAsset': 'tree_prefab.fscene',
        'name': 'Tree B',
      })
      .records
      .first
      .targetId;
  demo.run('setNodeTransform', {
    'nodeId': treeB.toToken(),
    'translation': _vec3(2, 0, 0),
  });
  _write('examples/scenes/prefab_demo.fscene', demo);
}
