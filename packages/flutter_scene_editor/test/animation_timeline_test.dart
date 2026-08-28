// The Animation panel's model: decoding a clip's channels out of a document,
// and the timeline arithmetic the sheet is drawn and hit-tested with. All
// GPU-free, which is the point of keeping it out of the panel widget.

import 'dart:typed_data';

import 'package:flutter_scene_editor/src/panels/animation_timeline_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scene/scene.dart';

Uint8List _bytes(List<double> values) {
  final floats = Float32List.fromList(values);
  return Uint8List.view(
    floats.buffer,
    floats.offsetInBytes,
    floats.lengthInBytes,
  );
}

/// A document with two nodes and one clip: the first node translated and
/// scaled, the second rotated.
({SceneDocument doc, AnimationSpec clip}) sceneWithClip() {
  final doc = SceneDocument();
  final cube = doc.createNode(name: 'Cube', root: true);
  final lamp = doc.createNode(name: 'Lamp', root: true);

  LocalId payload(List<double> values) => doc
      .addPayload(
        PayloadSpec(
          doc.newId(),
          encoding: PayloadEncoding.floats,
          length: values.length,
          bytes: _bytes(values),
        ),
      )
      .id;

  final clip = doc.addAnimation(
    AnimationSpec(
      doc.newId(),
      name: 'Idle',
      channels: [
        AnimationChannelSpec(
          target: cube.id,
          targetName: 'Cube',
          property: AnimationProperty.translation,
          timeline: payload(const [0, 1, 2]),
          keyframes: payload(const [0, 0, 0, 1, 2, 3, 4, 5, 6]),
        ),
        AnimationChannelSpec(
          target: lamp.id,
          targetName: 'Lamp',
          property: AnimationProperty.rotation,
          timeline: payload(const [0, 0.5]),
          keyframes: payload(const [0, 0, 0, 1, 0, 1, 0, 0]),
        ),
        AnimationChannelSpec(
          target: cube.id,
          targetName: 'Cube',
          property: AnimationProperty.scale,
          timeline: payload(const [1.5]),
          keyframes: payload(const [2, 2, 2]),
        ),
      ],
    ),
  );
  return (doc: doc, clip: clip);
}

