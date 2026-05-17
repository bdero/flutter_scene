// Covers ScenePath: PolylinePath evaluation, arc-length measurement,
// and rotation-minimizing frames. Pure logic, no GPU context needed.

import 'package:flutter_scene/src/scene_path.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

void _expectVector(Vector3 actual, Vector3 expected, {double tol = 1e-6}) {
  expect(actual.x, closeTo(expected.x, tol));
  expect(actual.y, closeTo(expected.y, tol));
  expect(actual.z, closeTo(expected.z, tol));
}

void main() {
  group('PolylinePath', () {
    test('rejects fewer than two points', () {
      expect(() => PolylinePath([Vector3(0, 0, 0)]), throwsArgumentError);
    });

    test('positionAt spans the endpoints', () {
      final path = PolylinePath([Vector3(0, 0, 0), Vector3(4, 0, 0)]);
      _expectVector(path.positionAt(0), Vector3(0, 0, 0));
      _expectVector(path.positionAt(1), Vector3(4, 0, 0));
      _expectVector(path.positionAt(0.5), Vector3(2, 0, 0));
    });

    test('tangentAt is the unit segment direction', () {
      final path = PolylinePath([Vector3(0, 0, 0), Vector3(0, 3, 0)]);
      _expectVector(path.tangentAt(0.5), Vector3(0, 1, 0));
    });

    test('length sums the segments', () {
      final path = PolylinePath([
        Vector3(0, 0, 0),
        Vector3(1, 0, 0),
        Vector3(1, 4, 0),
      ]);
      expect(path.length, closeTo(5, 1e-6));
    });

    test('natural and arc-length parameters differ on uneven segments', () {
      // Segment lengths 1 and 4; the natural midpoint sits at the
      // corner, the arc-length midpoint sits partway along segment two.
      final path = PolylinePath([
        Vector3(0, 0, 0),
        Vector3(1, 0, 0),
        Vector3(1, 4, 0),
      ]);
      _expectVector(path.positionAt(0.5), Vector3(1, 0, 0));
      _expectVector(path.positionAtDistance(2.5), Vector3(1, 1.5, 0));
    });

    test('parameterAtDistance maps the endpoints and a knot', () {
      final path = PolylinePath([
        Vector3(0, 0, 0),
        Vector3(1, 0, 0),
        Vector3(1, 4, 0),
      ]);
      expect(path.parameterAtDistance(0), closeTo(0, 1e-6));
      expect(path.parameterAtDistance(5), closeTo(1, 1e-6));
      expect(path.parameterAtDistance(1), closeTo(0.5, 1e-6));
    });

    test('sample evenly spaced yields equal arc-length steps', () {
      final path = PolylinePath([Vector3(0, 0, 0), Vector3(4, 0, 0)]);
      final points = path.sample(5, evenlySpaced: true);
      expect(points, hasLength(5));
      for (var i = 0; i < points.length; i++) {
        _expectVector(points[i], Vector3(i.toDouble(), 0, 0));
      }
    });

    test('sample requires at least two points', () {
      final path = PolylinePath([Vector3(0, 0, 0), Vector3(1, 0, 0)]);
      expect(() => path.sample(1), throwsArgumentError);
    });
  });

  group('ScenePath frames', () {
    test('frameAt is orthonormal', () {
      final path = PolylinePath([
        Vector3(0, 0, 0),
        Vector3(2, 1, 0),
        Vector3(4, 0, 3),
      ]);
      for (final t in [0.0, 0.25, 0.5, 0.75, 1.0]) {
        final frame = path.frameAt(t);
        expect(frame.tangent.length, closeTo(1, 1e-5));
        expect(frame.normal.length, closeTo(1, 1e-5));
        expect(frame.binormal.length, closeTo(1, 1e-5));
        expect(frame.tangent.dot(frame.normal), closeTo(0, 1e-5));
        expect(frame.tangent.dot(frame.binormal), closeTo(0, 1e-5));
        expect(frame.normal.dot(frame.binormal), closeTo(0, 1e-5));
      }
    });

    test('a straight path keeps a constant frame', () {
      final path = PolylinePath([Vector3(0, 0, 0), Vector3(10, 0, 0)]);
      final start = path.frameAt(0);
      final end = path.frameAt(1);
      _expectVector(start.normal, end.normal, tol: 1e-5);
      _expectVector(start.binormal, end.binormal, tol: 1e-5);
    });

    test('frameAtDistance tracks the arc-length position', () {
      final path = PolylinePath([Vector3(0, 0, 0), Vector3(8, 0, 0)]);
      _expectVector(path.frameAtDistance(2).position, Vector3(2, 0, 0));
    });
  });

  group('CatmullRomPath', () {
    test('rejects fewer than two points', () {
      expect(() => CatmullRomPath([Vector3(0, 0, 0)]), throwsArgumentError);
    });

    test('passes through every control point', () {
      final points = [
        Vector3(0, 0, 0),
        Vector3(1, 2, 0),
        Vector3(3, 1, 1),
        Vector3(4, 0, 0),
      ];
      final path = CatmullRomPath(points);
      for (var i = 0; i < points.length; i++) {
        _expectVector(path.positionAt(i / (points.length - 1)), points[i]);
      }
    });

    test('an interior segment of collinear points stays straight', () {
      final path = CatmullRomPath([
        Vector3(0, 0, 0),
        Vector3(1, 0, 0),
        Vector3(2, 0, 0),
        Vector3(3, 0, 0),
      ]);
      // Midpoint of the segment between points 1 and 2.
      _expectVector(path.positionAt(0.5), Vector3(1.5, 0, 0));
    });

    test('length is at least the endpoint chord', () {
      final path = CatmullRomPath([
        Vector3(0, 0, 0),
        Vector3(2, 3, 0),
        Vector3(6, 0, 0),
      ]);
      expect(path.length, greaterThanOrEqualTo(6 - 1e-6));
    });
  });

  group('BezierPath', () {
    test('rejects a control point count that is not 3n + 1', () {
      expect(
        () => BezierPath([Vector3(0, 0, 0), Vector3(1, 0, 0)]),
        throwsArgumentError,
      );
      expect(
        () => BezierPath([
          Vector3(0, 0, 0),
          Vector3(1, 0, 0),
          Vector3(2, 0, 0),
          Vector3(3, 0, 0),
          Vector3(4, 0, 0),
        ]),
        throwsArgumentError,
      );
    });

    test('spans the first and last control points', () {
      final path = BezierPath([
        Vector3(0, 0, 0),
        Vector3(1, 2, 0),
        Vector3(3, 2, 0),
        Vector3(4, 0, 0),
      ]);
      _expectVector(path.positionAt(0), Vector3(0, 0, 0));
      _expectVector(path.positionAt(1), Vector3(4, 0, 0));
    });

    test('evenly spaced collinear controls trace the straight line', () {
      final path = BezierPath([
        Vector3(0, 0, 0),
        Vector3(1, 0, 0),
        Vector3(2, 0, 0),
        Vector3(3, 0, 0),
      ]);
      _expectVector(path.positionAt(0.5), Vector3(1.5, 0, 0));
      _expectVector(path.tangentAt(0.5), Vector3(1, 0, 0));
    });

    test('joins two segments through the shared control point', () {
      final path = BezierPath([
        Vector3(0, 0, 0),
        Vector3(1, 1, 0),
        Vector3(2, 1, 0),
        Vector3(3, 0, 0),
        Vector3(4, -1, 0),
        Vector3(5, -1, 0),
        Vector3(6, 0, 0),
      ]);
      _expectVector(path.positionAt(0.5), Vector3(3, 0, 0));
      _expectVector(path.positionAt(1), Vector3(6, 0, 0));
    });
  });
}
