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

  group('FlipbookModule', () {
    test('plays once over life when framesPerSecond is unset', () {
      final s = _live(1);
      s.age[0] = 0.5; // normalized 0.5 of 64 frames -> 32
      const FlipbookModule(frameCount: 64).update(s, 0.016);
      expect(s.frame[0], closeTo(32.0, 1e-6));
    });

    test('holds the last cell at end of life instead of wrapping', () {
      final s = _live(1);
      s.age[0] = 1.0;
      const FlipbookModule(frameCount: 64).update(s, 0.016);
      expect(s.frame[0], closeTo(63.0, 1e-6));
    });

    test('advances at a fixed rate and wraps when framesPerSecond is set', () {
      final s = _live(1);
      s.age[0] = 2.25; // 2.25 s * 8 fps = 18 -> wraps to 2 in a 16-cell atlas
      const FlipbookModule(frameCount: 16, framesPerSecond: 8).update(s, 0.016);
      expect(s.frame[0], closeTo(2.0, 1e-4));
    });

    test('random start offsets are stable per particle', () {
      final s = _live(2);
      s.random01[0] = 0.25;
      s.random01[1] = 0.75;
      const module = FlipbookModule(
        frameCount: 16,
        framesPerSecond: 8,
        randomStartFrame: true,
      );
      module.update(s, 0.016);
      final first = (s.frame[0], s.frame[1]);
      module.update(s, 0.016); // age unchanged -> same frames
      expect(s.frame[0], first.$1);
      expect(s.frame[1], first.$2);
      expect(s.frame[0], isNot(equals(s.frame[1])));
    });
  });

  group('TurbulenceModule', () {
    test('adds a deterministic divergence-free kick to velocity', () {
      final a = _live(1);
      a.posX[0] = 0.3;
      a.posY[0] = 0.7;
      a.posZ[0] = -0.2;
      final b = _live(1);
      b.posX[0] = 0.3;
      b.posY[0] = 0.7;
      b.posZ[0] = -0.2;
      TurbulenceModule(strength: 2.0).update(a, 0.5);
      TurbulenceModule(strength: 2.0).update(b, 0.5);
      final speedSq =
          a.velX[0] * a.velX[0] + a.velY[0] * a.velY[0] + a.velZ[0] * a.velZ[0];
      expect(speedSq, greaterThan(0.0));
      expect(a.velX[0], b.velX[0]);
      expect(a.velY[0], b.velY[0]);
      expect(a.velZ[0], b.velZ[0]);
    });

    test('scroll drifts the field over time', () {
      final s = _live(1);
      final still = TurbulenceModule();
      final scrolled = TurbulenceModule(scroll: Vector3(0, 3, 0));
      still.update(s, 0.25);
      final stillKick = (s.velX[0], s.velY[0], s.velZ[0]);
      s.velX[0] = 0;
      s.velY[0] = 0;
      s.velZ[0] = 0;
      scrolled.update(s, 0.25);
      final scrolledKick = (s.velX[0], s.velY[0], s.velZ[0]);
      expect(scrolledKick, isNot(equals(stillKick)));
    });
  });

  test('RotationModule integrates rotation from angular velocity', () {
    final s = _live(1);
    s.angularVelocity[0] = 2.0;
    const module = RotationModule();
    module.update(s, 0.5);
    expect(s.rotation[0], closeTo(1.0, 1e-9));
  });
}
