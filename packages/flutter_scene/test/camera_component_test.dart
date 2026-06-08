// Covers CameraComponent: a camera whose view is derived from the owning
// node's world transform should match an equivalent free PerspectiveCamera.

import 'dart:ui' show Size;

import 'package:flutter_scene/scene.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

void main() {
  group('CameraComponent', () {
    test('derives a view matching an equivalent PerspectiveCamera', () {
      final reference = PerspectiveCamera(
        position: Vector3(3.0, 4.0, 5.0),
        target: Vector3(-1.0, 0.5, 2.0),
        up: Vector3(0.0, 1.0, 0.0),
        fovRadiansY: 0.9,
        fovNear: 0.2,
        fovFar: 500.0,
      );

      // Place a camera node where the reference camera sits: the node's
      // world transform is the inverse of the reference view matrix.
      final world = Matrix4.identity()..copyInverse(reference.getViewMatrix());
      final node = Node(localTransform: world);
      final component = CameraComponent(projection: reference.projection);
      node.addComponent(component);
      final camera = component.toCamera();

      const size = Size(800.0, 600.0);
      final expected = reference.getViewTransform(size);
      final actual = camera.getViewTransform(size);
      for (var i = 0; i < 16; i++) {
        expect(
          actual.storage[i],
          closeTo(expected.storage[i], 1e-5),
          reason: 'view-projection element $i',
        );
      }

      expect(camera.position.x, closeTo(reference.position.x, 1e-5));
      expect(camera.position.y, closeTo(reference.position.y, 1e-5));
      expect(camera.position.z, closeTo(reference.position.z, 1e-5));

      final refForward = reference.forward;
      expect(camera.forward.x, closeTo(refForward.x, 1e-5));
      expect(camera.forward.y, closeTo(refForward.y, 1e-5));
      expect(camera.forward.z, closeTo(refForward.z, 1e-5));
    });

    test('captures the node transform at the time toCamera is called', () {
      final node = Node();
      final component = CameraComponent();
      node.addComponent(component);

      node.localTransform = Matrix4.translation(Vector3(1.0, 2.0, 3.0));
      final camera = component.toCamera();
      expect(camera.position.x, closeTo(1.0, 1e-6));
      expect(camera.position.y, closeTo(2.0, 1e-6));
      expect(camera.position.z, closeTo(3.0, 1e-6));
    });
  });
}
