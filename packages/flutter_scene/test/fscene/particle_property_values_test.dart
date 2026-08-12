import 'package:scene/scene.dart';
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

  group('ColorDistribution round-trip', () {
    test('constant', () {
      final d = decodeColorDistribution(
        encodeColorDistribution(ConstantColor(Vector4(0.25, 0.5, 0.75, 1))),
      );
      expect(d, isA<ConstantColor>());
      final color = (d as ConstantColor).color;
      expect(color.x, closeTo(0.25, 1e-6));
      expect(color.z, closeTo(0.75, 1e-6));
    });

    test('gradient preserves stops', () {
      final d = decodeColorDistribution(
        encodeColorDistribution(
          GradientColor(
            ColorGradient([
              ColorStop(0.0, Vector4(1, 0, 0, 1)),
              ColorStop(1.0, Vector4(0, 1, 0, 0)),
            ]),
          ),
        ),
      );
      expect(d, isA<GradientColor>());
      final stops = (d as GradientColor).gradient.stops;
      expect(stops.length, 2);
      expect(stops[0].color.x, closeTo(1.0, 1e-6));
      expect(stops[1].color.y, closeTo(1.0, 1e-6));
    });

    test('uniform', () {
      final d = decodeColorDistribution(
        encodeColorDistribution(
          UniformColor(Vector4(1, 0, 0, 1), Vector4(0, 0, 1, 1)),
        ),
      );
      expect(d, isA<UniformColor>());
      final uniform = d as UniformColor;
      expect(uniform.a.x, closeTo(1.0, 1e-6));
      expect(uniform.b.z, closeTo(1.0, 1e-6));
    });

    test('absent value decodes to the fallback constant', () {
      final d = decodeColorDistribution(null, fallback: Vector4(0, 0, 0, 1));
      expect(d, isA<ConstantColor>());
      expect((d as ConstantColor).color.x, closeTo(0.0, 1e-6));
      expect(d.color.w, closeTo(1.0, 1e-6));
    });
  });
}
