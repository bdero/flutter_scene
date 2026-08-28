// The animation authoring commands. Keyframe edits rewrite the channel's
// float payloads, so the load-bearing checks are that times stay sorted with
// their values carried alongside, that a payload two channels share is cloned
// before one of them is rewritten, and that every edit reverts cleanly.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_scene_editor_core/flutter_scene_editor_core.dart';
import 'package:scene/scene.dart';
import 'package:test/test.dart';

/// A document with one node and one animation translating it over three keys.
({SceneDocument doc, LocalId node, LocalId animation}) sceneWithClip({
  List<double> times = const [0.0, 1.0, 2.0],
  List<double> values = const [
    0, 0, 0, //
    1, 0, 0, //
    2, 0, 0,
  ],
}) {
  final doc = SceneDocument();
  final node = doc.createNode(name: 'Cube', root: true);
  final timeline = doc.addPayload(
    PayloadSpec(
      doc.newId(),
      encoding: PayloadEncoding.floats,
      length: times.length,
      bytes: _bytes(times),
    ),
  );
  final keyframes = doc.addPayload(
    PayloadSpec(
      doc.newId(),
      encoding: PayloadEncoding.floats,
      length: values.length,
      bytes: _bytes(values),
    ),
  );
  final animation = doc.addAnimation(
    AnimationSpec(
      doc.newId(),
      name: 'Idle',
      channels: [
        AnimationChannelSpec(
          target: node.id,
          targetName: 'Cube',
          property: AnimationProperty.translation,
          timeline: timeline.id,
          keyframes: keyframes.id,
        ),
      ],
    ),
  );
  return (doc: doc, node: node.id, animation: animation.id);
}

Uint8List _bytes(List<double> values) {
  final floats = Float32List.fromList(values);
  return Uint8List.view(floats.buffer, floats.offsetInBytes, floats.lengthInBytes);
}

List<double> floatsOf(SceneDocument doc, LocalId payload) {
  final bytes = doc.payload(payload)!.bytes!;
  return Float32List.view(
    bytes.buffer,
    bytes.offsetInBytes,
    bytes.lengthInBytes ~/ 4,
  ).toList();
}

AnimationChannelSpec channelOf(SceneDocument doc, LocalId animation) =>
    doc.animations[animation]!.channels.single;

List<double> timesOf(SceneDocument doc, LocalId animation) =>
    floatsOf(doc, channelOf(doc, animation).timeline);

List<double> valuesOf(SceneDocument doc, LocalId animation) =>
    floatsOf(doc, channelOf(doc, animation).keyframes);

