// Whole-clip utility commands: duplicate, shift, scale, mirror.
import 'dart:typed_data';

import 'package:scene/scene.dart';
import 'package:flutter_scene_editor_core/flutter_scene_editor_core.dart';
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

  test(
    'step interpolation survives the .fscene round trip; linear omits it',
    () {
      final h = _harness();
      final node = _addCube(h, 'Cube');
      _run(h, 'createAnimation', {'name': 'Clip'});
      final animationId = h.doc.animations.keys.last;
      _run(h, 'setAnimationKeyframes', {
        'animationId': animationId.toToken(),
        'nodeId': node.toToken(),
        'property': 'translation',
        'keys': [
          {'time': 0.0},
          {'time': 1.0},
        ],
      });
      // A second, untouched channel stays linear.
      _run(h, 'setAnimationKeyframe', {
        'animationId': animationId.toToken(),
        'nodeId': node.toToken(),
        'property': 'scale',
        'time': 0.0,
      });

      // A default channel encodes without the key at all.
      final plain = writeFscene(readFscene(writeFscene(h.doc)));
      expect(plain.contains('interpolation'), isFalse);

      _run(h, 'setChannelInterpolation', {
        'animationId': animationId.toToken(),
        'nodeId': node.toToken(),
        'property': 'translation',
        'interpolation': 'step',
      });
      final encoded = writeFscene(h.doc);
      expect(encoded.contains('interpolation'), isTrue);

      final restored = readFscene(encoded);
      final restoredAnimation = restored.animations[animationId]!;
      final stepped = restoredAnimation.channels.firstWhere(
        (c) => c.property == AnimationProperty.translation,
      );
      expect(stepped.interpolation, AnimationInterpolation.step);
      final linear = restoredAnimation.channels.firstWhere(
        (c) => c.property == AnimationProperty.scale,
      );
      expect(linear.interpolation, isNull);

      // And the step flag itself survives a second round trip.
      expect(writeFscene(restored), encoded);
    },
  );

  test('cubic conversion expands rows; re-keying preserves tangents', () {
    final h = _harness();
    final node = _addCube(h, 'Cube');
    _run(h, 'createAnimation', {'name': 'Clip'});
    final animationId = h.doc.animations.keys.last;
    _run(h, 'setAnimationKeyframes', {
      'animationId': animationId.toToken(),
      'nodeId': node.toToken(),
      'property': 'translation',
      'keys': [
        {'time': 0.0},
        {'time': 1.0},
      ],
    });
    var animation = h.doc.animations[animationId]!;
    var channel = animation.channels.first;
    expect(h.doc.payload(channel.keyframes)!.bytes!.length, 24); // 2 x 3

    // Linear -> cubic triples each row; values move to the middle slot.
    _run(h, 'setChannelInterpolation', {
      'animationId': animationId.toToken(),
      'nodeId': node.toToken(),
      'property': 'translation',
      'interpolation': 'cubic',
    });
    animation = h.doc.animations[animationId]!;
    channel = animation.channels.first;
    var bytes = h.doc.payload(channel.keyframes)!.bytes!;
    expect(bytes.length, 72); // 2 x 9

    // Re-keying updates only the value slot; tangent slots stay zero
    // (the captured value must not leak into them).
    _run(h, 'setNodeTransform', {
      'nodeId': node.toToken(),
      'translation': {'x': 7.0, 'y': 8.0, 'z': 9.0},
    });
    _run(h, 'keyPose', {
      'animationId': animationId.toToken(),
      'time': 0.0,
      'nodeIds': [node.toToken()],
    });
    bytes = h.doc.payload(channel.keyframes)!.bytes!;
    expect(bytes.length, 72);
    final floats = bytes.buffer.asFloat32List(
      bytes.offsetInBytes,
      bytes.lengthInBytes ~/ 4,
    );
    expect(floats[3], closeTo(7.0, 1e-6));
    expect(floats[4], closeTo(8.0, 1e-6));
    expect(floats[5], closeTo(9.0, 1e-6));
    expect(floats[6], closeTo(0.0, 1e-6)); // out-tangent untouched

    // Cubic -> linear collapses back to one vector per key.
    _run(h, 'setChannelInterpolation', {
      'animationId': animationId.toToken(),
      'nodeId': node.toToken(),
      'property': 'translation',
      'interpolation': 'linear',
    });
    animation = h.doc.animations[animationId]!;
    channel = animation.channels.first;
    expect(h.doc.payload(channel.keyframes)!.bytes!.length, 24);

    // Undo thrice walks conversion and edits backwards without corruption.
    for (var i = 0; i < 3; i++) {
      h.history.undo();
    }
    animation = h.doc.animations[animationId]!;
    // After three undos we're back at the freshly-expanded cubic state
    // (linear-conversion -> keyPose -> linear-conversion were undone).
    expect(
      animation.channels.first.interpolation,
      AnimationInterpolation.cubic,
    );
    expect(
      h.doc.payload(animation.channels.first.keyframes)!.bytes!.length,
      72,
    );
    // A fourth undo returns to the original linear keys.
    h.history.undo();
    animation = h.doc.animations[animationId]!;
    expect(animation.channels.first.interpolation, isNull);
    expect(
      h.doc.payload(animation.channels.first.keyframes)!.bytes!.length,
      24,
    );
  });

  test('tangent authoring on cubic channels', () {
    final h = _harness();
    final node = _addCube(h, 'Cube');
    _run(h, 'createAnimation', {'name': 'Clip'});
    final animationId = h.doc.animations.keys.last;
    _run(h, 'setAnimationKeyframes', {
      'animationId': animationId.toToken(),
      'nodeId': node.toToken(),
      'property': 'translation',
      'keys': [
        {'time': 0.0},
        {'time': 1.0},
      ],
    });
    _run(h, 'setChannelInterpolation', {
      'animationId': animationId.toToken(),
      'nodeId': node.toToken(),
      'property': 'translation',
      'interpolation': 'cubic',
    });
    animation() => h.doc.animations[animationId]!;
    List<double> row(double time) {
      final channel = animation().channels.first;
      final bytes = h.doc.payload(channel.keyframes)!.bytes!;
      final floats = bytes.buffer.asFloat32List(
        bytes.offsetInBytes,
        bytes.lengthInBytes ~/ 4,
      );
      return floats;
    }

    // Author an out-tangent on key 0.
    _run(h, 'setAnimationKeyframe', {
      'animationId': animationId.toToken(),
      'nodeId': node.toToken(),
      'property': 'translation',
      'time': 0.0,
      'outTangent': {'x': 30.0, 'y': 0.0, 'z': 0.0},
    });
    var floats = row(0.0);
    // Out-tangent slot of key 0: floats[6..8].
    expect(floats[6], closeTo(30.0, 1e-6));
    // Re-key the same time WITHOUT tangents: they must survive.
    _run(h, 'setNodeTransform', {
      'nodeId': node.toToken(),
      'translation': {'x': 1.0, 'y': 2.0, 'z': 3.0},
    });
    _run(h, 'setAnimationKeyframe', {
      'animationId': animationId.toToken(),
      'nodeId': node.toToken(),
      'property': 'translation',
      'time': 0.0,
    });
    floats = row(0.0);
    expect(floats[3], closeTo(1.0, 1e-6)); // value updated
    expect(floats[4], closeTo(2.0, 1e-6));
    expect(floats[5], closeTo(3.0, 1e-6));
    expect(floats[6], closeTo(30.0, 1e-6)); // out-tangent preserved
    expect(floats[9], closeTo(0.0, 1e-6)); // key 1 untouched

    // Tangents on a non-cubic channel are rejected loudly.
    final other = _addCube(h, 'Other');
    _run(h, 'createAnimation', {'name': 'Linear'});
    final linearId = h.doc.animations.keys.last;
    _run(h, 'setAnimationKeyframe', {
      'animationId': linearId.toToken(),
      'nodeId': other.toToken(),
      'property': 'translation',
      'time': 0.0,
    });
    expect(
      () => _run(h, 'setAnimationKeyframe', {
        'animationId': linearId.toToken(),
        'nodeId': other.toToken(),
        'property': 'translation',
        'time': 0.0,
        'outTangent': {'x': 1.0, 'y': 0.0, 'z': 0.0},
      }),
      throwsA(isA<CommandException>()),
    );
  });

  test('name-targeted channels key prefab members without colliding', () {
    final h = _harness();
    final instance = _addCube(h, 'Lunar');
    _run(h, 'createAnimation', {'name': 'Rig'});
    final animationId = h.doc.animations.keys.last;

    // Two bones of one instance, both rotation channels.
    _run(h, 'setAnimationKeyframe', {
      'animationId': animationId.toToken(),
      'nodeId': instance.toToken(),
      'targetName': 'Bone_000',
      'property': 'rotation',
      'time': 0.0,
      'rotationEuler': {'yaw': 0.0, 'pitch': 0.0, 'roll': 0.0},
    });
    _run(h, 'setAnimationKeyframe', {
      'animationId': animationId.toToken(),
      'nodeId': instance.toToken(),
      'targetName': 'Bone_001',
      'property': 'rotation',
      'time': 0.0,
      'rotationEuler': {'yaw': 90.0, 'pitch': 0.0, 'roll': 0.0},
    });

    var animation = h.doc.animations[animationId]!;
    final boneChannels = animation.channels
        .where((c) => c.target == instance)
        .toList();
    expect(boneChannels, hasLength(2));
    expect(boneChannels.map((c) => c.targetName).toSet(), {
      'Bone_000',
      'Bone_001',
    });

    // Re-keying one bone leaves the other untouched.
    _run(h, 'setAnimationKeyframe', {
      'animationId': animationId.toToken(),
      'nodeId': instance.toToken(),
      'targetName': 'Bone_000',
      'property': 'rotation',
      'time': 1.0,
      'rotationEuler': {'yaw': 180.0, 'pitch': 0.0, 'roll': 0.0},
    });
    animation = h.doc.animations[animationId]!;
    var bone000Keys = 0;
    var bone001Keys = 0;
    for (final channel in animation.channels.where(
      (c) => c.target == instance,
    )) {
      final bytes = h.doc.payload(channel.timeline)!.bytes!;
      final times = bytes.buffer.asFloat32List(
        bytes.offsetInBytes,
        bytes.lengthInBytes ~/ 4,
      );
      if (channel.targetName == 'Bone_000') {
        bone000Keys = times.length;
      } else {
        bone001Keys = times.length;
      }
    }
    expect(bone000Keys, 2);
    expect(bone001Keys, 1);

    // Removing the member's only key deletes its channel (documented
    // behavior) — and leaves the sibling bone untouched.
    _run(h, 'removeAnimationKeyframe', {
      'animationId': animationId.toToken(),
      'nodeId': instance.toToken(),
      'targetName': 'Bone_001',
      'property': 'rotation',
      'time': 0.0,
    });
    animation = h.doc.animations[animationId]!;
    expect(
      animation.channels.where((c) => c.targetName == 'Bone_001'),
      isEmpty,
    );
    expect(
      animation.channels.where((c) => c.targetName == 'Bone_000'),
      hasLength(1),
    );
  });
}
