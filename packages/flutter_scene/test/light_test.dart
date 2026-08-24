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

    test('static shadow caching is enabled by default and can be disabled', () {
      expect(DirectionalLight().cacheStaticShadows, isTrue);
      expect(
        DirectionalLight(cacheStaticShadows: false).cacheStaticShadows,
        isFalse,
      );
    });

    test('rotated shadow filtering is the default', () {
      expect(
        DirectionalLight().shadowFilter,
        DirectionalShadowFilter.rotatedPoisson,
      );
      expect(
        DirectionalLight(
          shadowFilter: DirectionalShadowFilter.fixedPcf,
        ).shadowFilter,
        DirectionalShadowFilter.fixedPcf,
      );
      expect(
        DirectionalLight(
          shadowFilter: DirectionalShadowFilter.bilinearPcf,
        ).shadowFilter,
        DirectionalShadowFilter.bilinearPcf,
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

    test('uses the minimum stable frustum-slice sphere', () {
      final light = DirectionalLight(
        castsShadow: true,
        shadowCascadeCount: 1,
        shadowMaxDistance: 90,
      );
      final cascade = light.computeCascades(camera, aspectRatio).single;
      final tanV = tan(camera.fovRadiansY * 0.5);
      final tanH = tanV * aspectRatio;
      final tanRadius2 = tanH * tanH + tanV * tanV;
      final centerDepth = min(
        light.shadowMaxDistance,
        (camera.fovNear + light.shadowMaxDistance) * (1.0 + tanRadius2) * 0.5,
      );
      final expectedRadius = sqrt(
        max(
          pow(centerDepth - camera.fovNear, 2) +
              camera.fovNear * camera.fovNear * tanRadius2,
          pow(light.shadowMaxDistance - centerDepth, 2) +
              light.shadowMaxDistance * light.shadowMaxDistance * tanRadius2,
        ),
      );
      final midpointRadius = sqrt(
        pow((light.shadowMaxDistance - camera.fovNear) * 0.5, 2) +
            light.shadowMaxDistance * light.shadowMaxDistance * tanRadius2,
      );
      expect(cascade.center, isNotNull);
      expect(
        (cascade.center! - camera.position).dot(camera.forward),
        closeTo(centerDepth, 1e-5),
      );
      expect(cascade.radius, closeTo(expectedRadius, 1e-6));
      expect(cascade.radius, lessThan(midpointRadius));
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

  group('DirectionalLight cascade shaping', () {
    const aspectRatio = 16.0 / 9.0;
    PerspectiveCamera cameraAt(Vector3 position, Vector3 target) =>
        PerspectiveCamera(position: position, target: target);

    final views = [
      cameraAt(Vector3(0, 8, -20), Vector3(0, 0, 0)),
      cameraAt(Vector3(37, 3, 12), Vector3(-4, 9, -30)),
      cameraAt(Vector3(-120, 60, 5), Vector3(0, 0, 0)),
    ];

    test('the knobs default to automatic and no overlap', () {
      expect(DirectionalLight().firstCascadeFarBound, isNull);
      expect(DirectionalLight().cascadeOverlap, 0.0);
    });

    test('firstCascadeFarBound pins the first split across camera moves', () {
      final light = DirectionalLight(
        castsShadow: true,
        shadowCascadeCount: 4,
        firstCascadeFarBound: 18.0,
      );
      for (final camera in views) {
        final cascades = light.computeCascades(camera, aspectRatio);
        expect(cascades.first.splitDistance, closeTo(18.0, 1e-9));
        // The rest still spread out to the shadow distance, in order.
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
      }
    });

    test('a pinned bound is clamped inside the shadowed range', () {
      final camera = views.first;
      // Below the near plane the pin clamps strictly above it, so cascade 0
      // keeps thickness instead of collapsing to a zero-width slice.
      final near = DirectionalLight(
        shadowCascadeCount: 3,
        firstCascadeFarBound: -5.0,
      ).computeCascades(camera, aspectRatio);
      expect(near.first.splitDistance, greaterThan(camera.fovNear));
      for (var i = 1; i < near.length; i++) {
        expect(near[i].splitDistance, greaterThan(near[i - 1].splitDistance));
      }

      // At or past shadowMaxDistance the pin would collapse every later
      // cascade onto far, so it falls back to the automatic scheme.
      final control = DirectionalLight(
        shadowCascadeCount: 3,
        shadowMaxDistance: 100.0,
      ).computeCascades(camera, aspectRatio);
      final far = DirectionalLight(
        shadowCascadeCount: 3,
        shadowMaxDistance: 100.0,
        firstCascadeFarBound: 1000.0,
      ).computeCascades(camera, aspectRatio);
      for (var i = 0; i < control.length; i++) {
        expect(far[i].splitDistance, control[i].splitDistance);
      }
    });

    test('a single cascade keeps its far bound', () {
      final camera = views.first;
      final control = DirectionalLight(
        shadowCascadeCount: 1,
      ).computeCascades(camera, aspectRatio);
      final pinned = DirectionalLight(
        shadowCascadeCount: 1,
        firstCascadeFarBound: 20.0,
      ).computeCascades(camera, aspectRatio);
      expect(pinned.single.splitDistance, control.single.splitDistance);
      expect(pinned.single.boxSize, control.single.boxSize);
    });

    test('pinning keeps the fit and the texel snapping', () {
      final light = DirectionalLight(
        castsShadow: true,
        shadowCascadeCount: 3,
        firstCascadeFarBound: 25.0,
        shadowMapResolution: 512,
      );
      final camera = views.first;
      final cascades = light.computeCascades(camera, aspectRatio);
      // The pinned first cascade still fits its own frustum slice.
      final forward = (camera.target - camera.position).normalized();
      final right = camera.up.cross(forward).normalized();
      final up = forward.cross(right).normalized();
      final tanV = tan(camera.fovRadiansY * 0.5);
      final tanH = tanV * aspectRatio;
      for (final depth in [camera.fovNear, 25.0]) {
        final planeCenter = camera.position + forward * depth;
        for (final sx in [-1.0, 1.0]) {
          for (final sy in [-1.0, 1.0]) {
            final corner =
                planeCenter +
                right * (sx * depth * tanH) +
                up * (sy * depth * tanV);
            final clip = cascades.first.lightSpaceMatrix.transformed(
              Vector4(corner.x, corner.y, corner.z, 1),
            );
            expect(clip.x, inInclusiveRange(-1.02, 1.02));
            expect(clip.y, inInclusiveRange(-1.02, 1.02));
            expect(clip.z, inInclusiveRange(0.0, 1.0));
          }
        }
      }
      // Snapping puts the world origin on a texel boundary.
      final origin = cascades.first.lightSpaceMatrix.transformed(
        Vector4(0, 0, 0, 1),
      );
      const resolution = 512.0;
      for (final ndc in [origin.x, origin.y]) {
        final texel = (ndc * 0.5 + 0.5) * resolution;
        expect((texel - texel.roundToDouble()).abs(), lessThan(1e-6));
      }
    });

    test('zero overlap produces the control cascades exactly', () {
      DirectionalLight light({double overlap = 0.0}) => DirectionalLight(
        castsShadow: true,
        shadowCascadeCount: 4,
        cascadeOverlap: overlap,
      );
      for (final camera in views) {
        final control = light().computeCascades(camera, aspectRatio);
        final zero = light(overlap: 0.0).computeCascades(camera, aspectRatio);
        for (var i = 0; i < control.length; i++) {
          expect(zero[i].splitDistance, control[i].splitDistance);
          expect(zero[i].boxSize, control[i].boxSize);
          expect(zero[i].radius, control[i].radius);
          expect(zero[i].center, control[i].center);
          expect(
            zero[i].lightSpaceMatrix.storage,
            control[i].lightSpaceMatrix.storage,
          );
        }
      }
    });

    test('overlap widens every cascade but the last', () {
      final camera = views.first;
      final control = DirectionalLight(
        castsShadow: true,
        shadowCascadeCount: 4,
      ).computeCascades(camera, aspectRatio);
      final overlapped = DirectionalLight(
        castsShadow: true,
        shadowCascadeCount: 4,
        cascadeOverlap: 0.25,
      ).computeCascades(camera, aspectRatio);
      for (var i = 0; i < control.length - 1; i++) {
        expect(overlapped[i].radius, greaterThan(control[i].radius));
        // The split a fragment is assigned by is untouched; only coverage grew.
        expect(overlapped[i].splitDistance, control[i].splitDistance);
      }
      expect(overlapped.last.radius, control.last.radius);
      expect(overlapped.last.splitDistance, control.last.splitDistance);
    });

    test('the overlap fraction is clamped', () {
      final camera = views.first;
      final wide = DirectionalLight(
        shadowCascadeCount: 2,
        cascadeOverlap: 5.0,
      ).computeCascades(camera, aspectRatio);
      final full = DirectionalLight(
        shadowCascadeCount: 2,
        cascadeOverlap: 1.0,
      ).computeCascades(camera, aspectRatio);
      expect(wide.first.radius, full.first.radius);

      final negative = DirectionalLight(
        shadowCascadeCount: 2,
        cascadeOverlap: -1.0,
      ).computeCascades(camera, aspectRatio);
      final none = DirectionalLight(
        shadowCascadeCount: 2,
      ).computeCascades(camera, aspectRatio);
      expect(negative.first.radius, none.first.radius);
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
  test('a first-cascade pin at shadowMaxDistance falls back to automatic', () {
    final light = DirectionalLight()
      ..shadowCascadeCount = 4
      ..shadowMaxDistance = 30.0;
    final camera = PerspectiveCamera(
      position: Vector3(0, 2, 8),
      target: Vector3.zero(),
    );
    final automatic = light.computeCascades(camera, 1.5);
    light.firstCascadeFarBound = 30.0;
    final pinnedAtFar = light.computeCascades(camera, 1.5);
    for (var i = 0; i < automatic.length; i++) {
      expect(pinnedAtFar[i].splitDistance, automatic[i].splitDistance);
    }
    // Past the range behaves the same as at it.
    light.firstCascadeFarBound = 45.0;
    final pinnedPastFar = light.computeCascades(camera, 1.5);
    for (var i = 0; i < automatic.length; i++) {
      expect(pinnedPastFar[i].splitDistance, automatic[i].splitDistance);
    }
  });

  test('a first-cascade pin below the near plane keeps cascade 0 thick', () {
    final light = DirectionalLight()
      ..shadowCascadeCount = 4
      ..shadowMaxDistance = 30.0
      ..firstCascadeFarBound = 0.0;
    final camera = PerspectiveCamera(
      position: Vector3(0, 2, 8),
      target: Vector3.zero(),
    );
    final cascades = light.computeCascades(camera, 1.5);
    // The pin clamps strictly above the near plane, so the first split is a
    // real interval and the later splits stay strictly increasing.
    for (var i = 1; i < cascades.length; i++) {
      expect(
        cascades[i].splitDistance,
        greaterThan(cascades[i - 1].splitDistance),
      );
    }
  });
}
