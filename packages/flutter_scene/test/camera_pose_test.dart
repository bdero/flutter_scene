// Covers CameraPose: it reproduces Node.lookAtFrom exactly, exposes the
// +Z-forward basis, and interpolates position, rotation, and lens for blends.

import 'dart:math' as math;

import 'package:flutter_scene/scene.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

void expectMatrixClose(Matrix4 a, Matrix4 b, {double tolerance = 1e-6}) {
  for (var i = 0; i < 16; i++) {
    expect(a.storage[i], closeTo(b.storage[i], tolerance), reason: 'index $i');
  }
}

void main() {
  group('CameraPose', () {
    test('applyTo matches Node.lookAtFrom', () {
      final eye = Vector3(3.0, 4.0, -5.0);
      final target = Vector3(-1.0, 0.5, 2.0);

      final viaNode = Node()..lookAtFrom(eye, target);
      final viaPose = Node();
      CameraPose.lookAt(eye, target).applyTo(viaPose);

      expectMatrixClose(viaPose.globalTransform, viaNode.globalTransform);
    });

    test('applyTo preserves the node scale it lands on', () {
      final node = Node()
        ..localTransform = Matrix4.diagonal3(Vector3(2.0, 2.0, 2.0));
      CameraPose.lookAt(Vector3(0.0, 0.0, -5.0), Vector3.zero()).applyTo(node);

      final s = node.globalTransform.storage;
      expect(Vector3(s[0], s[1], s[2]).length, closeTo(2.0, 1e-6));
      expect(Vector3(s[4], s[5], s[6]).length, closeTo(2.0, 1e-6));
      expect(Vector3(s[8], s[9], s[10]).length, closeTo(2.0, 1e-6));
    });

    test('forward points at the target and the basis is right-handed', () {
      final pose = CameraPose.lookAt(Vector3(0.0, 0.0, -5.0), Vector3.zero());
      expect(pose.forward.x, closeTo(0.0, 1e-6));
      expect(pose.forward.y, closeTo(0.0, 1e-6));
      expect(pose.forward.z, closeTo(1.0, 1e-6));
      expect(pose.up.y, closeTo(1.0, 1e-6));
      // right = up x forward, matching Node's look-at basis.
      final right = pose.up.cross(pose.forward);
      expect((right - pose.right).length, closeTo(0.0, 1e-6));
    });

    test('fromMatrix drops scale but keeps rotation', () {
      final rotation = Quaternion.axisAngle(Vector3(0.0, 1.0, 0.0), 0.9);
      final transform = Matrix4.compose(
        Vector3(1.0, 2.0, 3.0),
        rotation,
        Vector3(3.0, 3.0, 3.0),
      );
      final pose = CameraPose.fromMatrix(transform);
      expect(pose.position.x, closeTo(1.0, 1e-6));
      expect(pose.rotation.dot(rotation).abs(), closeTo(1.0, 1e-6));
      expect(pose.forward.length, closeTo(1.0, 1e-6));
    });

    test('lerpTo interpolates position and takes the short rotational arc', () {
      final a = CameraPose.lookAt(Vector3(0.0, 0.0, -10.0), Vector3.zero());
      final b = CameraPose.lookAt(Vector3(10.0, 0.0, 0.0), Vector3.zero());

      expect(a.lerpTo(b, 0.0).position.z, closeTo(-10.0, 1e-6));
      expect(a.lerpTo(b, 1.0).position.x, closeTo(10.0, 1e-6));

      final mid = a.lerpTo(b, 0.5);
      expect(mid.position.x, closeTo(5.0, 1e-6));
      expect(mid.position.z, closeTo(-5.0, 1e-6));
      // Halfway around a 90-degree turn, the look direction is 45 degrees
      // between the two, not through some longer arc.
      final angle = math.acos(mid.forward.dot(a.forward).clamp(-1.0, 1.0));
      expect(angle, closeTo(math.pi / 4, 1e-3));
    });

    test('lerpTo blends two lenses of the same kind', () {
      final a = CameraPose.lookAt(
        Vector3(0.0, 0.0, -5.0),
        Vector3.zero(),
        projection: PerspectiveProjection(fovRadiansY: 0.4),
      );
      final b = CameraPose.lookAt(
        Vector3(0.0, 0.0, -5.0),
        Vector3.zero(),
        projection: PerspectiveProjection(fovRadiansY: 1.0),
      );
      final lens = a.lerpTo(b, 0.5).projection;
      expect(lens, isA<PerspectiveProjection>());
      expect((lens as PerspectiveProjection).fovRadiansY, closeTo(0.7, 1e-9));
    });

    test('lerpTo snaps between lenses that cannot be interpolated', () {
      final a = CameraPose.lookAt(
        Vector3(0.0, 0.0, -5.0),
        Vector3.zero(),
        projection: PerspectiveProjection(),
      );
      final b = CameraPose.lookAt(
        Vector3(0.0, 0.0, -5.0),
        Vector3.zero(),
        projection: OrthographicProjection(),
      );
      expect(a.lerpTo(b, 0.25).projection, isA<PerspectiveProjection>());
      expect(a.lerpTo(b, 0.75).projection, isA<OrthographicProjection>());
    });

    test('lerpTo keeps whichever lens is specified when only one is', () {
      final lens = PerspectiveProjection(fovRadiansY: 0.5);
      final a = CameraPose.lookAt(Vector3(0.0, 0.0, -5.0), Vector3.zero());
      final b = CameraPose.lookAt(
        Vector3(0.0, 0.0, -5.0),
        Vector3.zero(),
        projection: lens,
      );
      expect(a.lerpTo(b, 0.5).projection, same(lens));
      expect(b.lerpTo(a, 0.5).projection, same(lens));
    });

    test('translatedLocal and rotatedLocal work in camera space', () {
      // Looking along +X, so the camera's local +Z is world +X.
      final pose = CameraPose.lookAt(Vector3.zero(), Vector3(1.0, 0.0, 0.0));
      final moved = pose.translatedLocal(Vector3(0.0, 0.0, 2.0));
      expect(moved.position.x, closeTo(2.0, 1e-6));

      final turned = pose.rotatedLocal(
        Quaternion.axisAngle(Vector3(0.0, 1.0, 0.0), math.pi / 2),
      );
      // A quarter turn about local up swings the look direction onto world -Z
      // or +Z; either way it leaves the +X axis entirely.
      expect(turned.forward.x.abs(), lessThan(1e-6));
      expect(turned.forward.z.abs(), closeTo(1.0, 1e-6));
    });
  });
}
