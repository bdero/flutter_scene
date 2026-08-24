import 'package:flutter_scene/kit.dart';
import 'package:flutter_scene/scene.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' as vm;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ThirdPersonControllerComponent', () {
    test('accelerates when input is provided and stops on release', () {
      final node = Node()..position = vm.Vector3(0, 0, 0);
      final controller = ThirdPersonControllerComponent(walkSpeed: 5.0);
      node.addComponent(controller);

      // Provide forward input (Z+ in input space)
      controller.setMoveInput(vm.Vector2(0, 1));
      controller.update(0.1);

      expect(controller.velocity.z, greaterThan(0.0));

      // Clear input
      controller.setMoveInput(vm.Vector2.zero());
      for (var i = 0; i < 20; i++) {
        controller.update(0.1);
      }

      expect(controller.velocity.z, closeTo(0.0, 0.05));
    });

    test('jump applies vertical impulse', () {
      final node = Node()..position = vm.Vector3(0, 0, 0);
      final controller = ThirdPersonControllerComponent(jumpVelocity: 6.0);
      node.addComponent(controller);

      controller.update(0.016); // Detect ground
      expect(controller.isGrounded, isTrue);

      controller.jump();
      controller.update(0.016);

      expect(controller.velocity.y, greaterThan(4.0));
      expect(controller.isGrounded, isFalse);
    });
  });
}
