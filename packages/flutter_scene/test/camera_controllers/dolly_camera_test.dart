// Covers DollyCameraController: constant-speed travel along a path, timed
// travel with easing, looping, aiming, and the end-of-shot signal.

import 'package:flutter/animation.dart' show Curves;
import 'package:flutter_scene/scene.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

CameraPath _straight() =>
    CameraPath.line(Vector3.zero(), Vector3(0.0, 0.0, 100.0));

void _run(CameraController camera, double seconds, {double frame = 0.05}) {
  for (var t = 0.0; t < seconds - 1e-9; t += frame) {
    camera.step(frame);
  }
}

void main() {
  group('DollyCameraController', () {
    test('travels at the given speed', () {
      final camera = DollyCameraController(path: _straight(), speed: 10.0);
      _run(camera, 2.0);
      expect(camera.distanceAlong, closeTo(20.0, 1e-6));
      expect(camera.pose.position.z, closeTo(20.0, 1e-3));
    });

    test('holds still while paused', () {
      final camera = DollyCameraController(
        path: _straight(),
        speed: 10.0,
        playing: false,
      );
      _run(camera, 2.0);
      expect(camera.distanceAlong, 0.0);

      camera.play();
      _run(camera, 1.0);
      expect(camera.distanceAlong, closeTo(10.0, 1e-6));
    });

    test('fits an exact duration', () {
      final camera = DollyCameraController(path: _straight(), duration: 4.0);
      _run(camera, 2.0);
      expect(camera.progress, closeTo(0.5, 1e-6));
      _run(camera, 2.0);
      expect(camera.progress, closeTo(1.0, 1e-6));
    });

    test('easing shapes a timed move without changing its length', () {
      final eased = DollyCameraController(
        path: _straight(),
        duration: 4.0,
        easing: Curves.easeInOut,
      );
      _run(eased, 1.0);
      // A quarter of the way through time, an ease-in-out has covered less
      // than a quarter of the distance.
      expect(eased.progress, lessThan(0.25));
      _run(eased, 3.0);
      expect(eased.progress, closeTo(1.0, 1e-6));
    });

    test('reports the end once and only once', () {
      var finished = 0;
      final camera = DollyCameraController(
        path: _straight(),
        speed: 100.0,
        onFinished: () => finished++,
      );
      _run(camera, 3.0);
      expect(finished, 1);
      expect(camera.isFinished, isTrue);
      expect(camera.progress, closeTo(1.0, 1e-9));
    });

    test('loops without reporting an end', () {
      var finished = 0;
      final camera = DollyCameraController(
        path: _straight(),
        speed: 100.0,
        loop: true,
        onFinished: () => finished++,
      );
      _run(camera, 2.5);
      expect(finished, 0);
      expect(camera.isFinished, isFalse);
      expect(camera.distanceAlong, closeTo(50.0, 1e-4));
    });

    test('seek and restart move the shot', () {
      final camera = DollyCameraController(path: _straight(), speed: 10.0);
      camera.seek(0.5);
      camera.step(0.0);
      expect(camera.pose.position.z, closeTo(50.0, 1e-3));

      camera.restart();
      camera.step(0.0);
      expect(camera.distanceAlong, 0.0);
      expect(camera.isFinished, isFalse);
    });

    test('aims at a node it is tracking', () {
      final subject = Node()
        ..localTransform = Matrix4.translation(Vector3(20.0, 0.0, 0.0));
      final camera = DollyCameraController(
        path: _straight(),
        lookTarget: subject,
        speed: 0.0,
      );
      camera.step(0.0);
      expect(camera.pose.forward.x, closeTo(1.0, 1e-5));

      subject.localTransform = Matrix4.translation(Vector3(-20.0, 0.0, 0.0));
      camera.step(0.0);
      expect(camera.pose.forward.x, closeTo(-1.0, 1e-5));
    });

    test('aims at a fixed point when given one', () {
      final camera = DollyCameraController(
        path: _straight(),
        lookPoint: Vector3(10.0, 0.0, 0.0),
        speed: 0.0,
      );
      camera.step(0.0);
      expect(camera.pose.forward.x, closeTo(1.0, 1e-5));
    });

    test('survives aiming straight along its reference up', () {
      // A crane looking straight down: a look-at built from a vertical up is
      // degenerate here, so the shot has to find its own reference.
      final camera = DollyCameraController(
        path: CameraPath.line(
          Vector3(0.0, 20.0, 0.0),
          Vector3(0.0, 20.0, 40.0),
        ),
        lookPoint: Vector3.zero(),
        speed: 0.0,
      );
      camera.step(0.0);
      expect(camera.pose.forward.y, closeTo(-1.0, 1e-4));
      expect(camera.pose.up.length, closeTo(1.0, 1e-5));
      expect(camera.pose.up.dot(camera.pose.forward).abs(), lessThan(1e-4));
    });

    test('aims along the path when it has no target', () {
      final camera = DollyCameraController(
        path: _straight(),
        speed: 0.0,
        lookAhead: 5.0,
      );
      camera.step(0.0);
      expect(camera.pose.forward.z, closeTo(1.0, 1e-5));
    });

    test('keeps a valid aim at the very end of an open path', () {
      // Past the end there is nothing ahead to look at; the aim has to fall
      // back to the tangent rather than collapsing onto the camera itself.
      final camera = DollyCameraController(
        path: _straight(),
        speed: 1000.0,
        lookAhead: 5.0,
      );
      _run(camera, 1.0);
      expect(camera.progress, closeTo(1.0, 1e-9));
      expect(camera.pose.forward.length, closeTo(1.0, 1e-5));
      expect(camera.pose.forward.z, closeTo(1.0, 1e-4));
    });

    test('smoothing eases the aim, not the position', () {
      DollyCameraController build(Node subject, double smoothing) =>
          DollyCameraController(
            path: _straight(),
            lookTarget: subject,
            speed: 10.0,
            smoothing: smoothing,
          );

      final rigidSubject = Node();
      final easedSubject = Node();
      final rigid = build(rigidSubject, 0.0);
      final eased = build(easedSubject, 0.4);
      rigid.step(0.05);
      eased.step(0.05);

      // A near, lateral jump: far enough off-axis that a partly-eased aim
      // points somewhere visibly different from an arrived one.
      final moved = Matrix4.translation(Vector3(2.0, 0.0, 0.0));
      rigidSubject.localTransform = moved;
      easedSubject.localTransform = moved;
      rigid.step(0.05);
      eased.step(0.05);

      expect(eased.pose.forward.dot(rigid.pose.forward), lessThan(0.99));
      // ...while the position is exactly where the path says, unsmoothed.
      expect(eased.distanceAlong, closeTo(rigid.distanceAlong, 1e-9));
      expect(eased.pose.position.z, closeTo(rigid.pose.position.z, 1e-9));
    });
  });
}
