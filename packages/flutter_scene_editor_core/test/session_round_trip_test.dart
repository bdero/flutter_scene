import 'dart:typed_data';

import 'package:scene/scene.dart';
import 'package:flutter_scene_editor_core/flutter_scene_editor_core.dart';
import 'package:test/test.dart';

void main() {
  // Milestone M1: load, edit through commands, undo and redo the whole
  // sequence, serialize, and round-trip byte-stably, with no GPU and no UI.
  test('build, serialize, undo-all, redo-all round-trip byte-stably', () {
    final session = EditorSession(
      SceneDocument(allocator: IdAllocator(session: 7)),
    );
    final empty = session.toFscene();

    final root = session
        .run('createNode', {'name': 'Root'})
        .records
        .first
        .targetId;
    final child = session
        .run('createNode', {'name': 'Child', 'parentId': root.toToken()})
        .records
        .first
        .targetId;
    session.run('setNodeTransform', {
      'nodeId': child.toToken(),
      'translation': {'x': 1.0, 'y': 2.0, 'z': 3.0},
    });
    final geometry = session
        .run('createCuboidGeometry', {
          'extents': {'x': 2.0, 'y': 1.0, 'z': 1.0},
        })
        .records
        .first
        .targetId;
    final material = session
        .run('createMaterial', {
          'type': 'physicallyBased',
          'properties': {
            'baseColor': {'r': 1.0, 'g': 0.0, 'b': 0.0, 'a': 1.0},
            'metallic': 0.5,
          },
        })
        .records
        .first
        .targetId;
    session.run('addComponent', {
      'nodeId': child.toToken(),
      'componentType': 'mesh',
      'properties': {
        'geometry': {r'$resource': geometry.toToken()},
        'material': {r'$resource': material.toToken()},
      },
    });
    session.run('addComponent', {
      'nodeId': root.toToken(),
      'componentType': 'directionalLight',
      'properties': {'intensity': 1.5, 'castsShadow': true},
    });
    final enemy = session
        .run('instantiatePrefab', {
          'prefabAsset': 'assets/enemy.fscene',
          'name': 'Enemy',
        })
        .records
        .first
        .targetId;
    session.run('setPrefabOverride', {
      'nodeId': enemy.toToken(),
      'target': enemy.toToken(),
      'path': 'visible',
      'value': false,
    });

    final built = session.toFscene();
    expect(built, isNot(equals(empty)));

    // Serializing a reparse of the built scene is byte-identical.
    expect(writeFscene(readFscene(built)), built);

    // Undo everything returns to the empty baseline exactly.
    final count = session.history.transactions.length;
    expect(count, greaterThan(0));
    for (var i = 0; i < count; i++) {
      expect(session.undo(), isTrue);
    }
    expect(session.toFscene(), empty);
    expect(session.history.canUndo, isFalse);

    // Redo everything reproduces the built scene exactly (same ids and all).
    for (var i = 0; i < count; i++) {
      expect(session.redo(), isTrue);
    }
    expect(session.toFscene(), built);
  });

  test('an externalized texture survives a lean .fscene round-trip', () {
    final session = EditorSession.empty();
    session.run('createTextureResourceFromAsset', {
      'asset': 'imported/wood.png',
    });
    TextureResource texture(SceneDocument doc) =>
        doc.resources.values.whereType<TextureResource>().single;

    final created = texture(session.document);
    expect(created.asset?.key, 'imported/wood.png');
    expect(created.payload, isNull);

    // The lean text save carries the asset reference (not bytes), so reopening
    // recovers the texture intact.
    final roundTripped = texture(readFscene(session.toFscene()));
    expect(roundTripped.asset?.key, 'imported/wood.png');
    expect(roundTripped.payload, isNull);
  });

  test('an embedded texture payload is dropped by a lean .fscene save', () {
    // Documents the data loss the externalized path avoids: a raw-bytes payload
    // texture keeps only its descriptor through a `.fscene` (text) round-trip,
    // since lean text does not carry payload bytes. See
    // TODO(externalize-embedded-textures).
    final session = EditorSession.empty();
    session.run('createTextureResource', {
      'width': 1,
      'height': 1,
      'bytes': Uint8List.fromList(const [10, 20, 30, 40]),
    });
    final reloaded = readFscene(session.toFscene());
    expect(reloaded.payloads.values.single.bytes, isNull);
  });

  test('fromFscene loads a session that can keep editing', () {
    final source = EditorSession(
      SceneDocument(allocator: IdAllocator(session: 3)),
    )..run('createNode', {'name': 'Loaded'});
    final text = source.toFscene();

    final loaded = EditorSession.fromFscene(text);
    expect(loaded.query.roots.single.name, 'Loaded');

    final id = loaded.query.roots.single.id;
    loaded.run('setNodeName', {'nodeId': id.toToken(), 'name': 'Edited'});
    expect(loaded.query.node(id)!.name, 'Edited');
    loaded.undo();
    expect(loaded.query.node(id)!.name, 'Loaded');
  });
}
