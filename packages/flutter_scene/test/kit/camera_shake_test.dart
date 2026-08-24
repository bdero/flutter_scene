import 'package:flutter_scene/kit.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CameraShake', () {
    test('trauma decays linearly over time', () {
      final shake = CameraShake(decayRate: 1.0);
      shake.addTrauma(0.8);

      expect(shake.trauma, equals(0.8));

      // Advance 0.5s
      final offset = shake.update(0.5);
      expect(shake.trauma, closeTo(0.3, 0.001));
      expect(offset.translation.length2, greaterThan(0.0));

      // Advance 0.5s -> should reach 0.0
      shake.update(0.5);
      expect(shake.trauma, equals(0.0));

      final zeroOffset = shake.update(0.1);
      expect(
        zeroOffset.translation,
        equals(CameraShakeOffset.zero.translation),
      );
    });

    test('addTrauma clamps at 1.0', () {
      final shake = CameraShake();
      shake.addTrauma(1.5);
      expect(shake.trauma, equals(1.0));
    });
  });
}
