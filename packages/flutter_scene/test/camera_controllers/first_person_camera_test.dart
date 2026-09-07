// Covers FirstPersonCameraController: the eye rides a character's head, pitch
// clamps short of vertical, recoil is additive and decays back to wherever the
// player has since aimed, and head bob returns to nothing when they stop.

import 'dart:math' as math;

import 'package:flutter_scene/scene.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

Node _at(double x, double y, double z) =>
    Node()..localTransform = Matrix4.translation(Vector3(x, y, z));

void main() {
  group('FirstPersonCameraController', () {
    test('puts the eye at the character head', () {
      final player = _at(3.0, 0.0, -4.0);
      final camera = FirstPersonCameraController(followTarget: player);
      camera.warmUp();

      expect(camera.position.x, closeTo(3.0, 1e-6));
      expect(camera.position.y, closeTo(1.7, 1e-6));
      expect(camera.position.z, closeTo(-4.0, 1e-6));
    });

    test('tracks the character as it moves', () {
      final player = _at(0.0, 0.0, 0.0);
      final camera = FirstPersonCameraController(followTarget: player);
      camera.warmUp();

      player.localTransform = Matrix4.translation(Vector3(0.0, 0.0, 10.0));
      camera.warmUp();
      expect(camera.position.z, closeTo(10.0, 1e-6));
    });

    test('eases behind the body when positionSmoothing is set', () {
      final player = _at(0.0, 0.0, 0.0);
      final camera = FirstPersonCameraController(
        followTarget: player,
        positionSmoothing: 0.2,
      );
      camera.warmUp();

      player.localTransform = Matrix4.translation(Vector3(0.0, 0.0, 10.0));
      camera.step(0.016);
      expect(camera.position.z, greaterThan(0.0));
      expect(camera.position.z, lessThan(10.0));
    });

    test('clamps pitch short of vertical', () {
      final camera = FirstPersonCameraController();
      camera.lookBy(0.0, 100.0);
      camera.warmUp();
      expect(camera.pitch, closeTo(camera.maxPitch, 1e-9));
      expect(camera.pose.forward.y, lessThan(1.0));

      camera.lookBy(0.0, -1000.0);
      camera.warmUp();
      expect(camera.pitch, closeTo(camera.minPitch, 1e-9));
    });

    test('look turns right on a rightward drag', () {
      final camera = FirstPersonCameraController();
      camera.look(const Offset(100.0, 0.0));
      camera.warmUp();
      expect(camera.yaw, greaterThan(0.0));
      // Yaw 0 looks down +Z; turning right swings toward +X.
      expect(camera.planarForward.x, greaterThan(0.0));
    });

    test('planarForward and planarRight stay level and perpendicular', () {
      final camera = FirstPersonCameraController(yaw: 0.7, pitch: 0.5);
      camera.warmUp();
      expect(camera.planarForward.y, 0.0);
      expect(camera.planarRight.y, 0.0);
      expect(camera.planarForward.dot(camera.planarRight), closeTo(0.0, 1e-9));
      // The full look direction still carries the upward pitch.
      expect(camera.pose.forward.y, greaterThan(0.0));
    });

    test('lookAtPoint aims at a world position', () {
      final camera = FirstPersonCameraController(position: Vector3.zero());
      camera.eyeOffset = Vector3.zero();
      camera.lookAtPoint(Vector3(10.0, 0.0, 0.0));
      camera.warmUp();
      expect(camera.pose.forward.x, closeTo(1.0, 1e-5));
      expect(camera.pose.forward.y, closeTo(0.0, 1e-5));
    });

    test('recoil kicks the aim up and decays back', () {
      final camera = FirstPersonCameraController();
      camera.warmUp();
      final rested = camera.pose.forward.y;

      camera.addRecoil(0.2);
      camera.step(0.0);
      expect(camera.pose.forward.y, greaterThan(rested));
      // The player's own aim is untouched: only the kick moved.
      expect(camera.pitch, closeTo(0.0, 1e-9));

      for (var i = 0; i < 120; i++) {
        camera.step(1 / 60);
      }
      expect(camera.pose.forward.y, closeTo(rested, 1e-3));
    });

    test('recoil recovers to where the player has since aimed', () {
      final camera = FirstPersonCameraController();
      camera.addRecoil(0.3);
      camera.lookBy(0.0, -0.5); // the player pulls back down while it decays
      for (var i = 0; i < 200; i++) {
        camera.step(1 / 60);
      }
      expect(camera.pitch, closeTo(-0.5, 1e-6));
      expect(camera.pose.forward.y, closeTo(-math.sin(0.5), 1e-3));
    });

    test('head bob displaces the eye and settles when movement stops', () {
      final camera = FirstPersonCameraController(headBob: HeadBob());
      camera.warmUp();
      final still = camera.pose.position.clone();

      camera.setMotion(1.0);
      var moved = 0.0;
      for (var i = 0; i < 60; i++) {
        camera.step(1 / 60);
        final offset = (camera.pose.position - still).length;
        if (offset > moved) moved = offset;
      }
      expect(moved, greaterThan(0.01));

      camera.setMotion(0.0);
      for (var i = 0; i < 120; i++) {
        camera.step(1 / 60);
      }
      expect((camera.pose.position - still).length, lessThan(1e-3));
    });

    test('carries its lens into the pose', () {
      final lens = PerspectiveProjection(fovRadiansY: 0.6);
      final camera = FirstPersonCameraController(lens: lens);
      camera.warmUp();
      expect(camera.pose.projection, same(lens));
    });
  });
}
