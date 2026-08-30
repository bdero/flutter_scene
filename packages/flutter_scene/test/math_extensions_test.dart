// QuaternionSlerp tests. Guards the double-cover fix: q and -q are the
// same rotation, so slerp must negate the target on a negative dot product
// and take the short arc, without collapsing near-antipodal inputs to zero.

import 'dart:math';

import 'package:flutter_scene/src/math_extensions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

const double _degrees = pi / 180.0;

/// Rotation of [deg] degrees about +Z.
Quaternion _rotZ(double deg) =>
    Quaternion.axisAngle(Vector3(0, 0, 1), deg * _degrees);

/// Magnitude in degrees of the +X axis rotation applied by [q], measured
/// in the XY plane. Lets a Z-rotation be checked as a single scalar.
double _probeAngle(Quaternion q) {
  final v = q.rotateVector(Vector3(1, 0, 0));
  return atan2(v.y, v.x).abs() / _degrees;
}

/// True when [a] and [b] describe the same rotation, allowing the sign
/// ambiguity of the double cover.
bool _sameRotation(Quaternion a, Quaternion b) => a.dot(b).abs() > 1 - 1e-6;

void main() {
  group('QuaternionSlerp.slerp', () {
    test('sign-flipped inputs take the short arc', () {
      final a = _rotZ(10);
      // Same rotation as _rotZ(31), but the exporter-style negated form so
      // dot(a, b) < 0. The midpoint must land at 20.5 degrees (short arc),
      // not ~200 degrees the long way round.
      final b = _rotZ(31).scaled(-1.0);
      expect(a.dot(b), lessThan(0));

      final mid = a.slerp(b, 0.5);
      expect(_probeAngle(mid), closeTo(20.5, 1e-3));
    });

    test('matches the non-flipped arc it is equivalent to', () {
      final a = _rotZ(10);
      final b = _rotZ(31);
      final flipped = a.slerp(b.scaled(-1.0), 0.5);
      final plain = a.slerp(b, 0.5);
      expect(_sameRotation(flipped, plain), isTrue);
      expect(_probeAngle(flipped), closeTo(_probeAngle(plain), 1e-3));
    });

    test('weight 0 and 1 return the endpoint rotations', () {
      final a = _rotZ(10);
      final b = _rotZ(31).scaled(-1.0);
      expect(_sameRotation(a.slerp(b, 0.0), a), isTrue);
      // At weight 1 the result is the same rotation as b even though it may
      // come back as the negated (short-arc) form.
      expect(_sameRotation(a.slerp(b, 1.0), b), isTrue);
    });

    test('exactly antipodal inputs stay normalized', () {
      final a = _rotZ(37);
      final antipode = a.scaled(-1.0); // dot == -1, the zero-sum trap
      final result = a.slerp(antipode, 0.5);
      expect(result.length, closeTo(1.0, 1e-6));
      expect(result.x.isNaN, isFalse);
      expect(_sameRotation(result, a), isTrue);
    });

    test('non-flipped short arc is unchanged', () {
      final a = _rotZ(10);
      final b = _rotZ(31);
      expect(_probeAngle(a.slerp(b, 0.5)), closeTo(20.5, 1e-3));
      expect(_sameRotation(a.slerp(b, 1.0), b), isTrue);
    });
  });

  group('QuaternionRotate', () {
    test('agrees with the matrix the same quaternion composes', () {
      // The whole reason this helper exists. Node transforms, camera poses and
      // animation output all go through Matrix4.compose, so a rotation helper
      // that disagreed with it would be wrong everywhere it was used -- and
      // wrong only for compound rotations, which is the worst way to be wrong.
      final rotations = [
        Quaternion.identity(),
        Quaternion.axisAngle(Vector3(0, 1, 0), pi / 2),
        Quaternion.axisAngle(Vector3(1, 0, 0), 0.7),
        Quaternion.axisAngle(Vector3(0, 1, 0), 1.1) *
            Quaternion.axisAngle(Vector3(1, 0, 0), -0.4),
        Quaternion.axisAngle(Vector3(1, 2, 3).normalized(), 2.2),
      ];
      final vectors = [
        Vector3(1, 0, 0),
        Vector3(0, 0, 1),
        Vector3(0, 0, -5),
        Vector3(3, -2, 1.5),
      ];
      for (final q in rotations) {
        final matrix = Matrix4.compose(
          Vector3.zero(),
          q,
          Vector3(1, 1, 1),
        ).getRotation();
        for (final v in vectors) {
          final expected = matrix * v.clone();
          final actual = q.rotateVector(v);
          expect(
            (actual - expected).length,
            lessThan(1e-5),
            reason: 'rotating $v by $q',
          );
        }
      }
    });

    test('vector_math rotated is the inverse, which is the trap', () {
      // Pinned so the difference stays visible: a future reader who swaps the
      // helper back for Quaternion.rotated should fail here rather than in a
      // camera pointing quietly backwards.
      final q = Quaternion.axisAngle(Vector3(0, 1, 0), pi / 4);
      final v = Vector3(0, 0, 1);
      expect(q.rotateVector(v).x, closeTo(0.7071, 1e-3));
      expect(q.rotated(v.clone()).x, closeTo(-0.7071, 1e-3));
    });

    test('the into form writes the same answer and allocates nothing', () {
      final q = Quaternion.axisAngle(Vector3(0, 1, 0), 1.3);
      final v = Vector3(2, -1, 4);
      final out = Vector3.zero();
      q.rotateVectorInto(v, out);
      expect((out - q.rotateVector(v)).length, lessThan(1e-9));
    });

    test('writing into the source vector works', () {
      // Callers reuse one scratch vector for both sides; aliasing has to be
      // safe or the second component reads a value the first already replaced.
      final q = Quaternion.axisAngle(Vector3(0, 1, 0), 0.9);
      final v = Vector3(1, 2, 3);
      final expected = q.rotateVector(v);
      q.rotateVectorInto(v, v);
      expect((v - expected).length, lessThan(1e-9));
    });

    test('a unit rotation preserves length', () {
      final q = Quaternion.axisAngle(Vector3(1, 1, 0).normalized(), 2.0);
      expect(q.rotateVector(Vector3(0, 0, 7)).length, closeTo(7, 1e-6));
    });
  });
}
