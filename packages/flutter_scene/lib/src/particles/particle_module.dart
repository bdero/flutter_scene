import 'package:vector_math/vector_math.dart';

import 'package:flutter_scene/src/particles/distribution.dart';
import 'package:flutter_scene/src/particles/particle_storage.dart';

/// A unit of per-particle behaviour layered onto a system's simulation.
///
/// Modules run in two phases, in list order: [spawn] is called once for each
/// newly created particle (to set birth state a shape or the main config does
/// not), and [update] is called once per simulation step over all live
/// particles (to apply forces or evaluate over-life properties). Both default
/// to no-ops so a module implements only the phase it needs. A module touches
/// only the storage columns it documents.
abstract class ParticleModule {
  /// Creates a particle module.
  const ParticleModule();

  /// Initializes the freshly spawned particle at [index].
  void spawn(ParticleStorage storage, int index) {}

  /// Advances every live particle by [dt] seconds.
  void update(ParticleStorage storage, double dt) {}
}

/// Adds a constant [acceleration] (world units per second squared) to every
/// particle's velocity each step. Use it for wind or as an extra gravity on top
/// of the system's own gravity.
class AccelerationModule extends ParticleModule {
  /// Creates a constant-acceleration force.
  AccelerationModule(Vector3 acceleration)
    : acceleration = acceleration.clone();

  /// The acceleration applied each step.
  final Vector3 acceleration;

  @override
  void update(ParticleStorage storage, double dt) {
    final ax = acceleration.x * dt;
    final ay = acceleration.y * dt;
    final az = acceleration.z * dt;
    final n = storage.aliveCount;
    for (var i = 0; i < n; i++) {
      storage.velX[i] += ax;
      storage.velY[i] += ay;
      storage.velZ[i] += az;
    }
  }
}

/// Damps velocity toward zero with a linear drag [coefficient] (per second):
/// each step scales velocity by `max(0, 1 - coefficient * dt)`.
class LinearDragModule extends ParticleModule {
  /// Creates a linear drag force with the given [coefficient].
  LinearDragModule(this.coefficient) : assert(coefficient >= 0);

  /// The drag coefficient (per second).
  double coefficient;

  @override
  void update(ParticleStorage storage, double dt) {
    var factor = 1.0 - coefficient * dt;
    if (factor < 0.0) factor = 0.0;
    final n = storage.aliveCount;
    for (var i = 0; i < n; i++) {
      storage.velX[i] *= factor;
      storage.velY[i] *= factor;
      storage.velZ[i] *= factor;
    }
  }
}

/// Scales each particle's rendered size by a [FloatDistribution] sampled over
/// its normalized age, relative to the size set at spawn (`size = baseSize *
/// scale(age / lifetime)`).
class SizeOverLifeModule extends ParticleModule {
  /// Creates a size-over-life force driven by [scale].
  const SizeOverLifeModule(this.scale);

  /// The multiplier sampled over normalized age.
  final FloatDistribution scale;

  @override
  void update(ParticleStorage storage, double dt) {
    final n = storage.aliveCount;
    for (var i = 0; i < n; i++) {
      final life = storage.lifetime[i];
      final nAge = life > 0.0 ? storage.age[i] / life : 0.0;
      storage.size[i] =
          storage.baseSize[i] * scale.sample(nAge, storage.random01[i]);
    }
  }
}

/// Sets each particle's color from a [ColorDistribution] sampled over its
/// normalized age (color over life).
class ColorOverLifeModule extends ParticleModule {
  /// Creates a color-over-life force driven by [color].
  ColorOverLifeModule(this.color);

  /// The color sampled over normalized age.
  final ColorDistribution color;

  final Vector4 _tmp = Vector4.zero();

  @override
  void update(ParticleStorage storage, double dt) {
    final n = storage.aliveCount;
    for (var i = 0; i < n; i++) {
      final life = storage.lifetime[i];
      final nAge = life > 0.0 ? storage.age[i] / life : 0.0;
      color.sample(nAge, storage.random01[i], _tmp);
      storage.colorR[i] = _tmp.x;
      storage.colorG[i] = _tmp.y;
      storage.colorB[i] = _tmp.z;
      storage.colorA[i] = _tmp.w;
    }
  }
}

/// Integrates each particle's in-plane rotation from its angular velocity
/// (`rotation += angularVelocity * dt`).
class RotationModule extends ParticleModule {
  /// Creates a rotation integrator.
  const RotationModule();

  @override
  void update(ParticleStorage storage, double dt) {
    final n = storage.aliveCount;
    for (var i = 0; i < n; i++) {
      storage.rotation[i] += storage.angularVelocity[i] * dt;
    }
  }
}
