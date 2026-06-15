import 'package:flutter_scene_editor/src/inspector/euler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

void _expectQuatClose(Quaternion a, Quaternion b, {double eps = 1e-4}) {
  final an = a.normalized();
  final bn = b.normalized();
  // q and -q are the same rotation; compare with sign alignment.
  final dot = an.x * bn.x + an.y * bn.y + an.z * bn.z + an.w * bn.w;
  final s = dot < 0 ? -1.0 : 1.0;
  expect(an.x, closeTo(s * bn.x, eps));
  expect(an.y, closeTo(s * bn.y, eps));
  expect(an.z, closeTo(s * bn.z, eps));
  expect(an.w, closeTo(s * bn.w, eps));
}

void main() {
  test('euler degrees round-trip through a quaternion', () {
    for (final e in [
      Vector3(0, 0, 0),
      Vector3(30, 0, 0),
      Vector3(0, 45, 0),
      Vector3(0, 0, 90),
      Vector3(20, 35, 50),
      Vector3(-15, 60, -120),
    ]) {
      final q = eulerXyzDegreesToQuaternion(e);
      final back = quaternionToEulerXyzDegrees(q);
      // Compare via the quaternion (Euler triples are not unique).
      _expectQuatClose(q, eulerXyzDegreesToQuaternion(back));
    }
  });

  test('identity is zero degrees', () {
    final e = quaternionToEulerXyzDegrees(Quaternion.identity());
    expect(e.x, closeTo(0, 1e-4));
    expect(e.y, closeTo(0, 1e-4));
    expect(e.z, closeTo(0, 1e-4));
  });
}
