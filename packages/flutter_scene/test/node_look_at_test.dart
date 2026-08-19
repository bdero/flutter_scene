// Covers Node.lookAt / lookAtFrom / lookAtTransform: orienting a node's +Z
// forward axis at a world-space target, matching the inverse of an equivalent
// PerspectiveCamera view.

import 'package:flutter_scene/scene.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

Vector3 _column(Matrix4 m, int c) =>
    Vector3(m.storage[c * 4], m.storage[c * 4 + 1], m.storage[c * 4 + 2]);

void main() {
  group('Node.lookAtTransform', () {
    test('matches the inverse of the equivalent PerspectiveCamera view', () {
      final eye = Vector3(3.0, 4.0, 5.0);
      final target = Vector3(-1.0, 0.5, 2.0);
      final up = Vector3(0.0, 1.0, 0.0);

      final expected = Matrix4.identity()
        ..copyInverse(
          PerspectiveCamera(
            position: eye,
            target: target,
            up: up,
          ).getViewMatrix(),
        );
      final actual = Node.lookAtTransform(eye, target, up: up);

      for (var i = 0; i < 16; i++) {
        expect(
          actual.storage[i],
          closeTo(expected.storage[i], 1e-5),
          reason: 'element $i',
        );
      }
    });

    test('a CameraComponent on the node renders the equivalent view', () {
      final eye = Vector3(2.0, 1.0, -6.0);
      final target = Vector3(0.0, 0.0, 0.0);
      final reference = PerspectiveCamera(position: eye, target: target);

      final node = Node(localTransform: Node.lookAtTransform(eye, target));
      final component = CameraComponent(projection: reference.projection);
      node.addComponent(component);

      final camera = component.toCamera();
      expect(camera.position.x, closeTo(eye.x, 1e-5));
      expect(camera.position.y, closeTo(eye.y, 1e-5));
      expect(camera.position.z, closeTo(eye.z, 1e-5));
      final f = reference.forward;
      expect(camera.forward.x, closeTo(f.x, 1e-5));
      expect(camera.forward.y, closeTo(f.y, 1e-5));
      expect(camera.forward.z, closeTo(f.z, 1e-5));
    });
  });

  group('Node.lookAtFrom', () {
    test('positions at eye and aims +Z at the target', () {
      final eye = Vector3(0.0, 3.0, -8.0);
      final target = Vector3(0.0, 0.0, 0.0);
      final node = Node()..lookAtFrom(eye, target);

      final world = node.globalTransform;
      expect(world.getTranslation().x, closeTo(eye.x, 1e-6));
      expect(world.getTranslation().y, closeTo(eye.y, 1e-6));
      expect(world.getTranslation().z, closeTo(eye.z, 1e-6));

      final forward = _column(world, 2).normalized();
      final want = (target - eye).normalized();
      expect(forward.x, closeTo(want.x, 1e-5));
      expect(forward.y, closeTo(want.y, 1e-5));
      expect(forward.z, closeTo(want.z, 1e-5));
    });

    test('aims in world space through a transformed parent', () {
      final parent = Node(
        localTransform: Matrix4.translation(Vector3(10.0, 0.0, 0.0))
          ..rotateY(1.2),
      );
      final child = Node();
      parent.add(child);

      final eye = Vector3(1.0, 2.0, 3.0);
      final target = Vector3(4.0, 0.0, -1.0);
      child.lookAtFrom(eye, target);

      final world = child.globalTransform;
      expect(world.getTranslation().x, closeTo(eye.x, 1e-5));
      expect(world.getTranslation().y, closeTo(eye.y, 1e-5));
      expect(world.getTranslation().z, closeTo(eye.z, 1e-5));
      final forward = _column(world, 2).normalized();
      final want = (target - eye).normalized();
      expect(forward.x, closeTo(want.x, 1e-5));
      expect(forward.y, closeTo(want.y, 1e-5));
      expect(forward.z, closeTo(want.z, 1e-5));
    });
  });

  group('Node.lookAt', () {
    test('reorients while preserving world position and scale', () {
      final node = Node()
        ..position = Vector3(2.0, 5.0, -3.0)
        ..scale = Vector3(2.0, 3.0, 4.0);

      node.lookAt(Vector3(0.0, 0.0, 0.0));

      final world = node.globalTransform;
      expect(world.getTranslation().x, closeTo(2.0, 1e-5));
      expect(world.getTranslation().y, closeTo(5.0, 1e-5));
      expect(world.getTranslation().z, closeTo(-3.0, 1e-5));
      // World scale is the length of each basis column.
      expect(_column(world, 0).length, closeTo(2.0, 1e-5));
      expect(_column(world, 1).length, closeTo(3.0, 1e-5));
      expect(_column(world, 2).length, closeTo(4.0, 1e-5));

      final forward = _column(world, 2).normalized();
      final want = (Vector3.zero() - node.position).normalized();
      expect(forward.x, closeTo(want.x, 1e-5));
      expect(forward.y, closeTo(want.y, 1e-5));
      expect(forward.z, closeTo(want.z, 1e-5));
    });
  });
}
