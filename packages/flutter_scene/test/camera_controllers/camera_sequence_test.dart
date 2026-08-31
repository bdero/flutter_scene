// Covers CameraSequence: it drives a director through a shot list on the
// clock, hands the camera back when it ends, and survives frames longer than
// a shot.

import 'package:flutter_scene/scene.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

class _FixedCamera extends CameraController {
  _FixedCamera(this.y);
  final double y;

  @override
  void advance(double deltaSeconds) =>
      setPose(CameraPose.lookAt(Vector3(0.0, y, -10.0), Vector3(0.0, y, 0.0)));
}

({Node node, CameraDirector director}) _rig() {
  final node = Node();
  node.addComponent(CameraComponent());
  final director = CameraDirector(defaultBlend: const CameraBlend.cut());
  node.addComponent(director);
  return (node: node, director: director);
}

void _run(CameraSequence sequence, CameraDirector director, double seconds) {
  const step = 0.05;
  for (var t = 0.0; t < seconds - 1e-9; t += step) {
    sequence.update(step);
    director.update(step);
  }
}

void main() {
  group('CameraSequence', () {
    test('plays shots in order on the clock', () {
      final rig = _rig();
      final a = _FixedCamera(1.0);
      final b = _FixedCamera(2.0);
      final c = _FixedCamera(3.0);
      final sequence = CameraSequence(
        rig.director,
        shots: [
          CameraShot(a, hold: 1.0, blendIn: const CameraBlend.cut()),
          CameraShot(b, hold: 1.0, blendIn: const CameraBlend.cut()),
          CameraShot(c, hold: 1.0, blendIn: const CameraBlend.cut()),
        ],
      );
      rig.node.addComponent(sequence);

      sequence.play();
      _run(sequence, rig.director, 0.5);
      expect(sequence.currentIndex, 0);
      expect(rig.director.pose.position.y, closeTo(1.0, 1e-6));

      _run(sequence, rig.director, 1.0);
      expect(sequence.currentIndex, 1);
      expect(rig.director.pose.position.y, closeTo(2.0, 1e-6));

      _run(sequence, rig.director, 1.0);
      expect(sequence.currentIndex, 2);
      expect(rig.director.pose.position.y, closeTo(3.0, 1e-6));
    });

    test('reports its running time', () {
      final rig = _rig();
      final sequence = CameraSequence(
        rig.director,
        shots: [
          CameraShot(_FixedCamera(1.0), hold: 2.0),
          CameraShot(_FixedCamera(2.0), hold: 3.5),
        ],
      );
      expect(sequence.totalDuration, closeTo(5.5, 1e-9));
    });

    test('hands the camera back when it finishes', () {
      final rig = _rig();
      final gameplay = _FixedCamera(0.0);
      rig.director.add(gameplay, priority: 10);
      rig.director.update(0.05);

      var completed = 0;
      final shot = _FixedCamera(5.0);
      final sequence = CameraSequence(
        rig.director,
        shots: [CameraShot(shot, hold: 0.5, blendIn: const CameraBlend.cut())],
        onComplete: () => completed++,
      );
      rig.node.addComponent(sequence);

      sequence.play();
      _run(sequence, rig.director, 0.2);
      expect(rig.director.activeCamera, same(shot));

      _run(sequence, rig.director, 0.5);
      expect(completed, 1);
      expect(sequence.isPlaying, isFalse);
      // Priority takes back over on its own.
      expect(rig.director.activeCamera, same(gameplay));
    });

    test('stays on the last shot when told not to release', () {
      final rig = _rig();
      final gameplay = _FixedCamera(0.0);
      rig.director.add(gameplay, priority: 10);
      final shot = _FixedCamera(5.0);
      final sequence = CameraSequence(
        rig.director,
        shots: [CameraShot(shot, hold: 0.2, blendIn: const CameraBlend.cut())],
        releaseOnComplete: false,
      );
      rig.node.addComponent(sequence);

      sequence.play();
      _run(sequence, rig.director, 1.0);
      expect(rig.director.activeCamera, same(shot));
    });

    test('loops without ever completing', () {
      final rig = _rig();
      var completed = 0;
      final a = _FixedCamera(1.0);
      final b = _FixedCamera(2.0);
      final sequence = CameraSequence(
        rig.director,
        shots: [
          CameraShot(a, hold: 0.2, blendIn: const CameraBlend.cut()),
          CameraShot(b, hold: 0.2, blendIn: const CameraBlend.cut()),
        ],
        loop: true,
        onComplete: () => completed++,
      );
      rig.node.addComponent(sequence);

      sequence.play();
      _run(sequence, rig.director, 2.0);
      expect(completed, 0);
      expect(sequence.isPlaying, isTrue);
      expect(sequence.currentIndex, anyOf(0, 1));
    });

    test('does not fall behind when a frame is longer than a shot', () {
      final rig = _rig();
      final shots = [
        for (var i = 0; i < 4; i++)
          CameraShot(
            _FixedCamera(i.toDouble()),
            hold: 0.02,
            blendIn: const CameraBlend.cut(),
          ),
      ];
      final sequence = CameraSequence(rig.director, shots: shots);
      rig.node.addComponent(sequence);

      sequence.play();
      // One long frame spans every shot; the sequence must end, not lag.
      sequence.update(1.0);
      expect(sequence.isPlaying, isFalse);
    });

    test('pause holds and resume continues', () {
      final rig = _rig();
      final a = _FixedCamera(1.0);
      final b = _FixedCamera(2.0);
      final sequence = CameraSequence(
        rig.director,
        shots: [
          CameraShot(a, hold: 0.5, blendIn: const CameraBlend.cut()),
          CameraShot(b, hold: 0.5, blendIn: const CameraBlend.cut()),
        ],
      );
      rig.node.addComponent(sequence);

      sequence.play();
      sequence.pause();
      _run(sequence, rig.director, 2.0);
      expect(sequence.currentIndex, 0);

      sequence.resume();
      _run(sequence, rig.director, 0.6);
      expect(sequence.currentIndex, 1);
    });

    test('skip cuts to the next shot early', () {
      final rig = _rig();
      final a = _FixedCamera(1.0);
      final b = _FixedCamera(2.0);
      final sequence = CameraSequence(
        rig.director,
        shots: [
          CameraShot(a, hold: 100.0, blendIn: const CameraBlend.cut()),
          CameraShot(b, hold: 100.0, blendIn: const CameraBlend.cut()),
        ],
      );
      rig.node.addComponent(sequence);

      sequence.play();
      sequence.skip();
      expect(sequence.currentIndex, 1);
      sequence.skip();
      expect(sequence.isPlaying, isFalse);
    });

    test('reports each shot as it begins', () {
      final rig = _rig();
      final seen = <int>[];
      final sequence = CameraSequence(
        rig.director,
        shots: [
          CameraShot(_FixedCamera(1.0), hold: 0.2),
          CameraShot(_FixedCamera(2.0), hold: 0.2),
        ],
        onShotChanged: (index, _) => seen.add(index),
      );
      rig.node.addComponent(sequence);

      sequence.play();
      _run(sequence, rig.director, 0.5);
      expect(seen, [0, 1]);
    });

    test('rejects a shot with no duration', () {
      expect(
        () => CameraShot(_FixedCamera(0.0), hold: 0.0),
        throwsA(isA<AssertionError>()),
      );
    });
  });
}
