// Whole-clip utility commands: duplicate, shift, scale, mirror.
import 'dart:typed_data';

import 'package:scene/scene.dart';
import 'package:flutter_scene_editor_core/flutter_scene_editor_core.dart';
import 'package:flutter_scene_editor_core/src/command.dart';
import 'package:flutter_scene_editor_core/src/history.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

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

void _run(
  ({SceneDocument doc, EditHistory history, CommandRegistry registry}) h,
  String command,
  Map<String, Object?> params,
) {
  final entry = h.registry.lookup(command)!;
  h.history.commit(entry.execute(CommandContext(h.doc), params));
}

LocalId _addCube(
  ({SceneDocument doc, EditHistory history, CommandRegistry registry}) h,
  String name,
) {
  _run(h, 'createNode', {'name': name});
  return h.doc.roots.last;
}

List<double> _timesOf(
  SceneDocument doc,
  AnimationSpec animation,
  LocalId target,
) {
  final channel = animation.channels.firstWhere(
    (c) => c.target == target && c.property == AnimationProperty.translation,
  );
  final bytes = doc.payload(channel.timeline)!.bytes!;
  return [
    for (final v in bytes.buffer.asFloat32List(
      bytes.offsetInBytes,
      bytes.lengthInBytes ~/ 4,
    ))
      v,
  ];
}

Uint8List _keyframeBytes(
  SceneDocument doc,
  AnimationSpec animation,
  LocalId target,
) => doc
    .payload(
      animation.channels
          .firstWhere(
            (c) =>
                c.target == target && c.property == AnimationProperty.rotation,
          )
          .keyframes,
    )!
    .bytes!;

