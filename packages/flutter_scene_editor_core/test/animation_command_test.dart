import 'dart:typed_data';

import 'package:scene/scene.dart';
import 'package:flutter_scene_editor_core/flutter_scene_editor_core.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

/// A document plus a history and a registry wired to it, for command tests.
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

/// Runs a command by name and commits its transaction.
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

/// Reads a channel's keyframe times and values back out of the payloads.
(List<double>, List<List<double>>) _channelData(
  SceneDocument doc,
  AnimationSpec animation,
  LocalId target,
  AnimationProperty property,
) {
  final channel = animation.channels.firstWhere(
    (c) => c.target == target && c.property == property,
  );
  List<double> floats(PayloadSpec? payload) {
    final bytes = payload!.bytes!;
    return [
      for (final v in bytes.buffer.asFloat32List(
        bytes.offsetInBytes,
        bytes.lengthInBytes ~/ 4,
      ))
        v,
    ];
  }

  final stride = property == AnimationProperty.rotation ? 4 : 3;
  final times = floats(doc.payload(channel.timeline));
  final values = floats(doc.payload(channel.keyframes));
  return (
    times,
    [
      for (var i = 0; i * stride + stride <= values.length; i++)
        [for (var j = 0; j < stride; j++) values[i * stride + j]],
    ],
  );
}

