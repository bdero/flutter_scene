import 'package:flutter_scene/src/particles/distribution.dart';
import 'package:flutter_scene/src/particles/emitter_shape.dart';
import 'package:flutter_scene/src/particles/particle_module.dart';
import 'package:flutter_scene/src/particles/particle_storage.dart';
import 'package:flutter_scene/src/particles/particle_system.dart';
import 'package:flutter_scene/src/particles/spawner.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

const double _fixed = 1.0 / 60.0;

// Snapshots the live prefix of every column so two runs can be compared.
List<double> _snapshot(ParticleStorage s) {
  final out = <double>[];
  for (var i = 0; i < s.aliveCount; i++) {
    out.addAll([
      s.posX[i],
      s.posY[i],
      s.posZ[i],
      s.velX[i],
      s.velY[i],
      s.velZ[i],
      s.age[i],
      s.lifetime[i],
      s.rotation[i],
      s.angularVelocity[i],
      s.size[i],
      s.baseSize[i],
      s.colorR[i],
      s.colorG[i],
      s.colorB[i],
      s.colorA[i],
      s.random01[i],
    ]);
  }
  return out;
}

void main() {
  group('stepping', () {
    test('drains the accumulator in whole fixed steps', () {
      final system = ParticleSystem(
        shape: PointShape(),
        spawner: Spawner(),
        fixedStep: _fixed,
      );
      system.step(0.1); // 0.1 / (1/60) = 6 steps exactly
      expect(system.time, closeTo(6 * _fixed, 1e-9));
    });

    test('clamps an over-long frame to maxFrameTime', () {
      final system = ParticleSystem(
        shape: PointShape(),
        spawner: Spawner(),
        fixedStep: _fixed,
        maxFrameTime: 0.25,
      );
      system.step(10.0); // clamped to 0.25 -> 15 steps
      expect(system.time, closeTo(15 * _fixed, 1e-9));
    });

    test('leftover time carries into the next step', () {
      final system = ParticleSystem(
        shape: PointShape(),
        spawner: Spawner(),
        fixedStep: _fixed,
      );
      system.step(_fixed * 1.5); // one step, half remains
      expect(system.time, closeTo(_fixed, 1e-9));
      system.step(_fixed * 0.5); // accumulated to one more
      expect(system.time, closeTo(2 * _fixed, 1e-9));
    });
  });

  group('emission and motion', () {
    test('emits and integrates velocity over a step', () {
      final system = ParticleSystem(
        shape: PointShape(direction: Vector3(0, 1, 0)),
        spawner: Spawner(bursts: const [ParticleBurst(time: 0.0, count: 1)]),
        startSpeed: const ConstantFloat(2.0),
        fixedStep: _fixed,
      );
      system.step(_fixed);
      expect(system.storage.aliveCount, 1);
      // Spawned at origin with vel (0,2,0), then integrated one step. Columns
      // are float32, so compare with single-precision tolerance.
      expect(system.storage.posY[0], closeTo(2.0 * _fixed, 1e-6));
      expect(system.storage.velY[0], closeTo(2.0, 1e-6));
    });

    test('gravity accelerates velocity downward', () {
      final system = ParticleSystem(
        shape: PointShape(),
        spawner: Spawner(bursts: const [ParticleBurst(time: 0.0, count: 1)]),
        startSpeed: const ConstantFloat(0.0),
        gravity: Vector3(0, -10, 0),
        fixedStep: _fixed,
      );
      system.step(_fixed);
      expect(system.storage.aliveCount, 1);
      expect(system.storage.velY[0], closeTo(-10.0 * _fixed, 1e-6));
    });

    test('particles die once they outlive their lifetime', () {
      final system = ParticleSystem(
        shape: PointShape(),
        spawner: Spawner(bursts: const [ParticleBurst(time: 0.0, count: 5)]),
        lifetime: const ConstantFloat(0.05), // ~3 steps
        fixedStep: _fixed,
      );
      system.step(_fixed); // spawn 5
      expect(system.storage.aliveCount, 5);
      system.step(0.2); // well past their lifetime
      expect(system.storage.aliveCount, 0);
    });
  });

  group('looping', () {
    test('a non-looping system stops emitting past its duration', () {
      final system = ParticleSystem(
        shape: PointShape(),
        spawner: Spawner(rate: 60.0),
        lifetime: const ConstantFloat(100.0),
        looping: false,
        duration: 0.05, // ~3 steps of emission
        fixedStep: _fixed,
      );
      system.step(1.0);
      // Emission stopped at ~0.05s; far fewer than a full second of spawns.
      expect(system.storage.aliveCount, lessThan(10));
      expect(system.storage.aliveCount, greaterThan(0));
    });
  });

  group('prewarm', () {
    test('populates the system at construction', () {
      final cold = ParticleSystem(
        shape: PointShape(),
        spawner: Spawner(rate: 60.0),
        lifetime: const ConstantFloat(100.0),
        fixedStep: _fixed,
      );
      expect(cold.storage.aliveCount, 0);

      final warm = ParticleSystem(
        shape: PointShape(),
        spawner: Spawner(rate: 60.0),
        lifetime: const ConstantFloat(100.0),
        fixedStep: _fixed,
        prewarm: 0.5, // 30 steps -> 30 particles
      );
      expect(warm.storage.aliveCount, 30);
    });
  });

  group('determinism', () {
    ParticleSystem build() => ParticleSystem(
      maxParticles: 512,
      shape: const SphereShape(radius: 1.0),
      spawner: Spawner(
        rate: 200.0,
        bursts: const [ParticleBurst(time: 0.1, count: 50)],
      ),
      modules: [
        LinearDragModule(0.5),
        SizeOverLifeModule(CurveFloat(ParticleCurve.linear(from: 1, to: 0))),
        ColorOverLifeModule(
          GradientColor(
            ColorGradient([
              ColorStop(0.0, Vector4(1, 1, 0, 1)),
              ColorStop(1.0, Vector4(1, 0, 0, 0)),
            ]),
          ),
        ),
        const RotationModule(),
      ],
      lifetime: const UniformFloat(0.3, 0.8),
      startSpeed: const UniformFloat(1.0, 3.0),
      startSize: const UniformFloat(0.2, 0.5),
      startRotation: const UniformFloat(0.0, 6.28),
      startAngularVelocity: const UniformFloat(-2.0, 2.0),
      gravity: Vector3(0, -3, 0),
      seed: 1234,
      fixedStep: _fixed,
    );

    test('same seed and steps reproduce identical state', () {
      final a = build();
      final b = build();
      for (var i = 0; i < 60; i++) {
        a.step(_fixed);
        b.step(_fixed);
      }
      expect(a.storage.aliveCount, greaterThan(0));
      expect(a.storage.aliveCount, b.storage.aliveCount);
      expect(_snapshot(a.storage), _snapshot(b.storage));
    });

    test('a different seed diverges', () {
      final a = build();
      final b = ParticleSystem(
        maxParticles: 512,
        shape: const SphereShape(radius: 1.0),
        spawner: Spawner(rate: 200.0),
        startSpeed: const UniformFloat(1.0, 3.0),
        seed: 9999,
        fixedStep: _fixed,
      );
      for (var i = 0; i < 30; i++) {
        a.step(_fixed);
        b.step(_fixed);
      }
      expect(_snapshot(a.storage), isNot(equals(_snapshot(b.storage))));
    });
  });
}
