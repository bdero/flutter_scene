// Tests for PerspectiveCamera.framing, which places a camera to fit a
// bounding box in the view.

import 'dart:math';

import 'package:flutter_scene/scene.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

void main() {
  group('PerspectiveCamera.framing', () {
    test('looks at the bounds center from the given direction', () {
      final bounds = Aabb3.minMax(Vector3(2, 2, 2), Vector3(6, 6, 6));
      final camera = PerspectiveCamera.framing(
        bounds,
        direction: Vector3(0, 0, -1),
      );
      expect(camera.target, Vector3(4, 4, 4));
      // Eye sits on the -Z side of the center.
      expect(camera.position.x, closeTo(4, 1e-9));
      expect(camera.position.y, closeTo(4, 1e-9));
      expect(camera.position.z, lessThan(4));
    });

    test('the bounding sphere subtends the vertical field of view', () {
      final bounds = Aabb3.minMax(Vector3(-1, -1, -1), Vector3(1, 1, 1));
      const fov = 45 * degrees2Radians;
      final camera = PerspectiveCamera.framing(
        bounds,
        fovRadiansY: fov,
        margin: 1.0,
      );
      final radius = (bounds.max - bounds.min).length * 0.5;
      final distance = (camera.position - camera.target).length;
      // distance = radius / sin(fov/2) frames the sphere exactly.
      expect(camera.fovRadiansY, fov);
      expect(distance, closeTo(radius / sin(fov / 2), 1e-4));
    });

    test('margin pushes the camera farther back', () {
      final bounds = Aabb3.minMax(Vector3(-1, -1, -1), Vector3(1, 1, 1));
      final near = PerspectiveCamera.framing(bounds, margin: 1.0);
      final far = PerspectiveCamera.framing(bounds, margin: 2.0);
      final dNear = (near.position - near.target).length;
      final dFar = (far.position - far.target).length;
      expect(dFar, closeTo(dNear * 2, 1e-9));
    });

    test('clip planes bracket the model for any scale', () {
      for (final extent in [0.01, 1.0, 100.0]) {
        final bounds = Aabb3.minMax(Vector3.all(-extent), Vector3.all(extent));
        final camera = PerspectiveCamera.framing(bounds);
        final distance = (camera.position - camera.target).length;
        expect(camera.fovNear, greaterThan(0));
        expect(camera.fovNear, lessThan(distance));
        expect(camera.fovFar, greaterThan(distance));
      }
    });

    test('normalizes a non-unit direction', () {
      final bounds = Aabb3.minMax(Vector3(-1, -1, -1), Vector3(1, 1, 1));
      final camera = PerspectiveCamera.framing(
        bounds,
        direction: Vector3(0, 0, -5),
      );
      final distance = (camera.position - camera.target).length;
      final radius = (bounds.max - bounds.min).length * 0.5;
      expect(
        distance,
        closeTo(radius / sin((45 * degrees2Radians) / 2) * 1.1, 1e-4),
      );
    });
  });
}
