import 'package:flutter_scene/src/particles/distribution.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

void main() {
  group('ParticleCurve', () {
    test('constant samples its value everywhere and clamps t', () {
      final curve = ParticleCurve.constant(3.5);
      expect(curve.sample(0.0), 3.5);
      expect(curve.sample(0.5), 3.5);
      expect(curve.sample(1.0), 3.5);
      expect(curve.sample(-2.0), 3.5);
      expect(curve.sample(2.0), 3.5);
    });

    test('linear ramps from->to across [0,1]', () {
      final curve = ParticleCurve.linear(from: 2.0, to: 4.0);
      expect(curve.sample(0.0), closeTo(2.0, 1e-6));
      expect(curve.sample(0.5), closeTo(3.0, 1e-3));
      expect(curve.sample(1.0), closeTo(4.0, 1e-6));
    });

    test('clamps to end values outside the keyframe range', () {
      final curve = ParticleCurve([
        const ParticleKeyframe(0.25, 10.0),
        const ParticleKeyframe(0.75, 20.0),
      ]);
      expect(curve.sample(0.0), closeTo(10.0, 1e-6));
      expect(curve.sample(0.25), closeTo(10.0, 0.2));
      expect(curve.sample(0.5), closeTo(15.0, 0.3));
      expect(curve.sample(0.75), closeTo(20.0, 0.2));
      expect(curve.sample(1.0), closeTo(20.0, 1e-6));
    });

    test('unsorted keyframes are handled', () {
      final curve = ParticleCurve([
        const ParticleKeyframe(1.0, 100.0),
        const ParticleKeyframe(0.0, 0.0),
      ]);
      expect(curve.sample(0.0), closeTo(0.0, 1e-6));
      expect(curve.sample(1.0), closeTo(100.0, 1e-6));
      expect(curve.sample(0.5), closeTo(50.0, 1.0));
    });

    test('empty keyframes are constant zero', () {
      final curve = ParticleCurve(const []);
      expect(curve.sample(0.0), 0.0);
      expect(curve.sample(1.0), 0.0);
    });
  });

  group('ColorGradient', () {
    test('constant returns its color everywhere', () {
      final g = ColorGradient.constant(Vector4(0.2, 0.4, 0.6, 0.8));
      final c = g.sample(0.5);
      expect(c.x, closeTo(0.2, 1e-6));
      expect(c.y, closeTo(0.4, 1e-6));
      expect(c.z, closeTo(0.6, 1e-6));
      expect(c.w, closeTo(0.8, 1e-6));
    });

    test('lerps between stops and clamps', () {
      final g = ColorGradient([
        ColorStop(0.0, Vector4(0, 0, 0, 1)),
        ColorStop(1.0, Vector4(1, 1, 1, 0)),
      ]);
      final mid = g.sample(0.5);
      expect(mid.x, closeTo(0.5, 0.02));
      expect(mid.w, closeTo(0.5, 0.02));
      final before = g.sample(-1.0);
      expect(before.x, closeTo(0.0, 1e-6));
      expect(before.w, closeTo(1.0, 1e-6));
    });

    test('reuses the out vector when provided', () {
      final g = ColorGradient.constant(Vector4(1, 0, 0, 1));
      final out = Vector4.zero();
      final result = g.sample(0.3, out);
      expect(identical(result, out), isTrue);
      expect(out.x, closeTo(1.0, 1e-6));
    });
  });

  group('FloatDistribution', () {
    test('ConstantFloat ignores age and random', () {
      const d = ConstantFloat(7.0);
      expect(d.sample(0.0, 0.0), 7.0);
      expect(d.sample(1.0, 0.9), 7.0);
    });

    test('UniformFloat maps random across [min, max]', () {
      const d = UniformFloat(10.0, 20.0);
      expect(d.sample(0.5, 0.0), closeTo(10.0, 1e-6));
      expect(d.sample(0.5, 0.5), closeTo(15.0, 1e-6));
      expect(d.sample(0.5, 1.0), closeTo(20.0, 1e-6));
    });

    test('CurveFloat samples the curve over age and scales', () {
      final d = CurveFloat(ParticleCurve.linear(from: 0, to: 1), scale: 4.0);
      expect(d.sample(0.0, 0.3), closeTo(0.0, 1e-6));
      expect(d.sample(1.0, 0.3), closeTo(4.0, 1e-6));
    });

    test('UniformCurveFloat blends two curves by random', () {
      final d = UniformCurveFloat(
        ParticleCurve.constant(0.0),
        ParticleCurve.constant(10.0),
      );
      expect(d.sample(0.5, 0.0), closeTo(0.0, 1e-6));
      expect(d.sample(0.5, 0.25), closeTo(2.5, 1e-6));
      expect(d.sample(0.5, 1.0), closeTo(10.0, 1e-6));
    });
  });

  group('ColorDistribution', () {
    test('ConstantColor returns its color', () {
      final d = ConstantColor(Vector4(0.1, 0.2, 0.3, 1.0));
      final c = d.sample(0.5, 0.5);
      expect(c.x, closeTo(0.1, 1e-6));
      expect(c.z, closeTo(0.3, 1e-6));
    });

    test('GradientColor samples over age', () {
      final d = GradientColor(
        ColorGradient([
          ColorStop(0.0, Vector4(0, 0, 0, 1)),
          ColorStop(1.0, Vector4(1, 1, 1, 1)),
        ]),
      );
      expect(d.sample(0.0, 0.0).x, closeTo(0.0, 1e-6));
      expect(d.sample(1.0, 0.0).x, closeTo(1.0, 1e-6));
    });

    test('UniformColor blends two colors by random', () {
      final d = UniformColor(Vector4(0, 0, 0, 0), Vector4(1, 2, 3, 4));
      final mid = d.sample(0.5, 0.5);
      expect(mid.x, closeTo(0.5, 1e-6));
      expect(mid.y, closeTo(1.0, 1e-6));
      expect(mid.w, closeTo(2.0, 1e-6));
    });
  });
}
