// Animation-tab keying must never mutate the keyed nodes' document (rest)
// transforms: keys live in animation channels only, so stopping the preview or
// undoing a key always lands the scene back on its authored pose.
import 'package:scene/scene.dart';
import 'package:flutter_scene_editor_core/flutter_scene_editor_core.dart';
import 'package:test/test.dart';

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

LocalId _addNode(
  ({SceneDocument doc, EditHistory history, CommandRegistry registry}) h,
  String name, {
  LocalId? parentId,
}) {
  _run(h, 'createNode', {
    'name': name,
    if (parentId != null) 'parentId': parentId.toToken(),
  });
  return parentId == null
      ? h.doc.roots.last
      : h.doc.node(parentId)!.children.last;
}

/// The node's local transform as a flat matrix, for value comparison.
List<double> _matrixOf(SceneDocument doc, LocalId id) =>
    doc.node(id)!.transform.toMatrix4().storage.toList();

void _expectMatrixUnchanged(
  SceneDocument doc,
  LocalId id,
  List<double> rest,
  String label,
) {
  final now = _matrixOf(doc, id);
  expect(
    now.length,
    rest.length,
    reason: '$label: matrix size changed',
  );
  for (var i = 0; i < now.length; i++) {
    expect(
      now[i],
      closeTo(rest[i], 1e-6),
      reason: '$label: matrix[$i] moved',
    );
  }
}

void main() {
  // The exact batch the animation panel's Key button sends for a mirrored
  // key of a parent+child selection: every selected node × {translation,
  // rotation, scale}, each with the pose values captured from the live node.
  test('multi-node keying batch leaves node transforms untouched', () {
    final h = _harness();
    final parent = _addNode(h, 'Parent');
    final child = _addNode(h, 'Child', parentId: parent);
    _run(h, 'setNodeTransform', {
      'nodeId': parent.toToken(),
      'translation': {'x': 1.0, 'y': 2.0, 'z': 3.0},
    });
    _run(h, 'setNodeTransform', {
      'nodeId': child.toToken(),
      'translation': {'x': 0.0, 'y': 1.0, 'z': 0.0},
      'scale': {'x': 2.0, 'y': 2.0, 'z': 2.0},
    });
    final parentRest = _matrixOf(h.doc, parent);
    final childRest = _matrixOf(h.doc, child);

    _run(h, 'createAnimation', {'name': 'Walk'});
    final animationId = h.doc.animations.keys.last;

    final records = <ChangeRecord>[];
    for (final (node, pose) in [
      (parent, {
        'translation': {'x': 4.0, 'y': 2.0, 'z': 3.0},
        'rotation': {'x': 0.0, 'y': 0.0, 'z': 0.0, 'w': 1.0},
        'scale': {'x': 1.0, 'y': 1.0, 'z': 1.0},
      }),
      // The child rides along, so its live pose equals its rest pose —
      // mirrored mode keys it anyway.
      (child, {
        'translation': {'x': 0.0, 'y': 1.0, 'z': 0.0},
        'rotation': {'x': 0.0, 'y': 0.0, 'z': 0.0, 'w': 1.0},
        'scale': {'x': 2.0, 'y': 2.0, 'z': 2.0},
      }),
    ]) {
      for (final property in const ['translation', 'rotation', 'scale']) {
        final tx = _run(h, 'setAnimationKeyframe', {
          'animationId': animationId.toToken(),
          'nodeId': node.toToken(),
          'property': property,
          'time': 0.5,
          ...pose,
        });
        records.addAll(tx.records);
      }
    }

    // The guarantee: keying wrote channels, never node transforms.
    _expectMatrixUnchanged(h.doc, parent, parentRest, 'Parent');
    _expectMatrixUnchanged(h.doc, child, childRest, 'Child');
    expect(
      records.where((r) => r.slot == ChangeSlot.transform),
      isEmpty,
      reason: 'keying must not emit node transform change records',
    );

    // And the keys themselves landed in the animation.
    final animation = h.doc.animations[animationId]!;
    expect(animation.channels.length, 6);
    final parentTranslation = animation.channels.firstWhere(
      (c) => c.target == parent && c.property == AnimationProperty.translation,
    );
    final bytes = h.doc.payload(parentTranslation.keyframes)!.bytes!;
    final values = bytes.buffer.asFloat32List(
      bytes.offsetInBytes,
      bytes.lengthInBytes ~/ 4,
    );
    expect(values[0], closeTo(4.0, 1e-6));
  });

  // The command's own capture path (omitted value components fall back to
  // the document pose) is also write-free.
  test('keyframe without explicit values captures, never mutates', () {
    final h = _harness();
    final node = _addNode(h, 'Cube');
    _run(h, 'setNodeTransform', {
      'nodeId': node.toToken(),
      'translation': {'x': 7.0, 'y': 8.0, 'z': 9.0},
    });
    final rest = _matrixOf(h.doc, node);
    _run(h, 'createAnimation', {'name': 'Clip'});
    final animationId = h.doc.animations.keys.last;

    final tx = _run(h, 'setAnimationKeyframe', {
      'animationId': animationId.toToken(),
      'nodeId': node.toToken(),
      'property': 'translation',
      'time': 0.0,
    });

    _expectMatrixUnchanged(h.doc, node, rest, 'Cube');
    expect(
      tx.records.where((r) => r.slot == ChangeSlot.transform),
      isEmpty,
    );
    // The captured key equals the rest translation.
    final animation = h.doc.animations[animationId]!;
    final channel = animation.channels.single;
    final bytes = h.doc.payload(channel.keyframes)!.bytes!;
    final values = bytes.buffer.asFloat32List(
      bytes.offsetInBytes,
      bytes.lengthInBytes ~/ 4,
    );
    expect(values[0], closeTo(7.0, 1e-6));
    expect(values[1], closeTo(8.0, 1e-6));
    expect(values[2], closeTo(9.0, 1e-6));
  });
}