void main() {
  test('duplicateAnimation copies channels with fresh ids', () {
    final h = _harness();
    final node = _addCube(h, 'Cube');
    _run(h, 'createAnimation', {'name': 'Original'});
    final originalId = h.doc.animations.keys.last;
    _run(h, 'setAnimationKeyframe', {
      'animationId': originalId.toToken(),
      'nodeId': node.toToken(),
      'property': 'translation',
      'time': 1.0,
      'translation': {'x': 5.0, 'y': 0.0, 'z': 0.0},
    });
    final originalPayloadCount = h.doc.payloads.length;

    _run(h, 'duplicateAnimation', {'animationId': originalId.toToken()});
    final copyId = h.doc.animations.keys.last;
    expect(copyId, isNot(originalId));
    final copy = h.doc.animations[copyId]!;
    expect(copy.name, 'Original copy');
    // Same target and keyframe data...
    final times = _timesOf(h.doc, copy, node);
    expect(times.single, closeTo(1.0, 1e-6));
    // ...but independent payloads with fresh ids.
    for (final channel in copy.channels) {
      expect(h.doc.payloads.containsKey(channel.timeline), isTrue);
      expect(h.doc.payloads.containsKey(channel.keyframes), isTrue);
      expect(
        channel.timeline ==
            h.doc.animations[originalId]!.channels.first.timeline,
        isFalse,
      );
    }
    expect(h.doc.payloads.length, greaterThan(originalPayloadCount));

    // Undo removes the whole copy including its payloads.
    h.history.undo();
    expect(h.doc.animations.containsKey(copyId), isFalse);
  });

  test('shiftAnimationTime moves keys and rejects pre-zero results', () {
    final h = _harness();
    final node = _addCube(h, 'Cube');
    _run(h, 'createAnimation', {'name': 'Clip'});
    final animationId = h.doc.animations.keys.last;
    _run(h, 'setAnimationKeyframes', {
      'animationId': animationId.toToken(),
      'nodeId': node.toToken(),
      'property': 'translation',
      'keys': [
        {'time': 1.0},
        {'time': 2.0},
      ],
    });
    _run(h, 'shiftAnimationTime', {
      'animationId': animationId.toToken(),
      'offset': -0.5,
    });
    var times = _timesOf(h.doc, h.doc.animations[animationId]!, node);
    expect(times[0], closeTo(0.5, 1e-6));
    expect(times[1], closeTo(1.5, 1e-6));

    expect(
      () => _run(h, 'shiftAnimationTime', {
        'animationId': animationId.toToken(),
        'offset': -1.0,
      }),
      throwsA(isA<CommandException>()),
    );

    h.history.undo();
    times = _timesOf(h.doc, h.doc.animations[animationId]!, node);
    expect(times[0], closeTo(1.0, 1e-6));
    expect(times[1], closeTo(2.0, 1e-6));
  });

  test('scaleAnimationTime stretches timing; bad factors rejected', () {
    final h = _harness();
    final node = _addCube(h, 'Cube');
    _run(h, 'createAnimation', {'name': 'Clip'});
    final animationId = h.doc.animations.keys.last;
    _run(h, 'setAnimationKeyframes', {
      'animationId': animationId.toToken(),
      'nodeId': node.toToken(),
      'property': 'translation',
      'keys': [
        {'time': 0.5},
        {'time': 1.0},
      ],
    });
    _run(h, 'scaleAnimationTime', {
      'animationId': animationId.toToken(),
      'factor': 2.0,
    });
    final times = _timesOf(h.doc, h.doc.animations[animationId]!, node);
    expect(times[0], closeTo(1.0, 1e-6));
    expect(times[1], closeTo(2.0, 1e-6));

    for (final badFactor in [0.0, -1.0]) {
      expect(
        () => _run(h, 'scaleAnimationTime', {
          'animationId': animationId.toToken(),
          'factor': badFactor,
        }),
        throwsA(isA<CommandException>()),
      );
    }
  });

  test('mirrorAnimationX flips translation x and rotation yaw', () {
    final h = _harness();
    final node = _addCube(h, 'Cube');
    _run(h, 'createAnimation', {'name': 'Walk'});
    final animationId = h.doc.animations.keys.last;
    _run(h, 'setNodeTransform', {
      'nodeId': node.toToken(),
      'translation': {'x': 3.0, 'y': 0.5, 'z': 0.0},
      'rotationEuler': {'yaw': 90.0, 'pitch': 0.0, 'roll': 0.0},
    });
    _run(h, 'keyPose', {
      'animationId': animationId.toToken(),
      'time': 0.0,
      'nodeIds': [node.toToken()],
    });
    _run(h, 'mirrorAnimationX', {'animationId': animationId.toToken()});

    final animation = h.doc.animations[animationId]!;
    final times = _timesOf(h.doc, animation, node);
    expect(times.single, closeTo(0.0, 1e-6));

    final bytes = _keyframeBytes(h.doc, animation, node);
    final floats = bytes.buffer.asFloat32List(
      bytes.offsetInBytes,
      bytes.lengthInBytes ~/ 4,
    );
    // Translation x flipped sign; y survived.
    final translationChannel = animation.channels.firstWhere(
      (c) => c.target == node && c.property == AnimationProperty.translation,
    );
    final tBytes = h.doc.payload(translationChannel.keyframes)!.bytes!;
    final tFloats = tBytes.buffer.asFloat32List(
      tBytes.offsetInBytes,
      tBytes.lengthInBytes ~/ 4,
    );
    expect(tFloats[0], closeTo(-3.0, 1e-6));
    expect(tFloats[1], closeTo(0.5, 1e-6));

    // The mirrored orientation of a +90 degree yaw is a -90 degree yaw:
    // rotating +X through the engine's matrix path now lands on +Z.
    final q = Quaternion(floats[0], floats[1], floats[2], floats[3]);
    final rotated = Matrix4.compose(
      Vector3.zero(),
      q,
      Vector3(1, 1, 1),
    ).transformed3(Vector3(1, 0, 0));
    expect(rotated.x, closeTo(0.0, 1e-5));
    expect(rotated.z, closeTo(1.0, 1e-5));
  });
}
