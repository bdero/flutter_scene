import 'package:flutter_scene/kit.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DayNightCycleComponent', () {
    test('sun direction at noon points high in the sky', () {
      final cycle = DayNightCycleComponent(timeOfDay: 12.0);
      final dir = cycle.sunDirection;

      expect(dir.y, greaterThan(0.7));
    });

    test('sun direction at midnight points downward', () {
      final cycle = DayNightCycleComponent(timeOfDay: 0.0);
      final dir = cycle.sunDirection;

      expect(dir.y, lessThan(-0.7));
    });

    test('evaluates daytime vs night lighting', () {
      final dayCycle = DayNightCycleComponent(timeOfDay: 12.0);
      final dayLighting = dayCycle.evaluateLighting();
      expect(dayLighting.sunIntensity, greaterThan(50000.0));

      final nightCycle = DayNightCycleComponent(timeOfDay: 0.0);
      final nightLighting = nightCycle.evaluateLighting();
      expect(nightLighting.sunIntensity, lessThan(1000.0));
    });
  });
}
