import 'package:flutter_scene/src/particles/distribution.dart';
import 'package:flutter_scene/src/particles/particle_module.dart';
import 'package:flutter_scene/src/particles/particle_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

// A storage with [count] live particles, each with unit lifetime.
ParticleStorage _live(int count) {
  final s = ParticleStorage(count);
  for (var i = 0; i < count; i++) {
    s.spawn();
    s.lifetime[i] = 1.0;
  }
  return s;
}

void main() {
  test('AccelerationModule adds acceleration * dt to velocity', () {
    final s = _live(1);
    s.velY[0] = 5.0;
    AccelerationModule(Vector3(0, -10, 0)).update(s, 0.1);
    expect(s.velY[0], closeTo(4.0, 1e-9));
  });

  group('LinearDragModule', () {
    test('scales velocity by 1 - k*dt', () {
      final s = _live(1);
      s.velX[0] = 8.0;
      LinearDragModule(1.0).update(s, 0.5); // factor 0.5
      expect(s.velX[0], closeTo(4.0, 1e-9));
    });

    test('clamps the factor at zero for strong drag', () {
      final s = _live(1);
      s.velX[0] = 8.0;
      LinearDragModule(10.0).update(s, 1.0); // 1 - 10 -> clamp 0
      expect(s.velX[0], 0.0);
    });
  });

  test('SizeOverLifeModule scales baseSize by the curve over age', () {
    final s = _live(1);
    s.baseSize[0] = 2.0;
    s.age[0] = 0.5; // lifetime 1 -> normalized 0.5
    final module = SizeOverLifeModule(
      CurveFloat(ParticleCurve.linear(from: 0, to: 1)),
    );
    module.update(s, 0.016);
    expect(s.size[0], closeTo(1.0, 1e-2)); // 2 * 0.5
  });

  test('ColorOverLifeModule sets color from the gradient over age', () {
    final s = _live(1);
    s.age[0] = 1.0; // normalized 1.0 -> end of gradient
    final module = ColorOverLifeModule(
      GradientColor(
        ColorGradient([
          ColorStop(0.0, Vector4(0, 0, 0, 1)),
          ColorStop(1.0, Vector4(1, 1, 1, 1)),
        ]),
      ),
    );
    module.update(s, 0.016);
    expect(s.colorR[0], closeTo(1.0, 1e-6));
    expect(s.colorG[0], closeTo(1.0, 1e-6));
    expect(s.colorB[0], closeTo(1.0, 1e-6));
  });

  test('RotationModule integrates rotation from angular velocity', () {
    final s = _live(1);
    s.angularVelocity[0] = 2.0;
    const module = RotationModule();
    module.update(s, 0.5);
    expect(s.rotation[0], closeTo(1.0, 1e-9));
  });
}
