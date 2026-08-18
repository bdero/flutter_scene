// Debug-only asserts guarding the camera against silent blank-frame
// mistakes: a degenerate view basis (up parallel to the view direction, or
// target == position) and a degenerate or degrees-valued frustum. These run
// per view per frame, so they live in asserts and are exercised here by
// building the matrices directly.

import 'dart:math';

import 'package:flutter_scene/scene.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

void main() {
  group('view basis', () {
    test('target equal to position throws', () {
      final camera = PerspectiveCamera(
        position: Vector3(1, 2, 3),
        target: Vector3(1, 2, 3),
      );
      expect(camera.getViewMatrix, throwsAssertionError);
    });

    test('up parallel to the view direction throws', () {
      // Looking straight down the +Y axis with the default +Y up.
      final camera = PerspectiveCamera(
        position: Vector3(0, 10, 0),
        target: Vector3(0, 0, 0),
        up: Vector3(0, 1, 0),
      );
      expect(camera.getViewMatrix, throwsAssertionError);
    });

    test('a non-parallel up passes', () {
      final camera = PerspectiveCamera(
        position: Vector3(0, 10, 0),
        target: Vector3(0, 0, 0),
        up: Vector3(0, 0, 1),
      );
      expect(camera.getViewMatrix(), isA<Matrix4>());
    });

    test('the default placement passes', () {
      expect(PerspectiveCamera().getViewMatrix(), isA<Matrix4>());
    });
  });

  group('frustum', () {
    Matrix4 project(PerspectiveCamera camera) =>
        camera.projection.getProjectionMatrix(1.0);

    test('a degrees-valued field of view throws', () {
      final camera = PerspectiveCamera(fovRadiansY: 60);
      expect(() => project(camera), throwsAssertionError);
    });

    test('a zero near plane throws', () {
      final camera = PerspectiveCamera(fovNear: 0.0);
      expect(() => project(camera), throwsAssertionError);
    });

    test('a negative near plane throws', () {
      final camera = PerspectiveCamera(fovNear: -1.0);
      expect(() => project(camera), throwsAssertionError);
    });

    test('far behind near throws', () {
      final camera = PerspectiveCamera(fovNear: 100.0, fovFar: 10.0);
      expect(() => project(camera), throwsAssertionError);
    });

    test('a valid frustum passes', () {
      final camera = PerspectiveCamera(
        fovRadiansY: 45 * degrees2Radians,
        fovNear: 0.1,
        fovFar: 1000.0,
      );
      expect(project(camera), isA<Matrix4>());
    });

    test('a near-pi field of view still passes', () {
      final camera = PerspectiveCamera(fovRadiansY: pi - 0.01);
      expect(project(camera), isA<Matrix4>());
    });
  });
}
