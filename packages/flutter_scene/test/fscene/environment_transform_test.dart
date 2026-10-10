import 'dart:math' as math;

// ignore: implementation_imports
import 'package:flutter_scene/src/fscene/realize/stage.dart'
    show environmentRotationYAndMirrorZ, environmentTransformFor;
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

void main() {
  test('a plain rotation leaves the transform proper and round-trips', () {
    final transform = environmentTransformFor(0.7);
    expect(transform.determinant(), closeTo(1.0, 1e-6));
    final (rotationY, mirrorZ) = environmentRotationYAndMirrorZ(transform);
    expect(rotationY, closeTo(0.7, 1e-6));
    expect(mirrorZ, isFalse);
  });

  test('the mirror reflects Z before the rotation', () {
    final transform = environmentTransformFor(0.0, mirrorZ: true);
    expect(transform.determinant(), closeTo(-1.0, 1e-6));
    final sampled = transform.transform(Vector3(0.3, 0.2, 1.0));
    expect(sampled.x, closeTo(0.3, 1e-6));
    expect(sampled.y, closeTo(0.2, 1e-6));
    expect(sampled.z, closeTo(-1.0, 1e-6));

    // Mirror then rotate: +Z reflects to -Z, which a quarter turn about Y
    // carries to -X.
    final rotated = environmentTransformFor(math.pi / 2, mirrorZ: true);
    final turned = rotated.transform(Vector3(0.0, 0.0, 1.0));
    expect(turned.x, closeTo(-1.0, 1e-6));
    expect(turned.z, closeTo(0.0, 1e-6));
  });

  test('a mirrored transform round-trips its rotation and flag', () {
    for (final angle in [-2.5, -0.4, 0.0, 1.1, 3.0]) {
      final transform = environmentTransformFor(angle, mirrorZ: true);
      final (rotationY, mirrorZ) = environmentRotationYAndMirrorZ(transform);
      expect(mirrorZ, isTrue, reason: 'angle $angle');
      expect(rotationY, closeTo(angle, 1e-6), reason: 'angle $angle');
    }
  });
}
