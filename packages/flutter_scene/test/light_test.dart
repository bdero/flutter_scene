// Covers DirectionalLight.computeCascades: the cascaded shadow map
// split scheme and per-cascade frustum fitting.

import 'dart:math';

import 'package:flutter_scene/src/camera.dart';
import 'package:flutter_scene/src/light.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

Matrix4 _referenceLookAt(Vector3 position, Vector3 target, Vector3 up) {
  final forward = (target - position).normalized();
  final right = up.cross(forward).normalized();
  final newUp = forward.cross(right).normalized();
  return Matrix4(
    right.x,
    newUp.x,
    forward.x,
    0.0,
    right.y,
    newUp.y,
    forward.y,
    0.0,
    right.z,
    newUp.z,
    forward.z,
    0.0,
    -right.dot(position),
    -newUp.dot(position),
    -forward.dot(position),
    1.0,
  );
}

Matrix4 _referenceCascadeMatrix(
  Vector3 lightDir,
  Vector3 center,
  double radius,
  int resolution,
) {
  const casterReach = 12.0;
  const forwardMargin = 2.0;
  final up = lightDir.y.abs() > 0.99
      ? Vector3(0.0, 0.0, 1.0)
      : Vector3(0.0, 1.0, 0.0);
  final eye = center - lightDir * (radius * casterReach);
  final view = _referenceLookAt(eye, center, up);
  final far = radius * (casterReach + forwardMargin);
  final ortho = Matrix4(
    1.0 / radius,
    0.0,
    0.0,
    0.0,
    0.0,
    1.0 / radius,
    0.0,
    0.0,
    0.0,
    0.0,
    1.0 / far,
    0.0,
    0.0,
    0.0,
    0.0,
    1.0,
  );
  final matrix = ortho * view;
  final reference = matrix.transformed(Vector4(0.0, 0.0, 0.0, 1.0));
  final texelX = (reference.x * 0.5 + 0.5) * resolution;
  final texelY = (reference.y * 0.5 + 0.5) * resolution;
  final offsetX = (texelX.roundToDouble() - texelX) / resolution * 2.0;
  final offsetY = (texelY.roundToDouble() - texelY) / resolution * 2.0;
  return Matrix4.translation(Vector3(offsetX, offsetY, 0.0)) * matrix;
}

void main() {
  group('DirectionalLight.computeCascades', () {
    final camera = PerspectiveCamera(
      position: Vector3(0, 8, -20),
      target: Vector3(0, 0, 0),
    );
    const aspectRatio = 16.0 / 9.0;

    test('returns the requested cascades ordered near to far', () {
      final light = DirectionalLight(castsShadow: true, shadowCascadeCount: 4);
      final cascades = light.computeCascades(camera, aspectRatio);
      expect(cascades, hasLength(4));
      for (var i = 1; i < cascades.length; i++) {
        expect(
          cascades[i].splitDistance,
          greaterThan(cascades[i - 1].splitDistance),
        );
      }
      expect(
        cascades.last.splitDistance,
        closeTo(light.shadowMaxDistance, 1e-6),
      );
    });

    // Every corner of a cascade's slice of the camera frustum must
    // project inside that cascade's shadow box, or geometry in view
    // would fall outside the shadow map.
    test('each frustum slice fits inside its cascade box', () {
      final light = DirectionalLight(castsShadow: true, shadowCascadeCount: 3);
      final cascades = light.computeCascades(camera, aspectRatio);

      final forward = (camera.target - camera.position).normalized();
      final right = camera.up.cross(forward).normalized();
      final up = forward.cross(right).normalized();
      final tanV = tan(camera.fovRadiansY * 0.5);
      final tanH = tanV * aspectRatio;

      var sliceNear = camera.fovNear;
      for (final cascade in cascades) {
        final sliceFar = cascade.splitDistance;
        for (final depth in [sliceNear, sliceFar]) {
          final planeCenter = camera.position + forward * depth;
          for (final sx in [-1.0, 1.0]) {
            for (final sy in [-1.0, 1.0]) {
              final corner =
                  planeCenter +
                  right * (sx * depth * tanH) +
                  up * (sy * depth * tanV);
              final clip = cascade.lightSpaceMatrix.transformed(
                Vector4(corner.x, corner.y, corner.z, 1),
              );
              // Allow a texel of slack for the snapping shift.
              expect(clip.x, inInclusiveRange(-1.02, 1.02));
              expect(clip.y, inInclusiveRange(-1.02, 1.02));
              expect(clip.z, inInclusiveRange(0.0, 1.0));
            }
          }
        }
        sliceNear = sliceFar;
      }
    });

    // Each cascade reports the world-space size of its orthographic
    // box, used to scale world-space softness and fade into UV space.
    test('reports a positive box size for every cascade', () {
      final light = DirectionalLight(castsShadow: true);
      final cascades = light.computeCascades(camera, aspectRatio);
      for (final cascade in cascades) {
        expect(cascade.boxSize, greaterThan(0.0));
      }
    });

    test('scalar cascade matrices match the reference construction', () {
      final light = DirectionalLight(shadowMapResolution: 2048);
      final cases = [
        (Vector3(0.3, -1.0, 0.2).normalized(), Vector3(3, 7, -11), 9.0),
        (Vector3(0.01, -1.0, 0.01).normalized(), Vector3(-40, 2, 91), 31.0),
        (Vector3(-0.7, -0.2, 0.5).normalized(), Vector3(0, 0, 0), 140.0),
      ];
      for (final (direction, center, radius) in cases) {
        final actual = light.cascadeLightSpaceMatrix(direction, center, radius);
        final expected = _referenceCascadeMatrix(
          direction,
          center,
          radius,
          light.shadowMapResolution,
        );
        for (var i = 0; i < 16; i++) {
          expect(actual.storage[i], closeTo(expected.storage[i], 1e-6));
        }
      }
    });
  });

  group('SpotLight.shadowViewProjection', () {
    // A spot at the origin aiming straight down, a 30-degree outer cone,
    // reaching 10 units.
    final light = SpotLight(outerConeAngle: pi / 6, range: 10.0);
    final matrix = light.shadowViewProjection(
      Vector3.zero(),
      Vector3(0, -1, 0),
    );

    Vector3 project(Vector3 world) {
      final clip = matrix * Vector4(world.x, world.y, world.z, 1.0) as Vector4;
      return Vector3(clip.x / clip.w, clip.y / clip.w, clip.z / clip.w);
    }

    test('a point on the axis within range projects to the tile center', () {
      final ndc = project(Vector3(0, -5, 0));
      expect(ndc.x, closeTo(0.0, 1e-5));
      expect(ndc.y, closeTo(0.0, 1e-5));
      expect(ndc.z, greaterThan(0.0));
      expect(ndc.z, lessThan(1.0));
    });

    test('a point well outside the cone falls outside the tile', () {
      // ~63 degrees off the axis, far past the 30-degree cone.
      final ndc = project(Vector3(10, -5, 0));
      expect(ndc.x.abs() > 1.0 || ndc.y.abs() > 1.0, isTrue);
    });

    test('a point past the range is clipped beyond the far plane', () {
      final ndc = project(Vector3(0, -20, 0));
      expect(ndc.z, greaterThan(1.0));
    });

    test('depth increases with distance from the light', () {
      final near = project(Vector3(0, -2, 0)).z;
      final far = project(Vector3(0, -9, 0)).z;
      expect(far, greaterThan(near));
    });
  });
}
