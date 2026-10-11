import 'dart:ui' as ui;

import 'package:flutter_scene/scene.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/render/view_group.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/render/viewport_camera.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

// A stereo pair: two eyes [ipd] apart on the camera's right axis, both
// looking along -Z from z = 0, with the asymmetric lenses a headset reports
// (wider away from the nose).
({PerspectiveCamera left, PerspectiveCamera right}) _pair({
  double ipd = 0.064,
}) {
  PerspectiveCamera eye(double x) => PerspectiveCamera(
    position: Vector3(x, 1.6, 0),
    target: Vector3(x, 1.6, -1),
    fovNear: 0.1,
    fovFar: 100,
  );
  return (left: eye(-ipd / 2), right: eye(ipd / 2));
}

const _size = ui.Size(100, 100);

void main() {
  group('combinedCullingFrustum', () {
    test('contains what either eye sees and rejects what neither does', () {
      final eyes = _pair();
      final frustum = combinedCullingFrustum(
        [eyes.left, eyes.right],
        const [_size, _size],
      );
      final leftOnly = cullingFrustumOf(eyes.left, _size);
      final rightOnly = cullingFrustumOf(eyes.right, _size);
      // Just inside the right eye's right edge at depth 10, outside the left
      // eye's: the union keeps it.
      final rightEdge = Vector3(0.032 + 10 * 0.41 - 0.01, 1.6, -10);
      expect(rightOnly.containsVector3(rightEdge), isTrue);
      expect(leftOnly.containsVector3(rightEdge), isFalse);
      expect(frustum.containsVector3(rightEdge), isTrue);
      final leftEdge = Vector3(-0.032 - 10 * 0.41 + 0.01, 1.6, -10);
      expect(frustum.containsVector3(leftEdge), isTrue);
      // Well outside both, and behind both.
      expect(frustum.containsVector3(Vector3(20, 1.6, -10)), isFalse);
      expect(frustum.containsVector3(Vector3(0, 1.6, 5)), isFalse);
      // Past the far plane of both.
      expect(frustum.containsVector3(Vector3(0, 1.6, -200)), isFalse);
    });

    test('a single view is its own culling frustum', () {
      final eyes = _pair();
      final one = combinedCullingFrustum([eyes.left], const [_size]);
      final own = cullingFrustumOf(eyes.left, _size);
      for (var i = 0; i < 6; i++) {
        final a = [
          one.plane0,
          one.plane1,
          one.plane2,
          one.plane3,
          one.plane4,
          one.plane5,
        ][i];
        final b = [
          own.plane0,
          own.plane1,
          own.plane2,
          own.plane3,
          own.plane4,
          own.plane5,
        ][i];
        expect(a.normal.distanceTo(b.normal), lessThan(1e-9));
        expect(a.constant, closeTo(b.constant, 1e-9));
      }
    });

    test('views looking opposite ways cull nothing sideways', () {
      final forward = PerspectiveCamera(
        position: Vector3.zero(),
        target: Vector3(0, 0, -1),
      );
      final backward = PerspectiveCamera(
        position: Vector3.zero(),
        target: Vector3(0, 0, 1),
      );
      final frustum = combinedCullingFrustum(
        [forward, backward],
        const [_size, _size],
      );
      expect(frustum.containsVector3(Vector3(0, 0, -5)), isTrue);
      expect(frustum.containsVector3(Vector3(0, 0, 5)), isTrue);
      expect(frustum.containsVector3(Vector3(50, 0, -5)), isTrue);
    });
  });

  group('combinedViewCamera', () {
    test('sits behind the eyes and sees everything both eyes see', () {
      final eyes = _pair();
      final combined = combinedViewCamera(
        [eyes.left, eyes.right],
        const [_size, _size],
      )!;
      // The apex is on the midline, behind the eyes.
      expect(combined.position.x, closeTo(0, 1e-6));
      expect(combined.position.y, closeTo(1.6, 1e-6));
      expect(combined.position.z, greaterThan(0));
      final projection = combined.projection as OffAxisProjection;
      // Symmetric eyes give a symmetric combined lens.
      expect(projection.tanLeft, closeTo(-projection.tanRight, 1e-9));
      expect(projection.tanDown, closeTo(-projection.tanUp, 1e-9));
      // The near plane moved back by the apex offset.
      expect(projection.near, closeTo(0.1 + combined.position.z, 1e-6));
      // Every corner of each eye's frustum lies inside the combined one.
      final frustum = cullingFrustumOf(combined, _size);
      for (final eye in [eyes.left, eyes.right]) {
        final own = cullingFrustumOf(eye, _size);
        final c = List<Vector3>.generate(8, (_) => Vector3.zero());
        own.calculateCorners(c[0], c[1], c[2], c[3], c[4], c[5], c[6], c[7]);
        for (final corner in c) {
          // The corners of a far plane 100 units out carry float32 error.
          expect(
            frustum.containsVector3(corner) ||
                [
                  frustum.plane0,
                  frustum.plane1,
                  frustum.plane2,
                  frustum.plane3,
                  frustum.plane4,
                  frustum.plane5,
                ].every((p) => p.distanceToVector3(corner) > -1e-3),
            isTrue,
            reason: '$corner should be inside the combined frustum',
          );
        }
      }
    });

    test('is the view itself for one view', () {
      final eyes = _pair();
      expect(
        identical(combinedViewCamera([eyes.left], const [_size]), eyes.left),
        isTrue,
      );
    });

    test('declines views that are not parallel or not pinhole', () {
      final a = PerspectiveCamera(
        position: Vector3.zero(),
        target: Vector3(0, 0, -1),
      );
      final turned = PerspectiveCamera(
        position: Vector3(0.1, 0, 0),
        target: Vector3(1, 0, -1),
      );
      expect(combinedViewCamera([a, turned], const [_size, _size]), isNull);
      final ortho = OrthographicCamera(
        position: Vector3(0.1, 0, 0),
        target: Vector3(0.1, 0, -1),
      );
      expect(combinedViewCamera([a, ortho], const [_size, _size]), isNull);
    });
  });

  test('RenderViewGroup needs at least one view', () {
    expect(() => RenderViewGroup(const []), throwsAssertionError);
  });
}
