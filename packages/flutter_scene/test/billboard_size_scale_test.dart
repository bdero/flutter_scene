import 'dart:math' as math;

// ignore: implementation_imports
import 'package:flutter_scene/src/geometry/billboard_geometry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

void main() {
  test('billboard sizes take a uniform node scale', () {
    expect(billboardSizeScale(Matrix4.identity()), closeTo(1.0, 1e-6));
    expect(
      billboardSizeScale(Matrix4.diagonal3Values(4, 4, 4)),
      closeTo(4.0, 1e-6),
    );
    expect(
      billboardSizeScale(Matrix4.diagonal3Values(0.25, 0.25, 0.25)),
      closeTo(0.25, 1e-6),
    );
  });

  test('rotation and translation do not change billboard sizes', () {
    final m = Matrix4.compose(
      Vector3(10, -3, 7),
      Quaternion.axisAngle(Vector3(1, 2, 3).normalized(), 1.1),
      Vector3.all(2),
    );
    expect(billboardSizeScale(m), closeTo(2.0, 1e-5));
  });

  test('a non-uniform scale sizes billboards by its smallest axis', () {
    final m = Matrix4.compose(
      Vector3.zero(),
      Quaternion.axisAngle(Vector3(0, 1, 0), math.pi / 3),
      Vector3(4, 1, 2),
    );
    expect(billboardSizeScale(m), closeTo(1.0, 1e-5));
  });
}
