// Covers CameraPath: the curve passes through its waypoints, is parameterized
// by arc length (so equal distance steps cover equal ground), and closes
// cleanly when asked to.

import 'dart:math' as math;

import 'package:flutter_scene/scene.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

void main() {
  group('CameraPath', () {
    test('a straight line has the length of the line', () {
      final path = CameraPath.line(Vector3.zero(), Vector3(0.0, 0.0, 10.0));
      expect(path.length, closeTo(10.0, 1e-4));
      expect(path.pointAt(5.0).z, closeTo(5.0, 1e-4));
      expect(path.pointAtFraction(0.25).z, closeTo(2.5, 1e-4));
    });

    test('passes through every waypoint', () {
      final waypoints = [
        Vector3(0.0, 0.0, 0.0),
        Vector3(4.0, 2.0, 1.0),
        Vector3(9.0, -1.0, 6.0),
        Vector3(12.0, 3.0, 2.0),
      ];
      final path = CameraPath(waypoints);
      for (final waypoint in waypoints) {
        final nearest = path.pointAt(path.nearestDistanceTo(waypoint));
        expect(
          (nearest - waypoint).length,
          lessThan(0.05),
          reason: 'curve misses $waypoint',
        );
      }
    });

    test('is arc-length parameterized, not segment parameterized', () {
      // Deliberately lopsided spacing: a curve parameterized by segment index
      // would cover the long segment far faster than the short one.
      final path = CameraPath([
        Vector3(0.0, 0.0, 0.0),
        Vector3(0.0, 0.0, 1.0),
        Vector3(0.0, 0.0, 40.0),
      ], samplesPerSegment: 64);

      const steps = 20;
      final stride = path.length / steps;
      var previous = path.pointAt(0.0);
      final travelled = <double>[];
      for (var i = 1; i <= steps; i++) {
        final point = path.pointAt(stride * i);
        travelled.add((point - previous).length);
        previous = point;
      }
      for (final step in travelled) {
        expect(step, closeTo(stride, stride * 0.06));
      }
    });

    test('clamps past the end of an open path', () {
      final path = CameraPath.line(Vector3.zero(), Vector3(0.0, 0.0, 10.0));
      expect(path.pointAt(1000.0).z, closeTo(10.0, 1e-4));
      expect(path.pointAt(-5.0).z, closeTo(0.0, 1e-4));
    });

    test('wraps around a closed path', () {
      final path = CameraPath.orbit(Vector3.zero(), radius: 5.0, height: 0.0);
      final start = path.pointAt(0.0);
      final wrapped = path.pointAt(path.length);
      expect((wrapped - start).length, lessThan(0.05));

      final past = path.pointAt(path.length * 1.25);
      final quarter = path.pointAt(path.length * 0.25);
      expect((past - quarter).length, lessThan(0.05));
    });

    test('an orbit stays on its radius', () {
      final path = CameraPath.orbit(
        Vector3(2.0, 0.0, -3.0),
        radius: 8.0,
        height: 4.0,
      );
      for (var i = 0; i <= 24; i++) {
        final point = path.pointAtFraction(i / 24);
        final radial = Vector2(point.x - 2.0, point.z + 3.0).length;
        expect(radial, closeTo(8.0, 0.05));
        expect(point.y, closeTo(4.0, 1e-4));
      }
      expect(path.length, closeTo(2 * math.pi * 8.0, 0.5));
    });

    test('the tangent points along the direction of travel', () {
      final path = CameraPath.line(Vector3.zero(), Vector3(0.0, 0.0, 10.0));
      final tangent = path.tangentAt(5.0);
      expect(tangent.z, closeTo(1.0, 1e-4));
      expect(tangent.length, closeTo(1.0, 1e-6));
    });

    test('rejects a path with fewer than two waypoints', () {
      expect(
        () => CameraPath([Vector3.zero()]),
        throwsA(isA<AssertionError>()),
      );
    });
  });
}
