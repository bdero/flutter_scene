import 'dart:math' as math;
import 'dart:typed_data';

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

  test('a flattened axis does not size billboards', () {
    expect(
      billboardSizeScale(Matrix4.diagonal3Values(2, 0, 3)),
      closeTo(2.0, 1e-6),
    );
    expect(
      billboardSizeScale(Matrix4.diagonal3Values(2, 0.001, 3)),
      closeTo(2.0, 1e-6),
    );
  });

  // One unit quad at the origin. Its world pad is half its summed width and
  // height (1), over each axis's scale in local space.
  Float32List quad() {
    final data = Float32List(BillboardGeometry.floatsPerInstance);
    data[3] = 1;
    data[4] = 1;
    return data;
  }

  test('bounds pad each axis to the drawn world size', () {
    final axes = Vector3(4, 1, 0.5);
    final bounds = billboardLocalBounds(quad(), 1, axes, 1.0)!;
    expect(bounds.max.x * axes.x, closeTo(1.0, 1e-6));
    expect(bounds.max.y * axes.y, closeTo(1.0, 1e-6));
    expect(bounds.max.z * axes.z, closeTo(1.0, 1e-6));
  });

  test('a shrunken node keeps world-unit bounds conservative', () {
    // Sizes in world units under a 0.05 scale: the local pad must grow so
    // the transformed box still holds the full-size quad.
    final axes = Vector3.all(0.05);
    final bounds = billboardLocalBounds(quad(), 1, axes, 1.0)!;
    expect(bounds.max.x * axes.x, closeTo(1.0, 1e-5));
  });

  test('a flattened axis still pads to the drawn size', () {
    final axes = Vector3(2, 0.001, 2);
    final scale = billboardSizeScale(Matrix4.diagonal3Values(2, 0.001, 2));
    final bounds = billboardLocalBounds(quad(), 1, axes, scale)!;
    expect(bounds.max.y * axes.y, closeTo(scale, 1e-5));
  });

  test('no instances leave the batch unbounded', () {
    expect(billboardLocalBounds(quad(), 0, Vector3.all(1), 1), isNull);
  });
}