void main() {
  group('animation commands', () {
    test('create, rename, delete round trip with undo', () {
      final h = _harness();
      _run(h, 'createAnimation', {'name': 'Spin'});
      expect(h.doc.animations, hasLength(1));
      final id = h.doc.animations.keys.single;
      expect(h.doc.animations[id]!.name, 'Spin');

      _run(h, 'renameAnimation', {
        'animationId': id.toToken(),
        'name': 'Twirl',
      });
      expect(h.doc.animations[id]!.name, 'Twirl');

      // Undo lands on Spin, redo on Twirl.
      expect(h.history.undo(), isTrue);
      expect(h.doc.animations[id]!.name, 'Spin');
      expect(h.history.redo(), isTrue);
      expect(h.doc.animations[id]!.name, 'Twirl');

      _run(h, 'deleteAnimation', {'animationId': id.toToken()});
      expect(h.doc.animations, isEmpty);
      expect(h.history.undo(), isTrue);
      expect(h.doc.animations[id]!.name, 'Twirl');
    });

    test('keyframes capture the current transform and sort by time', () {
      final h = _harness();
      _run(h, 'createAnimation', {});
      final animationId = h.doc.animations.keys.single;
      final node = _addCube(h, 'Cube');
      // Move the node, then key its pose without passing explicit values.
      _run(h, 'setNodeTransform', {
        'nodeId': node.toToken(),
        'translation': {'x': 1.0, 'y': 2.0, 'z': 3.0},
        'rotation': {'x': 0.0, 'y': 0.0, 'z': 0.7071, 'w': 0.7071},
      });

      _run(h, 'setAnimationKeyframe', {
        'animationId': animationId.toToken(),
        'nodeId': node.toToken(),
        'property': 'translation',
        'time': 1.0,
      });
      _run(h, 'setAnimationKeyframe', {
        'animationId': animationId.toToken(),
        'nodeId': node.toToken(),
        'property': 'translation',
        'time': 0.5,
      });

      final (times, values) = _channelData(
        h.doc,
        h.doc.animations[animationId]!,
        node,
        AnimationProperty.translation,
      );
      expect(times, [0.5, 1.0]);
      expect(values.first, [1.0, 2.0, 3.0]);

      // The rotation keyframe carries the captured quaternion.
      _run(h, 'setAnimationKeyframe', {
        'animationId': animationId.toToken(),
        'nodeId': node.toToken(),
        'property': 'rotation',
        'time': 0.0,
      });
      final (_, rotations) = _channelData(
        h.doc,
        h.doc.animations[animationId]!,
        node,
        AnimationProperty.rotation,
      );
      expect(rotations.single.length, 4);
    });

    test('re-keying the same time replaces the value', () {
      final h = _harness();
      _run(h, 'createAnimation', {});
      final animationId = h.doc.animations.keys.single;
      final node = _addCube(h, 'Cube');
      Map<String, Object?> set(double t, double y) => {
        'animationId': animationId.toToken(),
        'nodeId': node.toToken(),
        'property': 'translation',
        'time': t,
        'translation': {'x': 0.0, 'y': y, 'z': 0.0},
      };
      _run(h, 'setAnimationKeyframe', set(0.0, 1.0));
      _run(h, 'setAnimationKeyframe', set(1.0, 2.0));
      _run(h, 'setAnimationKeyframe', set(0.0, 9.0));

      final (times, values) = _channelData(
        h.doc,
        h.doc.animations[animationId]!,
        node,
        AnimationProperty.translation,
      );
      expect(times, [0.0, 1.0]);
      expect(values.first, [0.0, 9.0, 0.0]);
    });

    test('removing the last keyframe removes the channel and payloads', () {
      final h = _harness();
      _run(h, 'createAnimation', {});
      final animationId = h.doc.animations.keys.single;
      final node = _addCube(h, 'Cube');
      _run(h, 'setAnimationKeyframe', {
        'animationId': animationId.toToken(),
        'nodeId': node.toToken(),
        'property': 'translation',
        'time': 0.25,
      });
      var animation = h.doc.animations[animationId]!;
      expect(animation.channels, hasLength(1));
      expect(h.doc.payloads, hasLength(2));

      _run(h, 'removeAnimationKeyframe', {
        'animationId': animationId.toToken(),
        'nodeId': node.toToken(),
        'property': 'translation',
        'time': 0.25001,
      });
      // The channel was the animation's only one; the animation goes too.
      expect(h.doc.animations, isEmpty);
      expect(h.doc.payloads, isEmpty);

      // Undo restores the animation, its channel, and its payload bytes.
      expect(h.history.undo(), isTrue);
      animation = h.doc.animations[animationId]!;
      expect(animation.channels, hasLength(1));
      final (times, _) = _channelData(
        h.doc,
        animation,
        node,
        AnimationProperty.translation,
      );
      expect(times.single, closeTo(0.25, 1e-6));
    });

    test('move keyframe reorders without duplicating', () {
      final h = _harness();
      _run(h, 'createAnimation', {});
      final animationId = h.doc.animations.keys.single;
      final node = _addCube(h, 'Cube');
      for (final t in [0.0, 1.0]) {
        _run(h, 'setAnimationKeyframe', {
          'animationId': animationId.toToken(),
          'nodeId': node.toToken(),
          'property': 'scale',
          'time': t,
          'scale': {'x': 2.0, 'y': 2.0, 'z': 2.0},
        });
      }
      _run(h, 'moveAnimationKeyframe', {
        'animationId': animationId.toToken(),
        'nodeId': node.toToken(),
        'property': 'scale',
        'fromTime': 0.0,
        'toTime': 2.0,
      });
      final (times, _) = _channelData(
        h.doc,
        h.doc.animations[animationId]!,
        node,
        AnimationProperty.scale,
      );
      expect(times, [1.0, 2.0]);
    });

    test('deleting an animation removes its channels\' payloads', () {
      final h = _harness();
      _run(h, 'createAnimation', {});
      final animationId = h.doc.animations.keys.single;
      final node = _addCube(h, 'Cube');
      _run(h, 'setAnimationKeyframe', {
        'animationId': animationId.toToken(),
        'nodeId': node.toToken(),
        'property': 'translation',
        'time': 0.0,
      });
      expect(h.doc.payloads, hasLength(2));
      _run(h, 'deleteAnimation', {'animationId': animationId.toToken()});
      expect(h.doc.payloads, isEmpty);
      expect(h.history.undo(), isTrue);
      expect(h.doc.payloads, hasLength(2));
    });

    group('animation persistence', () {
      test('.fscene text keeps the animation manifest (bytes live in the '
          'sidecar)', () {
        final source = _harness();
        _run(source, 'createAnimation', {'name': 'Bounce'});
        final animationId = source.doc.animations.keys.single;
        final node = _addCube(source, 'Cube');
        for (final entry in {
          0.0: {'x': 0.0, 'y': 0.0, 'z': 0.0},
          1.0: {'x': 0.0, 'y': 3.0, 'z': 0.0},
        }.entries) {
          _run(source, 'setAnimationKeyframe', {
            'animationId': animationId.toToken(),
            'nodeId': node.toToken(),
            'property': 'translation',
            'time': entry.key,
            'translation': entry.value,
          });
        }

        final text = writeFscene(source.doc);
        final restored = readFscene(text);

        expect(restored.animations, hasLength(1));
        final animation = restored.animations.values.single;
        expect(animation.name, 'Bounce');
        expect(animation.channels, hasLength(1));
        // Node ids are stable across serialization within one session.
        expect(animation.channels.single.target, node);
        // The payload manifest survives; the bytes ride in a .fsceneb
        // sidecar (see saveFscene).
        expect(restored.payload(animation.channels.single.timeline), isNotNull);
        expect(
          restored.payload(animation.channels.single.keyframes),
          isNotNull,
        );

        // The full byte-faithful form round trips through the container.
        final container = Uint8List.fromList(writeFsceneb(source.doc));
        final withBytes = readFsceneb(container);
        final (times, values) = _channelData(
          withBytes,
          withBytes.animations[animationId]!,
          node,
          AnimationProperty.translation,
        );
        expect(times, [0.0, 1.0]);
        expect(values[1][1], 3.0);
      });
    });
  });

  group('fsceneb sidecar', () {
    test('writeFsceneb embeds keyframe payloads readFsceneb restores', () {
      final source = _harness();
      _run(source, 'createAnimation', {});
      final animationId = source.doc.animations.keys.single;
      final node = _addCube(source, 'Cube');
      _run(source, 'setAnimationKeyframe', {
        'animationId': animationId.toToken(),
        'nodeId': node.toToken(),
        'property': 'rotation',
        'time': 0.5,
        'rotation': {'x': 0.0, 'y': 0.0, 'z': 0.0, 'w': 1.0},
      });

      final bytes = Uint8List.fromList(writeFsceneb(source.doc));
      final restored = readFsceneb(bytes);
      final animation = restored.animations[animationId]!;
      final (times, rotations) = _channelData(
        restored,
        animation,
        node,
        AnimationProperty.rotation,
      );
      expect(times.single, closeTo(0.5, 1e-6));
      expect(rotations.single, [0.0, 0.0, 0.0, 1.0]);
    });
  });

  group('euler rotation input', () {
    test('setNodeTransform converts degrees to a quaternion', () async {
      final h = _harness();
      final node = _addCube(h, 'Cube');
      _run(h, 'setNodeTransform', {
        'nodeId': node.toToken(),
        'rotationEuler': {'yaw': 90.0, 'pitch': 0.0, 'roll': 0.0},
      });
      final trs = h.doc.node(node)!.transform as TrsTransform;
      // Compose through the same path the engine renders with.
      final matrix = Matrix4.compose(
        Vector3.zero(),
        trs.rotation,
        Vector3(1, 1, 1),
      );
      // A +90 degree yaw around Y (right-handed) maps +X onto -Z.
      final rotated = matrix.transformed3(Vector3(1, 0, 0));
      expect(rotated.x, closeTo(0.0, 1e-6));
      expect(rotated.y, closeTo(0.0, 1e-6));
      expect(rotated.z, closeTo(-1.0, 1e-6));
    });

    test('setAnimationKeyframe accepts rotationEuler keys', () async {
      final h = _harness();
      final node = _addCube(h, 'Cube');
      _run(h, 'createAnimation', {'name': 'Spin'});
      final animationId = h.doc.animations.keys.last;
      _run(h, 'setAnimationKeyframe', {
        'animationId': animationId.toToken(),
        'nodeId': node.toToken(),
        'property': 'rotation',
        'time': 1.0,
        'rotationEuler': {'yaw': 180.0, 'pitch': 0.0, 'roll': 0.0},
      });
      final animation = h.doc.animations[animationId]!;
      final (times, rotations) = _channelData(
        h.doc,
        animation,
        node,
        AnimationProperty.rotation,
      );
      expect(times.single, closeTo(1.0, 1e-6));
      // A 180 degree yaw about Y is (0, 1, 0, ~0).
      expect(rotations.single[0], closeTo(0.0, 1e-6));
      expect(rotations.single[1], closeTo(1.0, 1e-6));
      expect(rotations.single[3], closeTo(0.0, 1e-6));
    });

    test('passing both rotation forms fails loudly', () async {
      final h = _harness();
      final node = _addCube(h, 'Cube');
      _run(h, 'createAnimation', {'name': 'Spin'});
      final animationId = h.doc.animations.keys.last;
      expect(
        () => _run(h, 'setAnimationKeyframe', {
          'animationId': animationId.toToken(),
          'nodeId': node.toToken(),
          'property': 'rotation',
          'time': 0.0,
          'rotation': {'x': 0.0, 'y': 0.0, 'z': 0.0, 'w': 1.0},
          'rotationEuler': {'yaw': 0.0, 'pitch': 0.0, 'roll': 0.0},
        }),
        throwsA(
          isA<CommandException>().having(
            (e) => e.message,
            'message',
            contains('not both'),
          ),
        ),
      );
    });
  });

  group('batch keyframes', () {
    test('setAnimationKeyframes writes many keys in one transaction', () {
      final h = _harness();
      final node = _addCube(h, 'Cube');
      _run(h, 'createAnimation', {'name': 'Bounce'});
      final animationId = h.doc.animations.keys.last;
      _run(h, 'setAnimationKeyframes', {
        'animationId': animationId.toToken(),
        'nodeId': node.toToken(),
        'property': 'translation',
        'keys': [
          {
            'time': 1.0,
            'translation': {'x': 0.0, 'y': 0.0, 'z': 0.0},
          },
          {
            'time': 0.0,
            'translation': {'x': 0.0, 'y': 2.0, 'z': 0.0},
          },
          {
            'time': 0.5,
            'translation': {'x': 0.0, 'y': 4.0, 'z': 0.0},
          },
        ],
      });
      final animation = h.doc.animations[animationId]!;
      final (times, values) = _channelData(
        h.doc,
        animation,
        node,
        AnimationProperty.translation,
      );
      // Unsorted input lands sorted.
      expect(times, [
        closeTo(0.0, 1e-6),
        closeTo(0.5, 1e-6),
        closeTo(1.0, 1e-6),
      ]);
      expect(values[0], [0.0, 2.0, 0.0]);
      expect(values[1], [0.0, 4.0, 0.0]);
      expect(values[2], [0.0, 0.0, 0.0]);
    });

    test('omitted components capture the current pose per key', () {
      final h = _harness();
      final node = _addCube(h, 'Cube');
      _run(h, 'createAnimation', {'name': 'Drift'});
      final animationId = h.doc.animations.keys.last;
      _run(h, 'setNodeTransform', {
        'nodeId': node.toToken(),
        'translation': {'x': 3.0, 'y': 0.0, 'z': 0.0},
      });
      _run(h, 'setAnimationKeyframes', {
        'animationId': animationId.toToken(),
        'nodeId': node.toToken(),
        'property': 'translation',
        'keys': [
          {'time': 0.0},
          {
            'time': 1.0,
            'translation': {'x': -3.0, 'y': 0.0, 'z': 0.0},
          },
        ],
      });
      final animation = h.doc.animations[animationId]!;
      final (_, values) = _channelData(
        h.doc,
        animation,
        node,
        AnimationProperty.translation,
      );
      expect(values[0], [3.0, 0.0, 0.0]);
      expect(values[1], [-3.0, 0.0, 0.0]);
    });

    test('empty or non-list "keys" is rejected', () {
      final h = _harness();
      final node = _addCube(h, 'Cube');
      _run(h, 'createAnimation', {'name': 'X'});
      final animationId = h.doc.animations.keys.last;
      for (final bad in [<Object>[], 'nope']) {
        expect(
          () => _run(h, 'setAnimationKeyframes', {
            'animationId': animationId.toToken(),
            'nodeId': node.toToken(),
            'property': 'translation',
            'keys': bad,
          }),
          throwsA(isA<CommandException>()),
        );
      }
    });
  });

  group('key pose', () {
    test('keys all three channels of several nodes in one transaction', () {
      final h = _harness();
      final a = _addCube(h, 'A');
      final b = _addCube(h, 'B');
      // Pose A and B differently.
      _run(h, 'setNodeTransform', {
        'nodeId': a.toToken(),
        'translation': {'x': 1.0, 'y': 2.0, 'z': 3.0},
        'rotationEuler': {'yaw': 90.0, 'pitch': 0.0, 'roll': 0.0},
        'scale': {'x': 2.0, 'y': 2.0, 'z': 2.0},
      });
      _run(h, 'setNodeTransform', {
        'nodeId': b.toToken(),
        'translation': {'x': -1.0, 'y': 0.0, 'z': 0.0},
      });
      _run(h, 'createAnimation', {'name': 'Clip'});
      final animationId = h.doc.animations.keys.last;

      _run(h, 'keyPose', {
        'animationId': animationId.toToken(),
        'time': 0.5,
        'nodeIds': [a.toToken(), b.toToken()],
      });

      final animation = h.doc.animations[animationId]!;
      for (final node in [a, b]) {
        for (final property in AnimationProperty.values) {
          if (property == AnimationProperty.weights) continue;
          final (times, values) = _channelData(
            h.doc,
            animation,
            node,
            property,
          );
          expect(times, hasLength(1), reason: '$node/$property');
          expect(times.single, closeTo(0.5, 1e-6));
          expect(
            values.single,
            hasLength(property == AnimationProperty.rotation ? 4 : 3),
          );
        }
      }
      final (aTimes, aTranslations) = _channelData(
        h.doc,
        animation,
        a,
        AnimationProperty.translation,
      );
      expect(aTranslations.single, [1.0, 2.0, 3.0]);
    });

    test('an unknown node fails without keying anything', () {
      final h = _harness();
      final good = _addCube(h, 'Good');
      _run(h, 'createAnimation', {'name': 'Clip'});
      final animationId = h.doc.animations.keys.last;
      expect(
        () => _run(h, 'keyPose', {
          'animationId': animationId.toToken(),
          'time': 0.0,
          'nodeIds': [good.toToken(), '0000000100000999'],
        }),
        throwsA(isA<CommandException>()),
      );
      expect(h.doc.animations[animationId]!.channels, isEmpty);
    });

    test('undo removes every channel the pose keyed at once', () {
      final h = _harness();
      final node = _addCube(h, 'Cube');
      _run(h, 'setNodeTransform', {
        'nodeId': node.toToken(),
        'translation': {'x': 1.0, 'y': 1.0, 'z': 1.0},
      });
      _run(h, 'createAnimation', {'name': 'Clip'});
      final animationId = h.doc.animations.keys.last;
      _run(h, 'keyPose', {
        'animationId': animationId.toToken(),
        'time': 0.0,
        'nodeIds': [node.toToken()],
      });
      expect(h.doc.animations[animationId]!.channels, hasLength(3));
      h.history.undo();
      expect(h.doc.animations[animationId]!.channels, isEmpty);
    });
  });

  test('undo removes the whole batch at once', () {
    final h = _harness();
    final node = _addCube(h, 'Cube');
    _run(h, 'createAnimation', {'name': 'Bounce'});
    final animationId = h.doc.animations.keys.last;
    _run(h, 'setAnimationKeyframes', {
      'animationId': animationId.toToken(),
      'nodeId': node.toToken(),
      'property': 'translation',
      'keys': [
        {
          'time': 0.0,
          'translation': {'x': 0.0, 'y': 1.0, 'z': 0.0},
        },
        {
          'time': 1.0,
          'translation': {'x': 0.0, 'y': 0.0, 'z': 0.0},
        },
      ],
    });
    h.history.undo();
    final animation = h.doc.animations[animationId]!;
    expect(animation.channels.where((c) => c.target == node), isEmpty);
  });

  group('removeChannel', () {
    Map<String, Object?> translateKey(
      String animationToken,
      LocalId node,
      double t,
      double y,
    ) => {
      'animationId': animationToken,
      'nodeId': node.toToken(),
      'property': 'translation',
      'time': t,
      'translation': {'x': 0.0, 'y': y, 'z': 0.0},
    };

    test('drops one path, keeps sibling paths of the same bone', () {
      final h = _harness();
      final node = _addCube(h, 'Bone');
      _run(h, 'createAnimation', {'name': 'Spin'});
      final animationId = h.doc.animations.keys.single;
      // A moving translation path plus a scale path the author keeps.
      for (final t in const [0.0, 1.0]) {
        _run(h, 'setAnimationKeyframe', translateKey(animationId.toToken(), node, t, t));
        _run(h, 'setAnimationKeyframe', {
          'animationId': animationId.toToken(),
          'nodeId': node.toToken(),
          'property': 'scale',
          'time': t,
          'scale': {'x': 1.0, 'y': 1.0, 'z': 1.0},
        });
      }

      _run(h, 'removeChannel', {
        'animationId': animationId.toToken(),
        'nodeId': node.toToken(),
        'property': 'translation',
      });

      final animation = h.doc.animations[animationId]!;
      expect(animation.channels.map((c) => c.property.name), ['scale']);
    });

    test('is undoable', () {
      final h = _harness();
      final node = _addCube(h, 'Bone');
      _run(h, 'createAnimation', {'name': 'Spin'});
      final animationId = h.doc.animations.keys.single;
      _run(
        h,
        'setAnimationKeyframe',
        translateKey(animationId.toToken(), node, 0.0, 0.0),
      );
      _run(h, 'setAnimationKeyframe', {
        'animationId': animationId.toToken(),
        'nodeId': node.toToken(),
        'property': 'scale',
        'time': 0.0,
      });
      expect(h.doc.animations[animationId]!.channels, hasLength(2));
      _run(h, 'removeChannel', {
        'animationId': animationId.toToken(),
        'nodeId': node.toToken(),
        'property': 'translation',
      });
      expect(h.doc.animations[animationId]!.channels, hasLength(1));

      expect(h.history.undo(), isTrue);
      expect(h.doc.animations[animationId]!.channels, hasLength(2));
    });

    test('removing the last channel removes the animation', () {
      final h = _harness();
      final node = _addCube(h, 'Bone');
      _run(h, 'createAnimation', {'name': 'Spin'});
      final animationId = h.doc.animations.keys.single;
      _run(
        h,
        'setAnimationKeyframe',
        translateKey(animationId.toToken(), node, 0.0, 0.0),
      );

      _run(h, 'removeChannel', {
        'animationId': animationId.toToken(),
        'nodeId': node.toToken(),
        'property': 'translation',
      });

      expect(h.doc.animations.containsKey(animationId), isFalse);
    });

    test('rejects an unknown path', () {
      final h = _harness();
      final node = _addCube(h, 'Bone');
      _run(h, 'createAnimation', {'name': 'Spin'});
      final animationId = h.doc.animations.keys.single;
      expect(
        () => _run(h, 'removeChannel', {
          'animationId': animationId.toToken(),
          'nodeId': node.toToken(),
          'property': 'rotation',
        }),
        throwsA(isA<CommandException>()),
      );
    });
  });

  group('cleanAnimationChannels', () {
    test('keeps moving paths and drops constant ones and dead targets', () {
      final h = _harness();
      final mover = _addCube(h, 'Mover');
      final still = _addCube(h, 'Still');
      final doomed = _addCube(h, 'Doomed');
      _run(h, 'createAnimation', {'name': 'Show'});
      final animationId = h.doc.animations.keys.single;
      final token = animationId.toToken();

      // The one path worth keeping: translation actually varies.
      _run(h, 'setAnimationKeyframe', {
        'animationId': token,
        'nodeId': mover.toToken(),
        'property': 'translation',
        'time': 0.0,
        'translation': {'x': 0.0, 'y': 0.0, 'z': 0.0},
      });
      _run(h, 'setAnimationKeyframe', {
        'animationId': token,
        'nodeId': mover.toToken(),
        'property': 'translation',
        'time': 1.0,
        'translation': {'x': 5.0, 'y': 0.0, 'z': 0.0},
      });
      // Constant keys — captured by Keying without ever touching the pose.
      for (final time in const [0.0, 1.0]) {
        _run(h, 'setAnimationKeyframe', {
          'animationId': token,
          'nodeId': still.toToken(),
          'property': 'rotation',
          'time': time,
        });
      }
      // Keys on a node that is about to disappear become dead weight.
      _run(h, 'setAnimationKeyframe', {
        'animationId': token,
        'nodeId': doomed.toToken(),
        'property': 'scale',
        'time': 0.0,
      });
      _run(h, 'deleteNode', {'nodeId': doomed.toToken()});

      _run(h, 'cleanAnimationChannels', {'animationId': token});

      final animation = h.doc.animations[animationId]!;
      expect(animation.channels, hasLength(1));
      expect(animation.channels.single.target, mover);
      expect(
        animation.channels.single.property,
        AnimationProperty.translation,
      );

      // Undo restores every dropped path at once.
      expect(h.history.undo(), isTrue);
      expect(h.doc.animations[animationId]!.channels, hasLength(3));
    });

    test('rejects the edit when nothing is unused', () {
      final h = _harness();
      final node = _addCube(h, 'Mover');
      _run(h, 'createAnimation', {'name': 'Show'});
      final token = h.doc.animations.keys.single.toToken();
      _run(h, 'setAnimationKeyframe', {
        'animationId': token,
        'nodeId': node.toToken(),
        'property': 'translation',
        'time': 0.0,
        'translation': {'x': 0.0, 'y': 0.0, 'z': 0.0},
      });
      _run(h, 'setAnimationKeyframe', {
        'animationId': token,
        'nodeId': node.toToken(),
        'property': 'translation',
        'time': 1.0,
        'translation': {'x': 3.0, 'y': 0.0, 'z': 0.0},
      });
      expect(
        () => _run(h, 'cleanAnimationChannels', {'animationId': token}),
        throwsA(isA<CommandException>()),
      );
    });
  });
}
