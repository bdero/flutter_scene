import 'package:flutter_scene/kit.dart';
import 'package:flutter_scene/scene.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' as vm;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SpringArmComponent', () {
    test('computes unoccluded socket transform at target length', () {
      final node = Node()..position = vm.Vector3(10, 0, 10);
      final arm = SpringArmComponent(
        targetLength: 5.0,
        targetOffset: vm.Vector3(0, 2, 0),
        socketOffset: vm.Vector3(1, 0, 0),
      );
      node.addComponent(arm);
      arm.onMount();

      final xform = arm.socketTransform;
      final pos = (xform * vm.Vector4(0, 0, 0, 1)).xyz;

      // Expected: origin (10, 0, 10) + targetOffset (0, 2, 0) + back (0, 0, 5) + socketOffset (1, 0, 0)
      // -> (11, 2, 15)
      expect(pos.x, closeTo(11.0, 0.001));
      expect(pos.y, closeTo(2.0, 0.001));
      expect(pos.z, closeTo(15.0, 0.001));
    });

    test('updates position lag smoothly towards target', () {
      final node = Node()..position = vm.Vector3.zero();
      final arm = SpringArmComponent(
        targetLength: 4.0,
        enablePositionLag: true,
        positionLagSpeed: 5.0,
      );
      node.addComponent(arm);
      arm.onMount();

      // Move parent node instantly
      node.position = vm.Vector3(100, 0, 0);

      // Tick 0.1s
      arm.update(0.1);

      final xform = arm.socketTransform;
      final pos = (xform * vm.Vector4(0, 0, 0, 1)).xyz;

      // Should be smoothly intermediate between 0 and 100 on X
      expect(pos.x, greaterThan(10.0));
      expect(pos.x, lessThan(90.0));
    });
  });
}
