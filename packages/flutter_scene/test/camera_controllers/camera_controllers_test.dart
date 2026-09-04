// Covers the camera controllers: orbit/fly/follow drive their node's transform
// with frame-rate-independent smoothing, clamped pitch, and a +Z forward axis
// aimed via Node.lookAtFrom.

import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter_scene/scene.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

Vector3 _pos(Node n) => n.globalTransform.getTranslation();
Vector3 _forward(Node n) {
  final s = n.globalTransform.storage;
  return Vector3(s[8], s[9], s[10]).normalized();
}

// Recovers (azimuth, polar) of an eye orbiting the origin, matching the
// controller's own convention (azimuth about +Y, polar elevation).
double _azimuthOf(Vector3 eye) => math.atan2(-eye.x, -eye.z);
double _polarOf(Vector3 eye) =>
    math.asin((eye.y / eye.length).clamp(-1.0, 1.0));

KeyDownEvent _down(LogicalKeyboardKey key) => KeyDownEvent(
  physicalKey: PhysicalKeyboardKey.keyW,
  logicalKey: key,
  timeStamp: Duration.zero,
);

void main() {
  _occlusionTests();
  group('OrbitCameraController', () {
    test('places the eye on the orbit and aims +Z at the target', () {
      final node = Node();
      final c = OrbitCameraController(
        distance: 6.0,
        polar: 0.0,
        smoothing: 0.0,
      );
      node.addComponent(c);
      c.update(1 / 60);

      final eye = _pos(node);
      expect(eye.x, closeTo(0.0, 1e-5));
      expect(eye.y, closeTo(0.0, 1e-5));
      expect(eye.z, closeTo(-6.0, 1e-5));
      final f = _forward(node);
      expect(f.x, closeTo(0.0, 1e-5));
      expect(f.z, closeTo(1.0, 1e-5)); // looks toward the origin
    });

    test('orbitBy rotates and clamps polar inside the poles', () {
      final node = Node();
      final c = OrbitCameraController(polar: 0.0, azimuth: 0.0, smoothing: 0.0);
      node.addComponent(c);
      c.orbitBy(0.5, 10.0); // huge pitch request
      c.update(1 / 60);
      final eye = _pos(node);
      expect(_polarOf(eye), closeTo(math.pi / 2 - 0.02, 1e-3));
      expect(_azimuthOf(eye), closeTo(0.5, 1e-3));
    });

    test('dollyBy scales distance proportionally and clamps', () {
      final node = Node();
      final c = OrbitCameraController(
        distance: 10.0,
        minDistance: 2.0,
        maxDistance: 20.0,
        smoothing: 0.0,
      );
      node.addComponent(c);
      c.dollyBy(1.0); // zoom in
      c.update(1 / 60);
      expect(c.distance, lessThan(10.0));
      c.dollyBy(-100.0); // zoom way out, clamps to max
      c.update(1 / 60);
      expect(c.distance, closeTo(20.0, 1e-6));
    });

    group('frame', () {
      Aabb3 unitBounds() => Aabb3.minMax(Vector3(-1, -1, -1), Vector3(1, 1, 1));

      // The bounding sphere of a 2-unit cube.
      final radius = Vector3(2, 2, 2).length * 0.5;

      test('solves the distance from the lens, not the diameter', () {
        final node = Node()..addComponent(CameraComponent());
        final c = OrbitCameraController(smoothing: 0.0)
          ..viewportSize = const Size(800, 600);
        node.addComponent(c);
        c.frame(unitBounds(), margin: 1.0);
        c.update(1 / 60);

        // 45 degrees vertical, landscape, so the vertical field is the narrow
        // one: the sphere subtends exactly the view height at r / sin(fov/2).
        final expected = radius / math.sin(45 * math.pi / 180 / 2);
        expect(c.distance, closeTo(expected, 1e-6));
      });

      test('a narrow lens pulls the camera back', () {
        final node = Node()
          ..addComponent(
            CameraComponent(
              projection: PerspectiveProjection(
                fovRadiansY: 20 * math.pi / 180,
              ),
            ),
          );
        final c = OrbitCameraController(smoothing: 0.0, maxDistance: 1000)
          ..viewportSize = const Size(800, 600);
        node.addComponent(c);
        c.frame(unitBounds(), margin: 1.0);
        c.warmUp();
        expect(
          c.distance,
          closeTo(radius / math.sin(10 * math.pi / 180), 1e-6),
        );
      });

      test('a portrait viewport fits the horizontal field instead', () {
        final node = Node()..addComponent(CameraComponent());
        final tall = OrbitCameraController(smoothing: 0.0, maxDistance: 1000)
          ..viewportSize = const Size(400, 800);
        node.addComponent(tall);
        tall.frame(unitBounds(), margin: 1.0);
        tall.warmUp();

        final halfY = 45 * math.pi / 180 / 2;
        final halfX = math.atan(math.tan(halfY) * 400 / 800);
        expect(tall.distance, closeTo(radius / math.sin(halfX), 1e-6));
        // Narrower than the vertical field, so it must sit further back than
        // the landscape framing would.
        expect(tall.distance, greaterThan(radius / math.sin(halfY)));
      });

      test('an explicit field of view overrides the lens', () {
        final node = Node()..addComponent(CameraComponent());
        final c = OrbitCameraController(smoothing: 0.0, maxDistance: 1000)
          ..viewportSize = const Size(800, 600);
        node.addComponent(c);
        c.frame(unitBounds(), margin: 1.0, fovRadiansY: 90 * math.pi / 180);
        c.warmUp();
        expect(
          c.distance,
          closeTo(radius / math.sin(45 * math.pi / 180), 1e-6),
        );
      });

      test('an orthographic lens keeps the diameter fit', () {
        final node = Node()
          ..addComponent(CameraComponent(projection: OrthographicProjection()));
        final c = OrbitCameraController(smoothing: 0.0, maxDistance: 1000)
          ..viewportSize = const Size(800, 600);
        node.addComponent(c);
        c.frame(unitBounds(), margin: 1.0);
        c.warmUp();
        expect(c.distance, closeTo(radius * 2, 1e-6));
      });

      test('an unattached controller falls back to the engine default', () {
        final c = OrbitCameraController(smoothing: 0.0, maxDistance: 1000)
          ..viewportSize = const Size(800, 600);
        c.frame(unitBounds(), margin: 1.0);
        c.warmUp();
        expect(
          c.distance,
          closeTo(radius / math.sin(45 * math.pi / 180 / 2), 1e-6),
        );
      });

      test('the distance stays inside the dolly limits', () {
        final node = Node()..addComponent(CameraComponent());
        final c = OrbitCameraController(smoothing: 0.0, maxDistance: 3.0);
        node.addComponent(c);
        c.frame(Aabb3.minMax(Vector3(-50, -50, -50), Vector3(50, 50, 50)));
        c.warmUp();
        expect(c.distance, closeTo(3.0, 1e-9));
      });
    });

    test('settling is frame-rate independent for a fixed goal', () {
      Node makeAt(double dt, int steps) {
        final node = Node();
        final c = OrbitCameraController(
          distance: 5.0,
          azimuth: 0.0,
          smoothing: 0.2,
        );
        node.addComponent(c);
        c.orbitBy(1.0, 0.0); // move the goal once
        for (var i = 0; i < steps; i++) {
          c.update(dt);
        }
        return node;
      }

      // Same 0.5s of wall-clock via coarse and fine steps -> same pose.
      final coarse = _pos(makeAt(0.1, 5));
      final fine = _pos(makeAt(1 / 240, 120));
      expect((coarse - fine).length, lessThan(1e-3));
    });

    test('handleDragUpdate uses the viewport height to normalize', () {
      final node = Node();
      final c = OrbitCameraController(
        rotateSpeed: math.pi,
        azimuth: 0.0,
        polar: 0.0,
        distance: 6.0,
        smoothing: 0.0,
      );
      node.addComponent(c);
      c.viewportSize = const Size(1000, 500);
      c.handleDragUpdate(const Offset(250, 0)); // half a view height across
      c.update(1 / 60);
      // azimuth goal = -250 * (pi / 500) = -pi/2.
      expect(_azimuthOf(_pos(node)), closeTo(-math.pi / 2, 1e-4));
    });
  });

  group('FlyCameraController', () {
    test('a held W key moves along the forward axis', () {
      final node = Node();
      final c = FlyCameraController(
        position: Vector3.zero(),
        speed: 4.0,
        smoothing: 0.0,
        movementSmoothing: 0.0,
      );
      node.addComponent(c);
      expect(c.handleKeyEvent(_down(LogicalKeyboardKey.keyW)), isTrue);
      c.update(0.05);
      // forward at yaw 0, pitch 0 is (0,0,-1); moved speed*dt = 0.2 units.
      expect(_pos(node).z, closeTo(-0.2, 1e-5));
    });

    test('look clamps pitch short of vertical', () {
      final node = Node();
      final c = FlyCameraController(position: Vector3.zero(), smoothing: 0.0);
      node.addComponent(c);
      c.look(const Offset(0, -100000)); // slam look up
      c.update(1 / 60);
      // forward.y = sin(pitch); pitch is clamped to pitchLimit.
      expect(_forward(node).y, closeTo(math.sin(c.pitchLimit), 1e-4));
    });

    test('grounded mode keeps forward/back horizontal', () {
      final node = Node();
      final c = FlyCameraController(
        position: Vector3.zero(),
        pitch: -1.0, // looking down
        speed: 4.0,
        smoothing: 0.0,
        movementSmoothing: 0.0,
        moveVertical: false,
      );
      node.addComponent(c);
      c.handleKeyEvent(_down(LogicalKeyboardKey.keyW));
      c.update(0.05);
      expect(_pos(node).y, closeTo(0.0, 1e-6)); // no vertical drift
    });
  });

  group('FollowCameraController', () {
    test('snaps behind the target on the first frame, then eases', () {
      final target = Node()..position = Vector3(0.0, 0.0, 0.0);
      final camNode = Node();
      final c = FollowCameraController(
        followTarget: target,
        distance: 8.0,
        lookHeight: 1.0,
        yaw: 0.0,
        pitch: 0.0,
        smoothing: 0.1,
      );
      camNode.addComponent(c);

      c.update(1 / 60); // first frame snaps
      final look = target.position + Vector3(0.0, 1.0, 0.0);
      final f = _forward(camNode);
      final want = (look - _pos(camNode)).normalized();
      expect((f - want).length, lessThan(1e-4));

      // Move the target; the camera should ease toward it, not jump.
      target.position = Vector3(100.0, 0.0, 0.0);
      c.update(1 / 60);
      expect(_pos(camNode).x, greaterThan(0.0));
      expect(_pos(camNode).x, lessThan(100.0));
    });
  });
}

