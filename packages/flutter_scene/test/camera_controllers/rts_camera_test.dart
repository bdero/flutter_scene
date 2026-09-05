// Covers RtsCameraController: the overhead framing (including straight down,
// which a look-at camera cannot express), camera-relative panning, bounds and
// terrain clamping, edge scrolling, and the orthographic zoom that drives the
// lens through the pose.

import 'dart:math' as math;
import 'dart:ui' show Offset, Size;

import 'package:flutter_scene/scene.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

void main() {
  group('RtsCameraController', () {
    test('sits back from the focus along its look direction', () {
      final camera = RtsCameraController(
        focus: Vector3(5.0, 0.0, -3.0),
        yaw: 0.0,
        pitch: math.pi / 4,
        distance: 20.0,
      );
      camera.warmUp();

      final pose = camera.pose;
      // The eye is above and behind, and looking back down at the focus.
      expect(pose.position.y, closeTo(20.0 * math.sin(math.pi / 4), 1e-5));
      final toFocus = (Vector3(5.0, 0.0, -3.0) - pose.position).normalized();
      expect(pose.forward.dot(toFocus), closeTo(1.0, 1e-5));
    });

    test('looks straight down without a degenerate basis', () {
      // The case a look-at camera cannot express: with the view along -Y there
      // is no up vector to cross against, so the basis has to come from yaw.
      final camera = RtsCameraController.topDown(yaw: 0.0, height: 30.0);
      camera.warmUp();

      final pose = camera.pose;
      expect(pose.position.y, closeTo(30.0, 1e-5));
      expect(pose.forward.y, closeTo(-1.0, 1e-5));
      // Screen-up is world north, from the yaw.
      expect(pose.up.z, closeTo(1.0, 1e-5));
      expect(pose.right.x, closeTo(1.0, 1e-5));
    });

    test('a rotated top-down view turns the world on screen', () {
      final camera = RtsCameraController.topDown(yaw: math.pi / 2);
      camera.warmUp();
      expect(camera.pose.forward.y, closeTo(-1.0, 1e-5));
      expect(camera.pose.up.x, closeTo(1.0, 1e-5));
    });

    test('pans in the camera-relative ground plane', () {
      final camera = RtsCameraController(yaw: 0.0, smoothing: 0.0);
      camera.setPanInput(Vector2(0.0, 1.0)); // forward
      camera.step(1.0);
      // Yaw 0 faces +Z, so panning forward increases Z and leaves X alone.
      expect(camera.focus.z, greaterThan(0.0));
      expect(camera.focus.x, closeTo(0.0, 1e-9));

      final turned = RtsCameraController(yaw: math.pi / 2, smoothing: 0.0);
      turned.setPanInput(Vector2(0.0, 1.0));
      turned.step(1.0);
      // Turned a quarter turn, "forward" is now +X.
      expect(turned.focus.x, greaterThan(0.0));
      expect(turned.focus.z, closeTo(0.0, 1e-6));
    });

    test('a drag moves the ground with the pointer', () {
      final camera = RtsCameraController(yaw: 0.0, smoothing: 0.0)
        ..viewportSize = const Size(1000.0, 1000.0);
      camera.handleDragUpdate(const Offset(100.0, 0.0));
      camera.step(0.0);
      // Dragging right pushes the view left, so the focus moves to -X.
      expect(camera.focus.x, lessThan(0.0));
    });

    test('clamps the focus to its bounds', () {
      final camera = RtsCameraController(
        smoothing: 0.0,
        bounds: Aabb3.minMax(
          Vector3(-10.0, 0.0, -10.0),
          Vector3(10.0, 0.0, 10.0),
        ),
      );
      camera.panWorld(Vector2(1000.0, -1000.0));
      camera.step(0.0);
      expect(camera.focus.x, closeTo(10.0, 1e-9));
      expect(camera.focus.z, closeTo(-10.0, 1e-9));
    });

    test('rides the terrain when given a height sampler', () {
      final camera = RtsCameraController(
        smoothing: 0.0,
        groundHeightAt: (x, z) => x * 0.5,
      );
      camera.panWorld(Vector2(8.0, 0.0));
      camera.step(0.0);
      expect(camera.focus.y, closeTo(4.0, 1e-6));
      // The eye rides up with it rather than cutting into the hill.
      expect(camera.pose.position.y, greaterThan(4.0));
    });

    test('zoom acts on distance in perspective mode and clamps', () {
      final camera = RtsCameraController(
        distance: 40.0,
        minDistance: 10.0,
        maxDistance: 100.0,
        smoothing: 0.0,
      );
      camera.zoomBy(1.0);
      camera.step(0.0);
      expect(camera.distance, lessThan(40.0));

      camera.zoomBy(1000.0);
      camera.step(0.0);
      expect(camera.distance, closeTo(10.0, 1e-9));

      camera.zoomBy(-1000.0);
      camera.step(0.0);
      expect(camera.distance, closeTo(100.0, 1e-9));
    });

    test('zoom acts on the view height in orthographic mode', () {
      final camera = RtsCameraController(
        orthographic: true,
        viewHeight: 30.0,
        distance: 100.0,
        smoothing: 0.0,
      );
      camera.zoomBy(1.0);
      camera.step(0.0);

      expect(camera.viewHeight, lessThan(30.0));
      expect(camera.distance, closeTo(100.0, 1e-9));

      final lens = camera.pose.projection;
      expect(lens, isA<OrthographicProjection>());
      expect(
        (lens as OrthographicProjection).height,
        closeTo(camera.viewHeight, 1e-9),
      );
    });

    test('a perspective strategy camera does not touch the lens', () {
      final camera = RtsCameraController(smoothing: 0.0);
      camera.warmUp();
      expect(camera.pose.projection, isNull);
    });

    test('isometric uses the true isometric angle and a parallel lens', () {
      final camera = RtsCameraController.isometric();
      camera.warmUp();
      expect(camera.pitch, closeTo(math.atan(1 / math.sqrt2), 1e-9));
      expect(camera.pose.projection, isA<OrthographicProjection>());

      // Locked: rotate and tilt do nothing.
      camera.handleSecondaryDragUpdate(const Offset(500.0, 500.0));
      camera.step(0.0);
      expect(camera.yaw, closeTo(math.pi / 4, 1e-9));
      expect(camera.pitch, closeTo(math.atan(1 / math.sqrt2), 1e-9));
    });

    group('edge scrolling', () {
      RtsCameraController build() =>
          RtsCameraController(smoothing: 0.0, edgeScroll: const EdgeScroll())
            ..viewportSize = const Size(800.0, 600.0);

      test('pushes when the pointer is at an edge', () {
        final camera = build();
        camera.pointerMoved(const Offset(2.0, 300.0)); // hard left
        camera.step(0.1);
        expect(camera.focus.x, lessThan(0.0));
      });

      test('pushes forward at the top of the view', () {
        final camera = build();
        camera.pointerMoved(const Offset(400.0, 1.0));
        camera.step(0.1);
        expect(camera.focus.z, greaterThan(0.0));
      });

      test('does nothing in the middle', () {
        final camera = build();
        camera.pointerMoved(const Offset(400.0, 300.0));
        camera.step(0.1);
        expect(camera.focus.length, closeTo(0.0, 1e-9));
      });

      test('stops when the pointer leaves the view', () {
        final camera = build();
        camera.pointerMoved(const Offset(2.0, 300.0));
        camera.step(0.1);
        final drifted = camera.focus.x;

        camera.pointerMoved(null);
        camera.step(0.1);
        expect(camera.focus.x, closeTo(drifted, 1e-9));
      });

      test('ramps up toward the very edge', () {
        final inner = build()..pointerMoved(const Offset(20.0, 300.0));
        final outer = build()..pointerMoved(const Offset(1.0, 300.0));
        inner.step(0.1);
        outer.step(0.1);
        expect(outer.focus.x.abs(), greaterThan(inner.focus.x.abs()));
      });
    });

    test('frame centers and zooms to contain a region', () {
      final camera = RtsCameraController(orthographic: true, smoothing: 0.0);
      camera.frame(
        Aabb3.minMax(Vector3(10.0, 0.0, 10.0), Vector3(30.0, 0.0, 30.0)),
      );
      camera.step(0.0);
      expect(camera.focus.x, closeTo(20.0, 1e-6));
      expect(camera.focus.z, closeTo(20.0, 1e-6));
      expect(camera.viewHeight, greaterThan(20.0));
    });
  });
}
