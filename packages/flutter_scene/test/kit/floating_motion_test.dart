import 'package:flutter_scene/kit.dart';
import 'package:flutter_scene/scene.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' as vm;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('FloatingMotionComponent', () {
    test('oscillates position and rotates over time', () {
      final node = Node()..position = vm.Vector3(0, 10, 0);
      final motion = FloatingMotionComponent(
        hoverAmplitude: 1.0,
        hoverFrequency: 1.0,
        spinSpeed: 2.0,
      );
      node.addComponent(motion);
      motion.onMount();

      expect(node.position.y, equals(10.0));

      // Quarter cycle (t = 0.25s at 1Hz -> sin(pi/2) = 1.0 -> y = 11.0)
      motion.update(0.25);
      expect(node.position.y, closeTo(11.0, 0.05));

      // Three quarters cycle (t = 0.5s more -> t = 0.75s -> sin(3pi/2) = -1.0 -> y = 9.0)
      motion.update(0.5);
      expect(node.position.y, closeTo(9.0, 0.05));
    });
  });
}