// Occlusion retraction on the third-person camera. The probe is injected
// rather than raycast, so the retraction logic is exercised without a GPU
// context; `occludeAgainst` supplies the real geometry probe in a build.
void _occlusionTests() {
  group('FollowCameraController occlusion', () {
    FollowCameraController camera({double? blockAt}) {
      final controller = FollowCameraController(
        distance: 10.0,
        pitch: 0.0,
        lookHeight: 0.0,
        smoothing: 0.0,
      );
      if (blockAt != null) {
        controller.occlusionProbe = (lookAt, desiredEye) => blockAt;
      }
      return controller;
    }

    double eyeDistance(FollowCameraController controller) =>
        controller.pose.position.length;

    test('stays at full distance with nothing in the way', () {
      final controller = camera();
      controller.step(0.1);
      expect(eyeDistance(controller), closeTo(10.0, 1e-4));
    });

    test('stays at full distance when the probe reports clear', () {
      final controller = FollowCameraController(
        distance: 10.0,
        pitch: 0.0,
        lookHeight: 0.0,
        smoothing: 0.0,
      )..occlusionProbe = (lookAt, desiredEye) => null;
      controller.step(0.1);
      expect(eyeDistance(controller), closeTo(10.0, 1e-4));
    });

    test('pulls in front of a wall, minus the padding', () {
      final controller = camera(blockAt: 4.0);
      controller.step(0.1);
      expect(
        eyeDistance(controller),
        closeTo(4.0 - controller.occlusionPadding, 1e-4),
      );
    });

    test('retracts immediately rather than easing into the wall', () {
      final controller = camera(blockAt: 3.0);
      // One frame is enough: easing here would leave the camera inside the
      // wall for the duration of the ease, which is the failure this exists
      // to prevent.
      controller.step(1 / 60);
      expect(eyeDistance(controller), lessThan(3.1));
    });

    test('never retracts past its minimum', () {
      final controller = camera(blockAt: 0.05);
      controller.step(0.1);
      expect(
        eyeDistance(controller),
        closeTo(controller.minOcclusionDistance, 1e-4),
      );
    });

    test('eases back out once the way is clear', () {
      final controller = camera(blockAt: 3.0);
      controller.step(0.1);
      final retracted = eyeDistance(controller);

      controller.occlusionProbe = (lookAt, desiredEye) => null;
      controller.step(0.1);
      final recovering = eyeDistance(controller);
      expect(recovering, greaterThan(retracted));
      expect(recovering, lessThan(10.0), reason: 'it eases rather than snaps');

      for (var i = 0; i < 120; i++) {
        controller.step(1 / 60);
      }
      expect(eyeDistance(controller), closeTo(10.0, 1e-3));
    });

    test('clearOcclusion goes back to the full distance', () {
      final controller = camera(blockAt: 2.0);
      controller.step(0.1);
      expect(eyeDistance(controller), lessThan(3.0));

      controller.clearOcclusion();
      controller.step(0.1);
      expect(eyeDistance(controller), closeTo(10.0, 1e-4));
    });
  });
}
