// The level-of-detail selection core: the projected-screen-size metric and
// the threshold selection with its cull floor and hysteresis dead-band.
// Pure logic, so these run without a Flutter GPU context.

import 'dart:math' as math;

import 'package:flutter_scene/src/render/lod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

void main() {
  group('lodScreenSize', () {
    const fov = math.pi / 2; // 90 degrees, tan(fov/2) == 1

    test('halves as the object moves twice as far', () {
      double sizeAt(double distance) => lodScreenSize(
        center: Vector3(0, 0, -distance),
        radius: 1,
        cameraPosition: Vector3.zero(),
        fovRadiansY: fov,
      );
      // With tan(fov/2) == 1, size == radius / distance.
      expect(sizeAt(2), closeTo(0.5, 1e-9));
      expect(sizeAt(4), closeTo(0.25, 1e-9));
    });

    test('a wider field of view shrinks the projected size', () {
      double sizeAt(double f) => lodScreenSize(
        center: Vector3(0, 0, -4),
        radius: 1,
        cameraPosition: Vector3.zero(),
        fovRadiansY: f,
      );
      expect(sizeAt(math.pi / 3), greaterThan(sizeAt(math.pi / 2)));
    });

    test('the camera inside the sphere yields infinity', () {
      expect(
        lodScreenSize(
          center: Vector3.zero(),
          radius: 2,
          cameraPosition: Vector3(0, 0, 1),
          fovRadiansY: fov,
        ),
        double.infinity,
      );
    });
  });

  group('selectLodLevel', () {
    final thresholds = [0.5, 0.25, 0.1]; // three levels, cull below 0.1

    test('picks the highest detail whose threshold is met', () {
      expect(selectLodLevel(0.8, thresholds), 0);
      expect(selectLodLevel(0.5, thresholds), 0);
      expect(selectLodLevel(0.3, thresholds), 1);
      expect(selectLodLevel(0.1, thresholds), 2);
    });

    test('culls below the smallest threshold', () {
      expect(selectLodLevel(0.05, thresholds), -1);
    });

    test('a zero last threshold never culls', () {
      expect(selectLodLevel(0.0, [0.5, 0.0]), 1);
    });

    test('hysteresis holds the current level inside the dead-band', () {
      // The 1<->2 boundary is 0.25; with a 20% margin level 1 holds down to
      // 0.20 and level 2 holds up to 0.30.
      expect(
        selectLodLevel(0.22, thresholds, hysteresis: 0.2, currentLevel: 1),
        1, // would be 2 without hysteresis, but stays 1
      );
      expect(
        selectLodLevel(0.28, thresholds, hysteresis: 0.2, currentLevel: 2),
        2, // would be 1 without hysteresis, but stays 2
      );
    });

    test('hysteresis still switches once clearly past the boundary', () {
      expect(
        selectLodLevel(0.18, thresholds, hysteresis: 0.2, currentLevel: 1),
        2, // below 0.25 * 0.8, so it drops
      );
      expect(
        selectLodLevel(0.32, thresholds, hysteresis: 0.2, currentLevel: 2),
        1, // above 0.25 * 1.2, so it rises
      );
    });

    test('hysteresis brackets the cull floor too', () {
      // Holding level 2 just under the floor, and staying culled just over it.
      expect(
        selectLodLevel(0.095, thresholds, hysteresis: 0.2, currentLevel: 2),
        2,
      );
      expect(
        selectLodLevel(0.105, thresholds, hysteresis: 0.2, currentLevel: -1),
        -1,
      );
      // Clearly past in each direction.
      expect(
        selectLodLevel(0.07, thresholds, hysteresis: 0.2, currentLevel: 2),
        -1,
      );
      expect(
        selectLodLevel(0.13, thresholds, hysteresis: 0.2, currentLevel: -1),
        2,
      );
    });

    test('a non-adjacent jump switches immediately despite hysteresis', () {
      expect(
        selectLodLevel(0.9, thresholds, hysteresis: 0.5, currentLevel: 2),
        0,
      );
    });
  });
}
