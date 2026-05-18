// Covers DirectionalLight's shadow matrix math: the texel snapping that
// keeps the shadow map's grid pinned to the world, and the cascaded
// shadow map split scheme and per-cascade fitting.

import 'dart:math';

import 'package:flutter_scene/src/camera.dart';
import 'package:flutter_scene/src/light.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

void main() {
  group('DirectionalLight.computeLightSpaceMatrix', () {
    // Snapping shifts the projection so a fixed world reference lands on
    // a texel center. The world origin should therefore project to an
    // integer texel for any focus point; that is what keeps the texel
    // grid pinned to the world.
    test('texel snapping pins the world origin to a texel center', () {
      for (final focus in [
        Vector3(0.3, 0.0, 0.0),
        Vector3(5.123, 0.0, -2.7),
        Vector3(-11.9, 0.4, 8.05),
      ]) {
        final light = DirectionalLight(
          direction: Vector3(-0.3, -1.0, -0.2),
          castsShadow: true,
          shadowFocusPoint: focus,
        );
        final clip = light.computeLightSpaceMatrix().transformed(
          Vector4(0, 0, 0, 1),
        );
        final resolution = light.shadowMapResolution.toDouble();
        final texelX = (clip.x * 0.5 + 0.5) * resolution;
        final texelY = (clip.y * 0.5 + 0.5) * resolution;
        expect(texelX - texelX.roundToDouble(), closeTo(0.0, 1e-3));
        expect(texelY - texelY.roundToDouble(), closeTo(0.0, 1e-3));
      }
    });
  });

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
  });
}
