import 'package:flutter_scene/kit.dart';
import 'package:flutter_scene/src/camera.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' as vm;

void main() {
  group('BoundsFraming', () {
    test(
      'computes transform framing bounding box with margin and +Z forward',
      () {
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

        expect(camPos.length, greaterThan(15.0));

        // In flutter_scene, NodeCamera points along +Z; +Z should point towards bounds center (0, 0, 0)
        final forward = (xform * vm.Vector4(0, 0, 1, 0)).xyz;
        final toCenter = (bounds.center - camPos).normalized();
        expect(forward.dot(toCenter), closeTo(1.0, 0.001));
      },
    );
  });
}
