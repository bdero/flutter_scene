import 'package:scene/scene.dart';
import 'package:scene/schema.dart';
import 'package:flutter_scene/src/fscene/realize/particle_emitter_codec.dart';
import 'package:flutter_scene/src/fscene/realize/particle_property_values.dart';
import 'package:flutter_scene/src/particles/distribution.dart';
import 'package:flutter_scene/src/particles/emitter_shape.dart';
import 'package:flutter_scene/src/particles/particle_module.dart';
import 'package:flutter_scene/src/particles/particle_system.dart';
import 'package:flutter_scene/src/particles/spawner.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

// A fully populated property map that exercises every system field, so the
// round-trip covers each one.
Map<String, PropertyValue> _authoredProperties() => {
  'maxParticles': const IntValue(256),
  'emitRate': const DoubleValue(80.0),
  'bursts': ListValue([
    MapValue({'time': const DoubleValue(0.5), 'count': const IntValue(20)}),
    MapValue({
      'time': const DoubleValue(1.0),
      'count': const IntValue(8),
      'interval': const DoubleValue(0.25),
      'cycles': const IntValue(4),
    }),
  ]),
  'shape': MapValue({
    'kind': const StringValue('cone'),
    'radius': const DoubleValue(0.4),
    'angle': const DoubleValue(0.35),
  }),
  'modules': ListValue([
    MapValue({
      'kind': const StringValue('linearDrag'),
      'coefficient': const DoubleValue(0.5),
    }),
    MapValue({
      'kind': const StringValue('sizeOverLife'),
      'scale': encodeFloatDistribution(
        CurveFloat(ParticleCurve.linear(from: 1, to: 0)),
      ),
    }),
    MapValue({
      'kind': const StringValue('colorOverLife'),
      'color': encodeColorDistribution(
        GradientColor(
          ColorGradient([
            ColorStop(0.0, Vector4(1, 0.8, 0.2, 1)),
            ColorStop(1.0, Vector4(1, 0.1, 0, 0)),
          ]),
        ),
      ),
    }),
    MapValue({'kind': const StringValue('rotation')}),
  ]),
  'lifetime': encodeFloatDistribution(const UniformFloat(0.5, 1.5)),
  'startSpeed': encodeFloatDistribution(const UniformFloat(2.0, 4.0)),
  'startSize': encodeFloatDistribution(const ConstantFloat(0.3)),
  'startRotation': encodeFloatDistribution(const UniformFloat(0, 6.28)),
  'startAngularVelocity': encodeFloatDistribution(const UniformFloat(-1, 1)),
  'startColor': encodeColorDistribution(
    UniformColor(Vector4(1, 0.5, 0, 1), Vector4(1, 1, 0.5, 1)),
  ),
  'gravity': Vec3Value(Vector3(0, -9.8, 0)),
  'looping': const BoolValue(false),
  'duration': const DoubleValue(3.0),
  'fixedStep': const DoubleValue(1.0 / 30.0),
  'maxFrameTime': const DoubleValue(0.5),
  'seed': const IntValue(99),
  'prewarm': const DoubleValue(0.0),
};

ParticleSystem _roundTrip(ParticleSystem system) =>
    particleSystemFromProperties(particleSystemToProperties(system));

