// Covers the orthographic lens: the projection matches the engine's clip
// convention (+Z forward, depth on [0, 1]), size is independent of distance,
// unprojected rays are parallel, and two ortho lenses blend as a zoom.

import 'dart:ui' show Offset, Size;

import 'package:flutter_scene/scene.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

// Projects a world point to NDC through [camera] on a square target.
Vector3 _ndc(Camera camera, Vector3 world, {double aspect = 1.0}) {
  final clip = camera
      .getViewTransform(Size(aspect, 1.0))
      .transform(Vector4(world.x, world.y, world.z, 1.0));
  return Vector3(clip.x / clip.w, clip.y / clip.w, clip.z / clip.w);
}

void main() {
  group('OrthographicProjection', () {
    test('maps the near and far planes onto 0 and 1', () {
      final projection = OrthographicProjection(height: 10, near: 2, far: 12);
      final matrix = projection.getProjectionMatrix(1.0);

      Vector4 clip(double viewZ) =>
          matrix.transform(Vector4(0.0, 0.0, viewZ, 1.0));
      expect(clip(2.0).z / clip(2.0).w, closeTo(0.0, 1e-9));
      expect(clip(12.0).z / clip(12.0).w, closeTo(1.0, 1e-9));
      expect(clip(7.0).z / clip(7.0).w, closeTo(0.5, 1e-9));
    });

    test('height sets the vertical extent and aspect sets the horizontal', () {
      final projection = OrthographicProjection(height: 10);
      expect(projection.widthFor(2.0), 20.0);

      final matrix = projection.getProjectionMatrix(2.0);
      // Half the vertical extent is the top edge; half the horizontal extent
      // (height * aspect) is the right edge.
      final top = matrix.transform(Vector4(0.0, 5.0, 5.0, 1.0));
      expect(top.y / top.w, closeTo(1.0, 1e-9));
      final rightEdge = matrix.transform(Vector4(10.0, 0.0, 5.0, 1.0));
      expect(rightEdge.x / rightEdge.w, closeTo(1.0, 1e-9));
    });

    test('accepts a near plane at or behind the eye', () {
      final projection = OrthographicProjection(near: -50, far: 50);
      final matrix = projection.getProjectionMatrix(1.0);
      final behind = matrix.transform(Vector4(0.0, 0.0, -50.0, 1.0));
      expect(behind.z / behind.w, closeTo(0.0, 1e-6));
    });

    test('lerpTo blends the view size as a zoom', () {
      final a = OrthographicProjection(height: 10, near: 0, far: 100);
      final b = OrthographicProjection(height: 30, near: 0, far: 100);
      final mid = a.lerpTo(b, 0.25);
      expect(mid, isA<OrthographicProjection>());
      expect((mid as OrthographicProjection).height, closeTo(15.0, 1e-9));
    });
  });

  group('OrthographicCamera', () {
    test('keeps size independent of distance', () {
      final camera = OrthographicCamera(
        position: Vector3(0.0, 0.0, -5.0),
        target: Vector3.zero(),
        height: 10.0,
        far: 500.0,
      );
      // The same world offset from the view axis lands at the same place on
      // screen whether it is near or far. That is the whole point of a
      // parallel lens, and the thing a perspective camera cannot do.
      final near = _ndc(camera, Vector3(5.0, 0.0, 0.0));
      final far = _ndc(camera, Vector3(5.0, 0.0, 400.0));
      expect(near.x, closeTo(1.0, 1e-6));
      expect(far.x, closeTo(1.0, 1e-6));
      expect(far.z, greaterThan(near.z));
    });

    test('unprojects parallel rays', () {
      final camera = OrthographicCamera(
        position: Vector3(0.0, 0.0, -5.0),
        target: Vector3.zero(),
        height: 10.0,
      );
      const viewSize = Size(200.0, 100.0);
      final left = camera.screenPointToRay(const Offset(10.0, 50.0), viewSize);
      final right = camera.screenPointToRay(
        const Offset(190.0, 20.0),
        viewSize,
      );

      final a = left.direction.normalized();
      final b = right.direction.normalized();
      expect(a.dot(b), closeTo(1.0, 1e-5));
      expect(a.dot(camera.forward), closeTo(1.0, 1e-5));
      // The origins differ: an orthographic ray starts at its own point on
      // the near plane rather than at a shared eye.
      expect((left.origin - right.origin).length, greaterThan(1.0));
    });

    test('framing fits the bounds inside the view', () {
      final bounds = Aabb3.minMax(
        Vector3(-2.0, -2.0, -2.0),
        Vector3(2.0, 2.0, 2.0),
      );
      final camera = OrthographicCamera.framing(bounds);
      for (final corner in [bounds.min, bounds.max, Vector3.zero()]) {
        final ndc = _ndc(camera, corner);
        expect(ndc.x.abs(), lessThanOrEqualTo(1.0));
        expect(ndc.y.abs(), lessThanOrEqualTo(1.0));
        expect(ndc.z, inInclusiveRange(0.0, 1.0));
      }
    });
  });
}
