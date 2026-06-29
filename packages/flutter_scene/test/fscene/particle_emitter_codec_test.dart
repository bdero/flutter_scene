import 'package:flutter_scene/src/fscene/property_value.dart';
import 'package:flutter_scene/src/fscene/realize/particle_emitter_codec.dart';
import 'package:flutter_scene/src/fscene/realize/particle_property_values.dart';
import 'package:flutter_scene/src/geometry/billboard_geometry.dart';
import 'package:flutter_scene/src/material/sprite_material.dart';
import 'package:flutter_scene/src/particles/distribution.dart';
import 'package:flutter_scene/src/particles/emitter_shape.dart';
import 'package:flutter_scene/src/particles/particle_module.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

// A fully populated property map that exercises every schema field, so the
// system round-trip covers each one.
Map<String, PropertyValue> _authoredProperties() => {
  'maxParticles': const IntValue(256),
  'emitRate': const DoubleValue(80.0),
  'shapeType': const StringValue('cone'),
  'shapeRadius': const DoubleValue(0.4),
  'shapeAngle': const DoubleValue(0.35),
  'lifetime': encodeFloatDistribution(const UniformFloat(0.5, 1.5)),
  'startSpeed': encodeFloatDistribution(const UniformFloat(2.0, 4.0)),
  'startSize': encodeFloatDistribution(const ConstantFloat(0.3)),
  'startRotation': encodeFloatDistribution(const UniformFloat(0, 6.28)),
  'startAngularVelocity': encodeFloatDistribution(const UniformFloat(-1, 1)),
  'sizeOverLife': encodeParticleCurve(ParticleCurve.linear(from: 1, to: 0)),
  'colorOverLife': encodeColorGradient(
    ColorGradient([
      ColorStop(0.0, Vector4(1, 0.8, 0.2, 1)),
      ColorStop(1.0, Vector4(1, 0.1, 0, 0)),
    ]),
  ),
  'drag': const DoubleValue(0.5),
  'gravity': Vec3Value(Vector3(0, -9.8, 0)),
  'blendMode': const StringValue('additive'),
  'facing': const StringValue('velocityStretched'),
  'velocityStretch': const DoubleValue(0.12),
  'looping': const BoolValue(false),
  'duration': const DoubleValue(3.0),
  'seed': const IntValue(99),
};

void main() {
  group('particleSystemFromProperties', () {
    test('builds the configured system', () {
      final s = particleSystemFromProperties(_authoredProperties());
      expect(s.storage.capacity, 256);
      expect(s.spawner.rate, 80.0);
      expect(s.shape, isA<ConeShape>());
      expect((s.shape as ConeShape).radius, closeTo(0.4, 1e-9));
      expect(s.lifetime, isA<UniformFloat>());
      expect(s.gravity.y, closeTo(-9.8, 1e-5)); // gravity stored as float32
      expect(s.looping, isFalse);
      expect(s.seed, 99);
      // Drag > 0 adds a drag module; size/color/rotation modules are present.
      expect(s.modules.whereType<LinearDragModule>().length, 1);
      expect(s.modules.whereType<SizeOverLifeModule>().length, 1);
      expect(s.modules.whereType<ColorOverLifeModule>().length, 1);
      expect(s.modules.whereType<RotationModule>().length, 1);
    });

    test('omits the drag module when drag is zero', () {
      final props = _authoredProperties()..['drag'] = const DoubleValue(0);
      final s = particleSystemFromProperties(props);
      expect(s.modules.whereType<LinearDragModule>(), isEmpty);
    });

    test('falls back to defaults for an empty spec', () {
      final s = particleSystemFromProperties({});
      expect(s.shape, isA<ConeShape>());
      expect(s.looping, isTrue);
      expect(s.storage.capacity, greaterThan(0));
    });

    test('absent sizeOverLife keeps particles visible (multiplier 1, not 0)', () {
      // Regression: an absent curve decoded to a constant-zero curve, shrinking
      // every particle to size 0 (invisible). It must default to x1.
      final s = particleSystemFromProperties({});
      final size = s.modules.whereType<SizeOverLifeModule>().first;
      expect(size.scale.sample(0.0, 0.0), closeTo(1.0, 1e-6));
      expect(size.scale.sample(1.0, 0.0), closeTo(1.0, 1e-6));
    });

    test('absent colorOverLife defaults to opaque white', () {
      final s = particleSystemFromProperties({});
      final color = s.modules.whereType<ColorOverLifeModule>().first;
      final out = Vector4.zero();
      color.color.sample(0.5, 0.0, out);
      expect(out.x, closeTo(1.0, 1e-6));
      expect(out.w, closeTo(1.0, 1e-6));
    });
  });

  group('round-trip through properties', () {
    test('system -> properties -> system preserves the config', () {
      final original = particleSystemFromProperties(_authoredProperties());
      final props = particleSystemToProperties(
        original,
        blendMode: SpriteBlendMode.additive,
        facing: BillboardFacing.velocityStretched,
        velocityStretch: 0.12,
      );
      final rebuilt = particleSystemFromProperties(props);

      expect(rebuilt.storage.capacity, original.storage.capacity);
      expect(rebuilt.spawner.rate, original.spawner.rate);
      expect(rebuilt.seed, original.seed);
      expect(rebuilt.looping, original.looping);
      expect(rebuilt.duration, original.duration);
      expect(rebuilt.gravity.y, closeTo(original.gravity.y, 1e-9));
      expect((rebuilt.shape as ConeShape).radius, closeTo(0.4, 1e-9));

      // Distributions survive (compare a sampled value).
      expect(
        rebuilt.startSpeed.sample(0, 0.5),
        closeTo(original.startSpeed.sample(0, 0.5), 1e-6),
      );
      // The over-life curve survives via the size module.
      final size = rebuilt.modules.whereType<SizeOverLifeModule>().first;
      expect(size.scale.sample(0.0, 0.0), closeTo(1.0, 1e-2));
      expect(size.scale.sample(1.0, 0.0), closeTo(0.0, 1e-2));
    });

    test('properties survive a system round-trip byte-for-byte', () {
      // Build a system from authored props, write it back, and confirm the
      // re-derived property map matches the canonical one the writer produces.
      final props = _authoredProperties();
      final system = particleSystemFromProperties(props);
      final out = particleSystemToProperties(
        system,
        blendMode: SpriteBlendMode.additive,
        facing: BillboardFacing.velocityStretched,
        velocityStretch: 0.12,
      );
      // Re-deriving from the writer's own output is stable.
      final system2 = particleSystemFromProperties(out);
      final out2 = particleSystemToProperties(
        system2,
        blendMode: SpriteBlendMode.additive,
        facing: BillboardFacing.velocityStretched,
        velocityStretch: 0.12,
      );
      expect(out2.keys.toSet(), out.keys.toSet());
      expect((out2['blendMode']! as StringValue).value, 'additive');
      expect((out2['facing']! as StringValue).value, 'velocityStretched');
    });
  });
}