void main() {
  group('particleSystemFromProperties', () {
    test('builds the configured system', () {
      final s = particleSystemFromProperties(_authoredProperties());
      expect(s.storage.capacity, 256);
      expect(s.spawner.rate, 80.0);
      expect(s.spawner.bursts.length, 2);
      expect(s.shape, isA<ConeEmitterShape>());
      expect((s.shape as ConeEmitterShape).radius, closeTo(0.4, 1e-9));
      expect(s.lifetime, isA<UniformFloat>());
      expect(s.startColor, isA<UniformColor>());
      expect(s.gravity.y, closeTo(-9.8, 1e-5)); // gravity stored as float32
      expect(s.looping, isFalse);
      expect(s.seed, 99);
      expect(s.fixedStep, closeTo(1.0 / 30.0, 1e-9));
      expect(s.maxFrameTime, closeTo(0.5, 1e-9));
      expect(s.modules, hasLength(4));
      expect(s.modules[0], isA<LinearDragModule>());
      expect(s.modules[1], isA<SizeOverLifeModule>());
      expect(s.modules[2], isA<ColorOverLifeModule>());
      expect(s.modules[3], isA<RotationModule>());
    });

    test('falls back to defaults for an empty spec', () {
      final s = particleSystemFromProperties({});
      expect(s.shape, isA<ConeEmitterShape>());
      expect(s.looping, isTrue);
      expect(s.storage.capacity, greaterThan(0));
      expect(s.startColor, isA<ConstantColor>());
      expect(s.fixedStep, closeTo(1.0 / 60.0, 1e-9));
      expect(s.maxFrameTime, closeTo(0.25, 1e-9));
    });

    test('legacy flat shape keys still realize', () {
      final cone = particleSystemFromProperties({
        'shapeType': const StringValue('cone'),
        'shapeRadius': const DoubleValue(0.4),
        'shapeAngle': const DoubleValue(0.35),
      });
      expect(cone.shape, isA<ConeEmitterShape>());
      expect((cone.shape as ConeEmitterShape).radius, closeTo(0.4, 1e-9));
      expect((cone.shape as ConeEmitterShape).angle, closeTo(0.35, 1e-9));

      final sphere = particleSystemFromProperties({
        'shapeType': const StringValue('sphere'),
        'shapeRadius': const DoubleValue(2.0),
      });
      expect(sphere.shape, isA<SphereEmitterShape>());
      expect((sphere.shape as SphereEmitterShape).radius, closeTo(2.0, 1e-9));

      final box = particleSystemFromProperties({
        'shapeType': const StringValue('box'),
        'shapeRadius': const DoubleValue(1.5),
      });
      expect(box.shape, isA<BoxEmitterShape>());
      expect((box.shape as BoxEmitterShape).halfExtents.x, closeTo(1.5, 1e-9));

      final point = particleSystemFromProperties({
        'shapeType': const StringValue('point'),
      });
      expect(point.shape, isA<PointEmitterShape>());
    });

    test('a shape union wins over legacy flat keys', () {
      final s = particleSystemFromProperties({
        'shape': MapValue({
          'kind': const StringValue('sphere'),
          'radius': const DoubleValue(3.0),
        }),
        'shapeType': const StringValue('cone'),
        'shapeRadius': const DoubleValue(0.1),
      });
      expect(s.shape, isA<SphereEmitterShape>());
      expect((s.shape as SphereEmitterShape).radius, closeTo(3.0, 1e-9));
    });

    test('legacy module keys realize the fixed stack', () {
      final s = particleSystemFromProperties({
        'drag': const DoubleValue(0.5),
        'sizeOverLife': encodeParticleCurve(
          ParticleCurve.linear(from: 1, to: 0),
        ),
        'colorOverLife': encodeColorGradient(
          ColorGradient.constant(Vector4(1, 0, 0, 1)),
        ),
      });
      expect(s.modules, hasLength(4));
      expect(s.modules[0], isA<LinearDragModule>());
      expect((s.modules[0] as LinearDragModule).coefficient, 0.5);
      expect(s.modules[1], isA<SizeOverLifeModule>());
      expect(s.modules[2], isA<ColorOverLifeModule>());
      expect(s.modules[3], isA<RotationModule>());
    });

    test('legacy zero drag omits the drag module', () {
      final s = particleSystemFromProperties({'drag': const DoubleValue(0)});
      expect(s.modules.whereType<LinearDragModule>(), isEmpty);
    });

    test('absent sizeOverLife keeps particles visible (multiplier 1, not 0)', () {
      // Regression: an absent curve decoded to a constant-zero curve, shrinking
      // every particle to size 0 (invisible). It must default to x1.
      final s = particleSystemFromProperties({});
      final size = s.modules.whereType<SizeOverLifeModule>().first;
      expect(size.scale.sample(0.0, 0.0), closeTo(1.0, 1e-6));
      expect(size.scale.sample(1.0, 0.0), closeTo(1.0, 1e-6));
    });

    test('absent sizeOverLife leaves stepped particles at size 1', () {
      final s = particleSystemFromProperties({
        'emitRate': const DoubleValue(60.0),
        'startSize': encodeFloatDistribution(const ConstantFloat(1.0)),
      });
      s.step(0.5);
      expect(s.storage.aliveCount, greaterThan(0));
      expect(s.storage.size[0], closeTo(1.0, 1e-6));
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

  group('shape union round-trip', () {
    test('point', () {
      final s = _roundTrip(
        ParticleSystem(
          shape: PointEmitterShape(direction: Vector3(1, 0, 0)),
          spawner: Spawner(rate: 1),
        ),
      );
      final shape = s.shape as PointEmitterShape;
      expect(shape.direction.x, closeTo(1.0, 1e-9));
      expect(shape.direction.y, closeTo(0.0, 1e-9));
    });

    test('sphere', () {
      final s = _roundTrip(
        ParticleSystem(
          shape: const SphereEmitterShape(
            radius: 2.5,
            surfaceOnly: true,
            hemisphere: true,
          ),
          spawner: Spawner(rate: 1),
        ),
      );
      final shape = s.shape as SphereEmitterShape;
      expect(shape.radius, closeTo(2.5, 1e-9));
      expect(shape.surfaceOnly, isTrue);
      expect(shape.hemisphere, isTrue);
    });

    test('cone', () {
      final s = _roundTrip(
        ParticleSystem(
          shape: const ConeEmitterShape(angle: 0.7, radius: 1.2),
          spawner: Spawner(rate: 1),
        ),
      );
      final shape = s.shape as ConeEmitterShape;
      expect(shape.angle, closeTo(0.7, 1e-9));
      expect(shape.radius, closeTo(1.2, 1e-9));
    });

    test('box', () {
      final s = _roundTrip(
        ParticleSystem(
          shape: BoxEmitterShape(
            halfExtents: Vector3(1, 2, 3),
            direction: Vector3(0, 0, 1),
          ),
          spawner: Spawner(rate: 1),
        ),
      );
      final shape = s.shape as BoxEmitterShape;
      expect(shape.halfExtents.x, closeTo(1.0, 1e-9));
      expect(shape.halfExtents.y, closeTo(2.0, 1e-9));
      expect(shape.halfExtents.z, closeTo(3.0, 1e-9));
      expect(shape.direction.z, closeTo(1.0, 1e-9));
    });
  });

  group('modules round-trip', () {
    test('an arbitrary module order and every kind survive', () {
      final s = _roundTrip(
        ParticleSystem(
          shape: PointEmitterShape(),
          spawner: Spawner(rate: 1),
          modules: [
            const RotationModule(),
            LinearDragModule(0.25),
            TurbulenceModule(
              strength: 2.0,
              frequency: 0.5,
              scroll: Vector3(0, 1, 0),
              seed: 7,
            ),
            ColorOverLifeModule(ConstantColor(Vector4(1, 0, 0, 1))),
            const FlipbookModule(
              frameCount: 16,
              framesPerSecond: 24.0,
              randomStartFrame: true,
            ),
            AccelerationModule(Vector3(0, 2, 0)),
            SizeOverLifeModule(const UniformFloat(0.5, 1.5)),
          ],
        ),
      );
      expect(s.modules, hasLength(7));
      expect(s.modules[0], isA<RotationModule>());
      expect((s.modules[1] as LinearDragModule).coefficient, 0.25);
      final turbulence = s.modules[2] as TurbulenceModule;
      expect(turbulence.strength, 2.0);
      expect(turbulence.frequency, 0.5);
      expect(turbulence.scroll.y, closeTo(1.0, 1e-9));
      expect(turbulence.seed, 7);
      final color = (s.modules[3] as ColorOverLifeModule).color;
      expect((color as ConstantColor).color.x, closeTo(1.0, 1e-9));
      final flipbook = s.modules[4] as FlipbookModule;
      expect(flipbook.frameCount, 16);
      expect(flipbook.framesPerSecond, 24.0);
      expect(flipbook.randomStartFrame, isTrue);
      expect((s.modules[5] as AccelerationModule).acceleration.y, 2.0);
      final size = (s.modules[6] as SizeOverLifeModule).scale;
      expect((size as UniformFloat).min, 0.5);
      expect(size.max, 1.5);
    });

    test('a once-over-life flipbook keeps its null frame rate', () {
      final s = _roundTrip(
        ParticleSystem(
          shape: PointEmitterShape(),
          spawner: Spawner(rate: 1),
          modules: const [FlipbookModule(frameCount: 8)],
        ),
      );
      final flipbook = s.modules.single as FlipbookModule;
      expect(flipbook.frameCount, 8);
      expect(flipbook.framesPerSecond, isNull);
    });

    test('an empty module list round-trips empty (not the default stack)', () {
      final s = _roundTrip(
        ParticleSystem(shape: PointEmitterShape(), spawner: Spawner(rate: 1)),
      );
      expect(s.modules, isEmpty);
    });

    test('an unknown module kind is skipped', () {
      final s = particleSystemFromProperties({
        'modules': ListValue([
          MapValue({'kind': const StringValue('warpDrive')}),
          MapValue({'kind': const StringValue('rotation')}),
        ]),
      });
      expect(s.modules.single, isA<RotationModule>());
    });
  });

  group('startColor round-trip', () {
    test('constant', () {
      final s = _roundTrip(
        ParticleSystem(
          shape: PointEmitterShape(),
          spawner: Spawner(rate: 1),
          startColor: ConstantColor(Vector4(0.2, 0.4, 0.6, 0.8)),
        ),
      );
      final color = s.startColor as ConstantColor;
      // Vector4 stores float32, so compare at float32 precision.
      expect(color.color.x, closeTo(0.2, 1e-6));
      expect(color.color.w, closeTo(0.8, 1e-6));
    });

    test('gradient', () {
      final s = _roundTrip(
        ParticleSystem(
          shape: PointEmitterShape(),
          spawner: Spawner(rate: 1),
          startColor: GradientColor(
            ColorGradient([
              ColorStop(0.0, Vector4(1, 0, 0, 1)),
              ColorStop(1.0, Vector4(0, 0, 1, 0)),
            ]),
          ),
        ),
      );
      final gradient = (s.startColor as GradientColor).gradient;
      expect(gradient.stops, hasLength(2));
      expect(gradient.stops[0].color.x, closeTo(1.0, 1e-9));
      expect(gradient.stops[1].color.z, closeTo(1.0, 1e-9));
      expect(gradient.stops[1].color.w, closeTo(0.0, 1e-9));
    });

    test('uniform', () {
      final s = _roundTrip(
        ParticleSystem(
          shape: PointEmitterShape(),
          spawner: Spawner(rate: 1),
          startColor: UniformColor(
            Vector4(1, 0.5, 0, 1),
            Vector4(0, 0.5, 1, 0.5),
          ),
        ),
      );
      final color = s.startColor as UniformColor;
      expect(color.a.x, closeTo(1.0, 1e-9));
      expect(color.b.z, closeTo(1.0, 1e-9));
      expect(color.b.w, closeTo(0.5, 1e-9));
    });

    test('an unrecognized value decodes to the constant fallback', () {
      final d = decodeColorDistribution(
        MapValue({'kind': const StringValue('plaid')}),
      );
      expect(d, isA<ConstantColor>());
      expect((d as ConstantColor).color.w, closeTo(1.0, 1e-9));
    });
  });

  group('bursts round-trip', () {
    test('single-shot and repeating bursts survive', () {
      final s = _roundTrip(
        ParticleSystem(
          shape: PointEmitterShape(),
          spawner: Spawner(
            rate: 5,
            bursts: const [
              ParticleBurst(time: 0.5, count: 30),
              ParticleBurst(time: 1.0, count: 10, interval: 0.25, cycles: 4),
              ParticleBurst(time: 2.0, count: 3, interval: 1.0),
            ],
          ),
        ),
      );
      final bursts = s.spawner.bursts;
      expect(bursts, hasLength(3));
      expect(bursts[0].time, 0.5);
      expect(bursts[0].count, 30);
      expect(bursts[0].interval, 0.0);
      expect(bursts[0].cycles, isNull);
      expect(bursts[1].interval, 0.25);
      expect(bursts[1].cycles, 4);
      expect(bursts[2].interval, 1.0);
      expect(bursts[2].cycles, isNull);
      expect(s.spawner.rate, 5.0);
    });
  });

  group('round-trip through properties', () {
    test('system -> properties -> system preserves the config', () {
      final original = particleSystemFromProperties(_authoredProperties());
      final rebuilt = _roundTrip(original);

      expect(rebuilt.storage.capacity, original.storage.capacity);
      expect(rebuilt.spawner.rate, original.spawner.rate);
      expect(rebuilt.spawner.bursts.length, original.spawner.bursts.length);
      expect(rebuilt.seed, original.seed);
      expect(rebuilt.looping, original.looping);
      expect(rebuilt.duration, original.duration);
      expect(rebuilt.fixedStep, original.fixedStep);
      expect(rebuilt.maxFrameTime, original.maxFrameTime);
      expect(rebuilt.gravity.y, closeTo(original.gravity.y, 1e-9));
      expect((rebuilt.shape as ConeEmitterShape).radius, closeTo(0.4, 1e-9));

      // Distributions survive (compare a sampled value).
      expect(
        rebuilt.startSpeed.sample(0, 0.5),
        closeTo(original.startSpeed.sample(0, 0.5), 1e-6),
      );
      final out = Vector4.zero();
      final expected = Vector4.zero();
      rebuilt.startColor.sample(0, 0.5, out);
      original.startColor.sample(0, 0.5, expected);
      expect(out.x, closeTo(expected.x, 1e-6));

      // The over-life curve survives via the size module, in place.
      expect(rebuilt.modules, hasLength(original.modules.length));
      final size = rebuilt.modules.whereType<SizeOverLifeModule>().first;
      expect(size.scale.sample(0.0, 0.0), closeTo(1.0, 1e-2));
      expect(size.scale.sample(1.0, 0.0), closeTo(0.0, 1e-2));
    });

    test('properties survive a system round-trip byte-for-byte', () {
      // Build a system from authored props, write it back, and confirm the
      // re-derived property map is a fixed point of the writer.
      final system = particleSystemFromProperties(_authoredProperties());
      final out = particleSystemToProperties(system);
      final out2 = particleSystemToProperties(
        particleSystemFromProperties(out),
      );
      expect(out2.keys.toSet(), out.keys.toSet());
      for (final key in out.keys) {
        expect(
          propertyValuesEqual(out2[key], out[key]),
          isTrue,
          reason: '$key did not round-trip',
        );
      }
    });
  });
}
