// The planar reflection math core: the world-space reflection transform, the
// reflected camera's view matrix, and the oblique near-plane projection
// (including the clip-bias sign). All headless; no GPU is involved.

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter_scene/src/camera.dart';
import 'package:flutter_scene/src/render/planar_reflection.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

void expectVector3(Vector3 actual, Vector3 expected, {double epsilon = 1e-6}) {
  expect(
    (actual - expected).length,
    lessThan(epsilon),
    reason: 'expected $expected, got $actual',
  );
}

void expectMatrix(Matrix4 actual, Matrix4 expected, {double epsilon = 1e-6}) {
  for (var i = 0; i < 16; i++) {
    expect(
      actual.storage[i],
      closeTo(expected.storage[i], epsilon),
      reason: 'entry $i of\n$actual\nvs\n$expected',
    );
  }
}

// Projects a world point through [camera] at [size], returning clip space.
Vector4 projectPoint(Camera camera, ui.Size size, Vector3 point) {
  return camera
      .getViewTransform(size)
      .transform(Vector4(point.x, point.y, point.z, 1.0));
}

void main() {
  final floor = Plane.normalconstant(Vector3(0, 1, 0), 0.0);
  const size = ui.Size(640, 480);

  group('planarReflectionMatrix', () {
    test('reflects points across the plane and fixes on-plane points', () {
      final reflect = planarReflectionMatrix(floor);
      expectVector3(reflect.transformed3(Vector3(1, 2, 3)), Vector3(1, -2, 3));
      expectVector3(reflect.transformed3(Vector3(4, 0, -7)), Vector3(4, 0, -7));

      // An offset, tilted plane: x + 2 = 0.
      final wall = Plane.normalconstant(Vector3(1, 0, 0), 2.0);
      final wallReflect = planarReflectionMatrix(wall);
      expectVector3(
        wallReflect.transformed3(Vector3(0, 1, 1)),
        Vector3(-4, 1, 1),
      );
      expectVector3(
        wallReflect.transformed3(Vector3(-2, 5, 9)),
        Vector3(-2, 5, 9),
      );
    });

    test('is an involution with determinant -1', () {
      final plane = Plane.normalconstant(
        Vector3(1, 2, -0.5).normalized(),
        1.25,
      );
      final reflect = planarReflectionMatrix(plane);
      expect(reflect.determinant(), closeTo(-1.0, 1e-6));
      expectMatrix(reflect * reflect as Matrix4, Matrix4.identity());
    });

    test('matches the point and direction helpers', () {
      final plane = Plane.normalconstant(Vector3(0, 0.6, 0.8), -0.5);
      final reflect = planarReflectionMatrix(plane);
      final point = Vector3(0.3, -1.7, 2.2);
      expectVector3(
        reflectPointAcrossPlane(point, plane),
        reflect.transformed3(point),
      );
      final direction = Vector3(0.5, 0.5, -1.0);
      final reflected = reflectDirectionAcrossPlane(direction, plane);
      // Directions ignore the plane offset: reflect two points and subtract.
      expectVector3(
        reflected,
        reflectPointAcrossPlane(point + direction, plane) -
            reflectPointAcrossPlane(point, plane),
      );
      // Reflection preserves length.
      expect(reflected.length, closeTo(direction.length, 1e-6));
    });
  });

  group('PlanarReflectionCamera', () {
    test('view matrix equals the engine look-at of the reflected basis', () {
      final source = PerspectiveCamera(
        position: Vector3(0, 2, -5),
        target: Vector3(1, 0, 3),
        up: Vector3(0, 1, 0),
        fovRadiansY: 60 * degrees2Radians,
        fovNear: 0.25,
        fovFar: 80.0,
      );
      final reflected = PlanarReflectionCamera(source: source, plane: floor);

      // Hand-reflected across y = 0: the eye mirrors below the plane, the
      // target (already on the plane) is fixed, and up flips.
      expectVector3(reflected.position, Vector3(0, -2, -5));
      final expected = PerspectiveCamera(
        position: Vector3(0, -2, -5),
        target: Vector3(1, 0, 3),
        up: Vector3(0, -1, 0),
      );
      expectVector3(reflected.forward, Vector3(1, 2, 8).normalized());
      expectMatrix(reflected.getViewMatrix(), expected.getViewMatrix());
    });

    test('reflected view basis stays proper (no winding flip)', () {
      final source = PerspectiveCamera(
        position: Vector3(3, 4, -6),
        target: Vector3(-1, 0.5, 2),
      );
      final view = PlanarReflectionCamera(
        source: source,
        plane: Plane.normalconstant(Vector3(0.2, 0.9, -0.1).normalized(), 0.4),
      ).getViewMatrix();
      // A proper rotation-plus-translation has determinant +1; an improper
      // (mirroring) view would flip every triangle's winding.
      expect(view.determinant(), closeTo(1.0, 1e-6));
    });

    test('on-plane points project mirror-symmetrically in both cameras', () {
      // A point on the mirror surface is shared by both views. With the
      // proper reflected basis the horizontal axis mirrors (right becomes
      // minus the reflected right) while the vertical matches, which is what
      // makes the sampled capture read as a mirror image. The sampler itself
      // only relies on projecting through the capture's own view-projection,
      // so this pins the orientation contract.
      final source = PerspectiveCamera(
        position: Vector3(1, 3, -4),
        target: Vector3(0, 0, 2),
      );
      final reflected = PlanarReflectionCamera(source: source, plane: floor);
      for (final point in [
        Vector3(0, 0, 1),
        Vector3(2, 0, 3),
        Vector3(-1.5, 0, -0.5),
      ]) {
        final a = projectPoint(source, size, point);
        final b = projectPoint(reflected, size, point);
        expect(a.x / a.w, closeTo(-b.x / b.w, 1e-5));
        expect(a.y / a.w, closeTo(b.y / b.w, 1e-5));
        expect(a.w, closeTo(b.w, 1e-5));
      }
    });

    test('a non-perspective projection passes through unclipped', () {
      final projection = _FixedProjection();
      final source = _FixedProjectionCamera(projection);
      final reflected = PlanarReflectionCamera(source: source, plane: floor);
      expect(reflected.projection, same(projection));
    });
  });

  group('obliqueNearClipProjection', () {
    final source = PerspectiveCamera(
      position: Vector3(0, 2, -5),
      target: Vector3(0, 0, 0),
      fovRadiansY: 45 * degrees2Radians,
      fovNear: 0.1,
      fovFar: 100.0,
    );

    Matrix4 oblique({double clipBias = 0.0}) {
      final reflected = PlanarReflectionCamera(
        source: source,
        plane: floor,
        clipBias: clipBias,
      );
      return reflected.getViewTransform(size);
    }

    test('keeps the x, y, and w rows of the base projection', () {
      final reflected = PlanarReflectionCamera(source: source, plane: floor);
      final base = PerspectiveProjection(
        fovRadiansY: 45 * degrees2Radians,
        near: 0.1,
        far: 100.0,
      ).getProjectionMatrix(size.width / size.height);
      final clipped = reflected.projection.getProjectionMatrix(
        size.width / size.height,
      );
      for (final row in [0, 1, 3]) {
        for (var column = 0; column < 4; column++) {
          expect(
            clipped.entry(row, column),
            closeTo(base.entry(row, column), 1e-6),
            reason: 'row $row column $column',
          );
        }
      }
    });

    test('maps points on the mirror plane to depth zero', () {
      final viewProjection = oblique();
      for (final point in [
        Vector3(0, 0, 0.5),
        Vector3(1.5, 0, 2),
        Vector3(-2, 0, 4),
      ]) {
        final clip = viewProjection.transform(
          Vector4(point.x, point.y, point.z, 1.0),
        );
        expect(clip.z / clip.w, closeTo(0.0, 1e-5));
      }
    });

    test('clips geometry behind the mirror, keeps geometry in front', () {
      final viewProjection = oblique();
      // The reflected camera looks up from below; world points above the
      // plane (the mirrored scene) are kept, points below are clipped.
      final kept = viewProjection.transform(Vector4(0, 1.0, 1.0, 1.0));
      expect(kept.z / kept.w, greaterThan(0.0));
      final clipped = viewProjection.transform(Vector4(0, -1.0, 1.0, 1.0));
      expect(clipped.z / clipped.w, lessThan(0.0));
    });

    test('clip bias moves the clip boundary in front of the plane', () {
      const bias = 1e-2;
      final viewProjection = oblique(clipBias: bias);
      // On the plane (the mirror surface itself): now behind the clip.
      final onPlane = viewProjection.transform(Vector4(0, 0, 1.0, 1.0));
      expect(onPlane.z / onPlane.w, lessThan(0.0));
      // Inside the bias band: still clipped.
      final inBand = viewProjection.transform(Vector4(0, bias * 0.5, 1.0, 1.0));
      expect(inBand.z / inBand.w, lessThan(0.0));
      // Past the bias band: kept.
      final past = viewProjection.transform(Vector4(0, bias * 4.0, 1.0, 1.0));
      expect(past.z / past.w, greaterThan(0.0));
    });

    test('far depth stays bounded by one', () {
      final viewProjection = oblique();
      // Sample visible points through the frustum; none may exceed the far
      // depth, which the oblique matrix preserves at the anchor corner.
      final random = math.Random(7);
      for (var i = 0; i < 200; i++) {
        final point = Vector4(
          (random.nextDouble() - 0.5) * 40.0,
          random.nextDouble() * 20.0,
          (random.nextDouble() - 0.5) * 40.0,
          1.0,
        );
        final clip = viewProjection.transform(Vector4.copy(point));
        if (clip.w <= 0) continue;
        final inXy =
            (clip.x / clip.w).abs() <= 1.0 && (clip.y / clip.w).abs() <= 1.0;
        if (!inXy) continue;
        expect(
          clip.z / clip.w,
          lessThanOrEqualTo(1.0 + 1e-4),
          reason: 'point $point exceeded the far plane',
        );
      }
    });

    test('a degenerate plane leaves the projection unchanged', () {
      final base = PerspectiveProjection().getProjectionMatrix(1.5);
      final unchanged = obliqueNearClipProjection(base, Vector4.zero());
      expectMatrix(unchanged, base);
    });
  });
}

class _FixedProjection extends CameraProjection {
  @override
  Matrix4 getProjectionMatrix(double aspectRatio, {Vector2? jitter}) =>
      Matrix4.identity();
}

class _FixedProjectionCamera extends Camera {
  _FixedProjectionCamera(this._projection);

  final CameraProjection _projection;

  @override
  Vector3 get position => Vector3(0, 1, -2);

  @override
  Vector3 get forward => Vector3(0, 0, 1);

  @override
  Vector3 get up => Vector3(0, 1, 0);

  @override
  CameraProjection get projection => _projection;

  @override
  Matrix4 getViewMatrix() => makeViewMatrix(position, position + forward, up);
}
