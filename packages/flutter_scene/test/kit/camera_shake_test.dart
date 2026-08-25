import 'package:flutter_scene/kit.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CameraShake', () {
    test('trauma decays linearly over time', () {
      final shake = CameraShake(decayRate: 1.0);
      shake.addTrauma(0.8);

      expect(shake.trauma, equals(0.8));

      final offset = shake.update(0.5);
      expect(shake.trauma, closeTo(0.3, 0.001));
      expect(offset.translation.length2, greaterThan(0.0));

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

    test('CameraShakeOffset.zero returns independent unshared instances', () {
      final z1 = CameraShakeOffset.zero;
      final z2 = CameraShakeOffset.zero;

      z1.translation.x = 99.0;
      expect(z2.translation.x, equals(0.0));
    });
  });
}
