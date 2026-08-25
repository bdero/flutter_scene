import 'package:flutter_scene/kit.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' as vm;

void main() {
  group('WaterSurfaceComponent', () {
    test('evaluates wave displacement and normal across time', () {
      final water = WaterSurfaceComponent(
        waves: [
          GerstnerWave(
            direction: vm.Vector2(1.0, 0.0),
            amplitude: 0.5,
            wavelength: 10.0,
            speed: 1.0,
            steepness: 0.8,
          ),
        ],
      );

      final eval0 = water.evaluateAt(vm.Vector2(0, 0), 0.0);
      expect(eval0.displacement.y, closeTo(0.0, 0.001));
      expect(eval0.normal.y, greaterThan(0.5));

      // Advance time to a quarter cycle (peak crest: k = 2pi/10, k*x = 2pi*2.5/10 = pi/2 -> sin(pi/2)=1 -> y=0.5)
      final evalPeak = water.evaluateAt(vm.Vector2(2.5, 0), 0.0);
      expect(evalPeak.displacement.y, closeTo(0.5, 0.05));
    });
  });
}
