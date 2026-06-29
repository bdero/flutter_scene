import 'package:flutter_scene/src/fscene/property_value.dart';
import 'package:flutter_scene/src/fscene/realize/particle_property_values.dart';
import 'package:flutter_scene/src/particles/distribution.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

void main() {
  group('ParticleCurve round-trip', () {
    test('preserves keyframes', () {
      final curve = ParticleCurve([
        const ParticleKeyframe(0.0, 0.2),
        const ParticleKeyframe(0.5, 1.0),
        const ParticleKeyframe(1.0, 0.0),
      ]);
      final decoded = decodeParticleCurve(encodeParticleCurve(curve));
      expect(decoded.keyframes.length, 3);
      for (var i = 0; i < curve.keyframes.length; i++) {
        expect(decoded.keyframes[i].t, closeTo(curve.keyframes[i].t, 1e-9));
        expect(
          decoded.keyframes[i].value,
          closeTo(curve.keyframes[i].value, 1e-9),
        );
      }
    });

    test('absent keys decode to a constant-zero curve', () {
      final decoded = decodeParticleCurve(MapValue({}));
      expect(decoded.sample(0.0), 0.0);
      expect(decoded.sample(1.0), 0.0);
    });
  });

  group('ColorGradient round-trip', () {
    test('preserves stops and colors', () {
      final gradient = ColorGradient([
        ColorStop(0.0, Vector4(1, 0.5, 0, 1)),
        ColorStop(1.0, Vector4(0, 0, 0, 0)),
      ]);
      final decoded = decodeColorGradient(encodeColorGradient(gradient));
      expect(decoded.stops.length, 2);
      expect(decoded.stops[0].t, closeTo(0.0, 1e-9));
      expect(decoded.stops[0].color.x, closeTo(1.0, 1e-9));
      expect(decoded.stops[0].color.y, closeTo(0.5, 1e-9));
      expect(decoded.stops[1].color.w, closeTo(0.0, 1e-9));
    });
  });

  group('FloatDistribution round-trip', () {
    test('constant', () {
      final d = decodeFloatDistribution(
        encodeFloatDistribution(const ConstantFloat(3.5)),
      );
      expect(d, isA<ConstantFloat>());
      expect((d as ConstantFloat).value, 3.5);
    });

    test('uniform', () {
      final d = decodeFloatDistribution(
        encodeFloatDistribution(const UniformFloat(1.0, 4.0)),
      );
      expect(d, isA<UniformFloat>());
      expect((d as UniformFloat).min, 1.0);
      expect(d.max, 4.0);
    });

    test('curve preserves the curve and scale', () {
      final source = CurveFloat(
        ParticleCurve.linear(from: 0, to: 1),
        scale: 2.5,
      );
      final d = decodeFloatDistribution(encodeFloatDistribution(source));
      expect(d, isA<CurveFloat>());
      final cf = d as CurveFloat;
      expect(cf.scale, 2.5);
      expect(cf.sample(1.0, 0.0), closeTo(2.5, 1e-3));
    });

    test('uniformCurve', () {
      final source = UniformCurveFloat(
        ParticleCurve.constant(0.0),
        ParticleCurve.constant(10.0),
      );
      final d = decodeFloatDistribution(encodeFloatDistribution(source));
      expect(d, isA<UniformCurveFloat>());
      expect(d.sample(0.5, 0.5), closeTo(5.0, 1e-3));
    });

    test('absent value decodes to the fallback constant', () {
      final d = decodeFloatDistribution(null, fallback: 7.0);
      expect(d, isA<ConstantFloat>());
      expect((d as ConstantFloat).value, 7.0);
    });
  });
}