void main() {
  group('buildAnimationTimeline', () {
    test('decodes each channel with the right stride', () {
      final scene = sceneWithClip();
      final timeline = buildAnimationTimeline(scene.doc, scene.clip);

      expect(timeline.name, 'Idle');
      expect(timeline.tracks, hasLength(3));
      expect(timeline.tracks[0].stride, 3, reason: 'translation');
      expect(timeline.tracks[1].stride, 4, reason: 'rotation');
      expect(timeline.tracks[2].stride, 3, reason: 'scale');
      expect(timeline.tracks[0].times, [0, 1, 2]);
      expect(timeline.tracks[0].valueAt(1, 1), 2);
    });

    test('a channel keeps its index, which is how commands address it', () {
      final timeline = buildAnimationTimeline(
        sceneWithClip().doc,
        sceneWithClip().clip,
      );
      expect([for (final t in timeline.tracks) t.channelIndex], [0, 1, 2]);
    });

    test('targets group in first-appearance order, not alphabetically', () {
      final scene = sceneWithClip();
      final timeline = buildAnimationTimeline(scene.doc, scene.clip);
      // Cube appears first even though its second channel comes last, and
      // Lamp keeps the slot its channel was authored in.
      expect(timeline.targets, ['Cube', 'Lamp']);
      expect(
        [for (final t in timeline.tracksFor('Cube')) t.property],
        [AnimationProperty.translation, AnimationProperty.scale],
      );
    });

    test('the label falls back through the name to the id token', () {
      final doc = SceneDocument();
      final missing = doc.newId();
      final clip = doc.addAnimation(
        AnimationSpec(
          doc.newId(),
          channels: [
            AnimationChannelSpec(
              target: missing,
              targetName: 'Ghost',
              property: AnimationProperty.translation,
              timeline: doc.newId(),
              keyframes: doc.newId(),
            ),
            AnimationChannelSpec(
              target: missing,
              property: AnimationProperty.scale,
              timeline: doc.newId(),
              keyframes: doc.newId(),
            ),
          ],
        ),
      );
      final timeline = buildAnimationTimeline(doc, clip);
      expect(timeline.tracks[0].targetName, 'Ghost');
      expect(timeline.tracks[1].targetName, missing.toToken());
    });

    test('endTime is the last key across every channel', () {
      final scene = sceneWithClip();
      expect(buildAnimationTimeline(scene.doc, scene.clip).endTime, 2);
    });

    test('keyTimes merges and sorts every channel', () {
      final scene = sceneWithClip();
      expect(buildAnimationTimeline(scene.doc, scene.clip).keyTimes, [
        0,
        0.5,
        1,
        1.5,
        2,
      ]);
    });

    test('a missing payload decodes as an empty channel, not a crash', () {
      final doc = SceneDocument();
      final node = doc.createNode(name: 'A', root: true);
      final clip = doc.addAnimation(
        AnimationSpec(
          doc.newId(),
          channels: [
            AnimationChannelSpec(
              target: node.id,
              property: AnimationProperty.translation,
              timeline: doc.newId(),
              keyframes: doc.newId(),
            ),
          ],
        ),
      );
      final timeline = buildAnimationTimeline(doc, clip);
      expect(timeline.tracks.single.times, isEmpty);
      expect(timeline.endTime, 0);
    });

    test('an empty weights channel reports no stride to read', () {
      final doc = SceneDocument();
      final node = doc.createNode(name: 'A', root: true);
      final clip = doc.addAnimation(
        AnimationSpec(
          doc.newId(),
          channels: [
            AnimationChannelSpec(
              target: node.id,
              property: AnimationProperty.weights,
              timeline: doc.newId(),
              keyframes: doc.newId(),
            ),
          ],
        ),
      );
      expect(buildAnimationTimeline(doc, clip).tracks.single.stride, 0);
    });
  });

  group('keyStride', () {
    test('a weights channel reads its width off the data', () {
      expect(keyStride(AnimationProperty.weights, 4, 12), 3);
      expect(keyStride(AnimationProperty.weights, 0, 0), 0);
    });

    test('the transform channels are fixed', () {
      expect(keyStride(AnimationProperty.translation, 9, 99), 3);
      expect(keyStride(AnimationProperty.rotation, 9, 99), 4);
      expect(keyStride(AnimationProperty.scale, 9, 99), 3);
    });
  });

  group('snapToSamples', () {
    test('lands a time on a whole frame', () {
      expect(snapToSamples(0.333, 60), closeTo(20 / 60, 1e-9));
      expect(snapToSamples(1.004, 24), closeTo(24 / 24, 1e-9));
    });

    test('a rate of zero or less leaves the time alone', () {
      expect(snapToSamples(0.333, 0), 0.333);
      expect(snapToSamples(0.333, -1), 0.333);
    });
  });

  group('majorTickStep', () {
    test('ticks stay at least the minimum distance apart at every zoom', () {
      for (final zoom in const [8.0, 30.0, 120.0, 600.0, 2000.0]) {
        final step = majorTickStep(pixelsPerSecond: zoom, sampleRate: 60);
        expect(
          step * zoom,
          greaterThanOrEqualTo(60 - 1e-9),
          reason: 'at $zoom px/s',
        );
      }
    });

    test('the step is a round number of seconds on a 1-2-5 ladder', () {
      expect(majorTickStep(pixelsPerSecond: 120, sampleRate: 60), 0.5);
      expect(majorTickStep(pixelsPerSecond: 60, sampleRate: 60), 1.0);
      expect(majorTickStep(pixelsPerSecond: 50, sampleRate: 60), 2.0);
      expect(majorTickStep(pixelsPerSecond: 20, sampleRate: 60), 5.0);
      expect(majorTickStep(pixelsPerSecond: 5, sampleRate: 60), 20.0);
    });

    test('zoomed far in it bottoms out at one tick per sample', () {
      // A finer division would label times that cannot be keyed.
      expect(
        majorTickStep(pixelsPerSecond: 100000, sampleRate: 60),
        closeTo(1 / 60, 1e-12),
      );
    });

    test('a degenerate zoom does not divide by zero', () {
      expect(majorTickStep(pixelsPerSecond: 0, sampleRate: 60), 1);
    });
  });

  group('formatTimelineLabel', () {
    test('formats whole seconds as m:ss', () {
      expect(formatTimelineLabel(0), '0:00');
      expect(formatTimelineLabel(5), '0:05');
      expect(formatTimelineLabel(75), '1:15');
    });

    test('appends hundredths only when the tick is finer than a second', () {
      expect(formatTimelineLabel(1.25), '0:01.25');
      expect(formatTimelineLabel(2.0), '0:02');
    });
  });

  group('nearestKeyIndex', () {
    final times = Float32List.fromList(const [0, 1, 2]);

    test('grabs the key under the pointer', () {
      expect(nearestKeyIndex(times, 1.01, pixelsPerSecond: 100), 1);
    });

    test('the grab radius is in pixels, so it holds at any zoom', () {
      // 0.1s from the key: inside 6px at 100px/s (10px away? no, 10 > 6).
      expect(nearestKeyIndex(times, 1.1, pixelsPerSecond: 100), isNull);
      // The same 0.1s is well inside the radius once zoomed out.
      expect(nearestKeyIndex(times, 1.1, pixelsPerSecond: 10), 1);
    });

    test('an empty channel has nothing to grab', () {
      expect(nearestKeyIndex(Float32List(0), 0, pixelsPerSecond: 100), isNull);
    });
  });

  group('adjacentKeyTime', () {
    const times = [0.0, 1.0, 2.0];

    test('steps to the next and previous key', () {
      expect(adjacentKeyTime(times, 0.5, forward: true), 1.0);
      expect(adjacentKeyTime(times, 1.5, forward: false), 1.0);
    });

    test('sitting exactly on a key steps past it rather than sticking', () {
      expect(adjacentKeyTime(times, 1.0, forward: true), 2.0);
      expect(adjacentKeyTime(times, 1.0, forward: false), 0.0);
    });

    test('past the end it clamps rather than running off', () {
      expect(adjacentKeyTime(times, 9.0, forward: true), 2.0);
      expect(adjacentKeyTime(times, -9.0, forward: false), 0.0);
    });

    test('no keys means nowhere to jump', () {
      expect(adjacentKeyTime(const [], 0, forward: true), isNull);
    });
  });
}