void main() {
  group('clip and channel lifecycle', () {
    test('createAnimation adds an empty, named clip', () {
      final doc = SceneDocument();
      final session = EditorSession(doc);
      session.run(createAnimation.name, {'name': 'Walk'});
      expect(doc.animations.values.single.name, 'Walk');
      expect(doc.animations.values.single.channels, isEmpty);
    });

    test('renameAnimation keeps the channels', () {
      final scene = sceneWithClip();
      final session = EditorSession(scene.doc);
      session.run(renameAnimation.name, {
        'animationId': scene.animation.toToken(),
        'name': 'Run',
      });
      expect(scene.doc.animations[scene.animation]!.name, 'Run');
      expect(scene.doc.animations[scene.animation]!.channels, hasLength(1));
    });

    test('deleteAnimation removes the clip and undo brings it back', () {
      final scene = sceneWithClip();
      final session = EditorSession(scene.doc);
      session.run(deleteAnimation.name, {
        'animationId': scene.animation.toToken(),
      });
      expect(scene.doc.animations, isEmpty);
      session.history.undo();
      expect(scene.doc.animations[scene.animation]!.name, 'Idle');
    });

    test('addAnimationChannel mints its two empty payloads', () {
      final scene = sceneWithClip();
      final session = EditorSession(scene.doc);
      session.run(addAnimationChannel.name, {
        'animationId': scene.animation.toToken(),
        'nodeId': scene.node.toToken(),
        'property': 'rotation',
      });
      final channels = scene.doc.animations[scene.animation]!.channels;
      expect(channels, hasLength(2));
      expect(channels[1].property, AnimationProperty.rotation);
      expect(scene.doc.payload(channels[1].timeline)!.bytes, isEmpty);
    });

    test('an unknown property is refused rather than guessed', () {
      final scene = sceneWithClip();
      final session = EditorSession(scene.doc);
      expect(
        () => session.run(addAnimationChannel.name, {
          'animationId': scene.animation.toToken(),
          'nodeId': scene.node.toToken(),
          'property': 'colour',
        }),
        throwsA(isA<CommandException>()),
      );
    });

    test('removeAnimationChannel drops just that channel', () {
      final scene = sceneWithClip();
      final session = EditorSession(scene.doc);
      session.run(addAnimationChannel.name, {
        'animationId': scene.animation.toToken(),
        'nodeId': scene.node.toToken(),
        'property': 'scale',
      });
      session.run(removeAnimationChannel.name, {
        'animationId': scene.animation.toToken(),
        'channel': 0,
      });
      final channels = scene.doc.animations[scene.animation]!.channels;
      expect(channels, hasLength(1));
      expect(channels.single.property, AnimationProperty.scale);
    });
  });

  group('setAnimationKeyTime', () {
    test('moves a key within its neighbours', () {
      final scene = sceneWithClip();
      final session = EditorSession(scene.doc);
      session.run(setAnimationKeyTime.name, {
        'animationId': scene.animation.toToken(),
        'channel': 0,
        'key': 1,
        'time': 0.25,
      });
      expect(timesOf(scene.doc, scene.animation), [0.0, 0.25, 2.0]);
      expect(valuesOf(scene.doc, scene.animation), [0, 0, 0, 1, 0, 0, 2, 0, 0]);
    });

    test('a key dragged past its neighbour carries its value with it', () {
      final scene = sceneWithClip();
      final session = EditorSession(scene.doc);
      // Drag the first key (value 0) past the second (value 1).
      session.run(setAnimationKeyTime.name, {
        'animationId': scene.animation.toToken(),
        'channel': 0,
        'key': 0,
        'time': 1.5,
      });
      expect(timesOf(scene.doc, scene.animation), [1.0, 1.5, 2.0]);
      // The value that was at t=0 is now the middle key, not left behind.
      expect(valuesOf(scene.doc, scene.animation), [1, 0, 0, 0, 0, 0, 2, 0, 0]);
    });

    test('a negative time clamps to the start of the clip', () {
      final scene = sceneWithClip();
      final session = EditorSession(scene.doc);
      session.run(setAnimationKeyTime.name, {
        'animationId': scene.animation.toToken(),
        'channel': 0,
        'key': 1,
        'time': -5.0,
      });
      expect(timesOf(scene.doc, scene.animation).first, 0.0);
    });

    test('an out-of-range key is refused', () {
      final scene = sceneWithClip();
      final session = EditorSession(scene.doc);
      expect(
        () => session.run(setAnimationKeyTime.name, {
          'animationId': scene.animation.toToken(),
          'channel': 0,
          'key': 9,
          'time': 1.0,
        }),
        throwsA(isA<CommandException>()),
      );
    });

    test('undo restores the timeline byte for byte', () {
      final scene = sceneWithClip();
      final before = timesOf(scene.doc, scene.animation);
      final session = EditorSession(scene.doc);
      session.run(setAnimationKeyTime.name, {
        'animationId': scene.animation.toToken(),
        'channel': 0,
        'key': 1,
        'time': 1.75,
      });
      session.history.undo();
      expect(timesOf(scene.doc, scene.animation), before);
    });
  });

  group('setAnimationKeyValue', () {
    test('replaces just that key', () {
      final scene = sceneWithClip();
      final session = EditorSession(scene.doc);
      session.run(setAnimationKeyValue.name, {
        'animationId': scene.animation.toToken(),
        'channel': 0,
        'key': 1,
        'value': encodeAnimationValues([5, 6, 7]),
      });
      expect(valuesOf(scene.doc, scene.animation), [0, 0, 0, 5, 6, 7, 2, 0, 0]);
    });

    test('a value of the wrong width is refused', () {
      final scene = sceneWithClip();
      final session = EditorSession(scene.doc);
      expect(
        () => session.run(setAnimationKeyValue.name, {
          'animationId': scene.animation.toToken(),
          'channel': 0,
          'key': 1,
          'value': encodeAnimationValues([5, 6]),
        }),
        throwsA(isA<CommandException>()),
      );
    });
  });

  group('insertAnimationKey', () {
    test('samples the curve so the pose does not move', () {
      final scene = sceneWithClip();
      final session = EditorSession(scene.doc);
      session.run(insertAnimationKey.name, {
        'animationId': scene.animation.toToken(),
        'channel': 0,
        'time': 0.5,
      });
      expect(timesOf(scene.doc, scene.animation), [0.0, 0.5, 1.0, 2.0]);
      // Halfway between (0,0,0) and (1,0,0).
      expect(valuesOf(scene.doc, scene.animation).sublist(3, 6), [0.5, 0, 0]);
    });

    test('an explicit value overrides the sample', () {
      final scene = sceneWithClip();
      final session = EditorSession(scene.doc);
      session.run(insertAnimationKey.name, {
        'animationId': scene.animation.toToken(),
        'channel': 0,
        'time': 0.5,
        'value': encodeAnimationValues([9, 9, 9]),
      });
      expect(valuesOf(scene.doc, scene.animation).sublist(3, 6), [9, 9, 9]);
    });

    test('a key at an existing time replaces it rather than doubling up', () {
      final scene = sceneWithClip();
      final session = EditorSession(scene.doc);
      session.run(insertAnimationKey.name, {
        'animationId': scene.animation.toToken(),
        'channel': 0,
        'time': 1.0,
        'value': encodeAnimationValues([4, 4, 4]),
      });
      expect(timesOf(scene.doc, scene.animation), [0.0, 1.0, 2.0]);
      expect(valuesOf(scene.doc, scene.animation).sublist(3, 6), [4, 4, 4]);
    });

    test('past the last key it holds the last value', () {
      final scene = sceneWithClip();
      final session = EditorSession(scene.doc);
      session.run(insertAnimationKey.name, {
        'animationId': scene.animation.toToken(),
        'channel': 0,
        'time': 5.0,
      });
      expect(timesOf(scene.doc, scene.animation), [0.0, 1.0, 2.0, 5.0]);
      expect(valuesOf(scene.doc, scene.animation).sublist(9), [2, 0, 0]);
    });

    test('an empty weights channel needs its first value to fix the width', () {
      final scene = sceneWithClip();
      final session = EditorSession(scene.doc);
      session.run(addAnimationChannel.name, {
        'animationId': scene.animation.toToken(),
        'nodeId': scene.node.toToken(),
        'property': 'weights',
      });
      expect(
        () => session.run(insertAnimationKey.name, {
          'animationId': scene.animation.toToken(),
          'channel': 1,
          'time': 0.0,
        }),
        throwsA(isA<CommandException>()),
      );
      session.run(insertAnimationKey.name, {
        'animationId': scene.animation.toToken(),
        'channel': 1,
        'time': 0.0,
        'value': encodeAnimationValues([0.25, 0.75]),
      });
      final channel = scene.doc.animations[scene.animation]!.channels[1];
      expect(floatsOf(scene.doc, channel.keyframes), [0.25, 0.75]);
    });
  });

  test('deleteAnimationKey removes the key and its value together', () {
    final scene = sceneWithClip();
    final session = EditorSession(scene.doc);
    session.run(deleteAnimationKey.name, {
      'animationId': scene.animation.toToken(),
      'channel': 0,
      'key': 1,
    });
    expect(timesOf(scene.doc, scene.animation), [0.0, 2.0]);
    expect(valuesOf(scene.doc, scene.animation), [0, 0, 0, 2, 0, 0]);
  });

  group('shared payloads', () {
    /// glTF lets several channels share one sampler input, so a timeline
    /// payload can have more than one reader.
    ({SceneDocument doc, LocalId animation}) sceneWithSharedTimeline() {
      final scene = sceneWithClip();
      final doc = scene.doc;
      final first = doc.animations[scene.animation]!.channels.single;
      final scaleValues = doc.addPayload(
        PayloadSpec(
          doc.newId(),
          encoding: PayloadEncoding.floats,
          length: 9,
          bytes: _bytes(const [1, 1, 1, 2, 2, 2, 3, 3, 3]),
        ),
      );
      doc.animations[scene.animation] = AnimationSpec(
        scene.animation,
        name: 'Idle',
        channels: [
          first,
          AnimationChannelSpec(
            target: scene.node,
            targetName: 'Cube',
            property: AnimationProperty.scale,
            // The same timeline as the translation channel.
            timeline: first.timeline,
            keyframes: scaleValues.id,
          ),
        ],
      );
      return (doc: doc, animation: scene.animation);
    }

    test('retiming one channel does not disturb the other', () {
      final scene = sceneWithSharedTimeline();
      final shared =
          scene.doc.animations[scene.animation]!.channels[0].timeline;
      final session = EditorSession(scene.doc);
      session.run(setAnimationKeyTime.name, {
        'animationId': scene.animation.toToken(),
        'channel': 0,
        'key': 1,
        'time': 0.5,
      });

      final channels = scene.doc.animations[scene.animation]!.channels;
      expect(
        channels[0].timeline,
        isNot(shared),
        reason: 'the edited channel moved onto its own copy',
      );
      expect(
        channels[1].timeline,
        shared,
        reason: 'the other reader kept the original',
      );
      expect(floatsOf(scene.doc, channels[0].timeline), [0.0, 0.5, 2.0]);
      expect(floatsOf(scene.doc, shared), [0.0, 1.0, 2.0]);
    });

    test('the clone is undone along with the edit', () {
      final scene = sceneWithSharedTimeline();
      final shared =
          scene.doc.animations[scene.animation]!.channels[0].timeline;
      final payloadCount = scene.doc.payloads.length;
      final session = EditorSession(scene.doc);
      session.run(setAnimationKeyTime.name, {
        'animationId': scene.animation.toToken(),
        'channel': 0,
        'key': 1,
        'time': 0.5,
      });
      session.history.undo();

      expect(scene.doc.payloads, hasLength(payloadCount));
      expect(
        scene.doc.animations[scene.animation]!.channels[0].timeline,
        shared,
      );
      expect(floatsOf(scene.doc, shared), [0.0, 1.0, 2.0]);
    });
  });

  test('encodeAnimationValues round-trips through base64 float32', () {
    final encoded = encodeAnimationValues([1.5, -2.25, 0]);
    final bytes = base64Decode(encoded);
    expect(
      Float32List.view(bytes.buffer, bytes.offsetInBytes, 3).toList(),
      [1.5, -2.25, 0],
    );
  });
}
