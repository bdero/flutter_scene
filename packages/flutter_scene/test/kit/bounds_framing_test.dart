import 'package:flutter_scene/kit.dart';
import 'package:flutter_scene/src/camera.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' as vm;

void main() {
  group('BoundsFraming', () {
    test('computes transform framing bounding box with margin', () {
      final bounds = vm.Aabb3.minMax(
        vm.Vector3(-5, -5, -5),
        vm.Vector3(5, 5, 5),
      );
      final camera = PerspectiveCamera(fovRadiansY: 1.0);

      final xform = BoundsFraming.computeFramingTransform(
        bounds,
        camera,
        paddingFactor: 1.2,
      );
      final camPos = (xform * vm.Vector4(0, 0, 0, 1)).xyz;

      // Camera should be positioned outside the bounds
      expect(camPos.length, greaterThan(15.0));
    });
  });
}
