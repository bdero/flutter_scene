import 'package:vector_math/vector_math.dart';

import 'package:flutter_scene/src/noise/curl.dart';
import 'package:flutter_scene/src/particles/distribution.dart';
import 'package:flutter_scene/src/particles/particle_storage.dart';

// Salt for the flipbook start-frame random. The system reserves 1-6 and
// emitter shapes 20+, so module salts live in the 10-19 range.
const int _saltFlipbookStart = 10;

/// A unit of per-particle behaviour layered onto a system's simulation.
///
/// Modules run in two phases, in list order: [spawn] is called once for each
/// newly created particle (to set birth state a shape or the main config does
/// not), and [update] is called once per simulation step over all live
/// particles (to apply forces or evaluate over-life properties). Both default
/// to no-ops so a module implements only the phase it needs. A module touches
/// only the storage columns it documents.
/// {@category Particles}
abstract class ParticleModule {
  /// Creates a particle module.
  const ParticleModule();

  /// Initializes the freshly spawned particle at [index].
  void spawn(ParticleStorage storage, int index) {}

  /// Advances every live particle by [dt] seconds.
  ///
  /// Runs before the system integrates velocity into position, which is what
  /// a force wants: it is contributing to the velocity that is about to be
  /// applied.
  void update(ParticleStorage storage, double dt) {}

  /// Runs after the system has integrated positions, before ageing.
  ///
  /// For anything that has to react to where a particle actually ended up.
  /// Collision is the reason this exists: testing the position a particle
  /// had before it moved lets it pass through a wall for a step and come
  /// back, which reads as a flicker rather than a bounce.
  void postIntegrate(ParticleStorage storage, double dt) {}
}

/// Adds a constant [acceleration] (world units per second squared) to every
/// particle's velocity each step. Use it for wind or as an extra gravity on top
/// of the system's own gravity.
/// {@category Particles}
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
/// {@category Particles}
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
/// {@category Particles}
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
/// {@category Particles}
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

/// Animates each particle's flipbook [ParticleStorage.frame] through a
/// [frameCount]-cell atlas.
///
/// With [framesPerSecond] unset the sequence plays exactly once over the
/// particle's life (frame = normalized age * frameCount), the natural mode
/// for baked erosion/dissolve sequences. With it set, frames advance at that
/// fixed rate and wrap, for looping atlases. [randomStartFrame] offsets each
/// particle by a stable random frame so simultaneous spawns do not animate in
/// lockstep; leave it off for once-over-life erosion sequences, which must
/// start at frame zero.
/// {@category Particles}
class FlipbookModule extends ParticleModule {
  /// Creates a flipbook animator over [frameCount] cells.
  const FlipbookModule({
    required this.frameCount,
    this.framesPerSecond,
    this.randomStartFrame = false,
  }) : assert(frameCount > 0),
       assert(framesPerSecond == null || framesPerSecond > 0);

  /// The number of cells in the atlas (columns * rows).
  final int frameCount;

  /// Fixed playback rate; `null` plays the sequence once over each particle's
  /// life instead.
  final double? framesPerSecond;

  /// Whether each particle starts at a stable random frame offset (wrapped).
  final bool randomStartFrame;

  @override
  void update(ParticleStorage storage, double dt) {
    final count = frameCount.toDouble();
    final fps = framesPerSecond;
    final n = storage.aliveCount;
    for (var i = 0; i < n; i++) {
      var frame = 0.0;
      if (fps == null) {
        final life = storage.lifetime[i];
        final nAge = life > 0.0 ? storage.age[i] / life : 0.0;
        // Clamp shy of the end so the last cell holds instead of wrapping.
        frame = nAge * count;
        if (frame > count - 1.0) frame = count - 1.0;
      } else {
        frame = storage.age[i] * fps;
      }
      if (randomStartFrame) {
        frame += storage.randomFor(i, _saltFlipbookStart) * count;
      }
      storage.frame[i] = frame % count;
    }
  }
}

/// Advects particles through a curl-noise field, the divergence-free swirl
/// that gives fire, smoke, and drifting embers their turbulent motion.
///
/// Each step samples [noiseCurl3] at the particle's position (scaled by
/// [frequency], with the field scrolled by [scroll] per second) and adds
/// `curl * strength * dt` to its velocity. Larger [frequency] gives smaller,
/// busier eddies; [scroll] drifts the whole field (an upward scroll makes
/// rising flames lick).
/// {@category Particles}
class TurbulenceModule extends ParticleModule {
  /// Creates a curl-noise force.
  TurbulenceModule({
    this.strength = 1.0,
    this.frequency = 1.0,
    Vector3? scroll,
    this.seed = 1337,
  }) : scroll = scroll?.clone() ?? Vector3.zero();

  /// Velocity change per second at unit curl magnitude.
  double strength;

  /// Spatial scale applied to particle positions before sampling.
  double frequency;

  /// How fast the noise field itself drifts, in world units per second
  /// (applied in field space after [frequency] scaling of time).
  final Vector3 scroll;

  /// The curl field's seed; emitters with different seeds swirl differently.
  final int seed;

  double _time = 0.0;

  @override
  void update(ParticleStorage storage, double dt) {
    _time += dt;
    final ox = scroll.x * _time * frequency;
    final oy = scroll.y * _time * frequency;
    final oz = scroll.z * _time * frequency;
    final n = storage.aliveCount;
    for (var i = 0; i < n; i++) {
      final curl = noiseCurl3(
        storage.posX[i] * frequency - ox,
        storage.posY[i] * frequency - oy,
        storage.posZ[i] * frequency - oz,
        seed: seed,
      );
      storage.velX[i] += curl.x * strength * dt;
      storage.velY[i] += curl.y * strength * dt;
      storage.velZ[i] += curl.z * strength * dt;
    }
  }
}

/// Integrates each particle's in-plane rotation from its angular velocity
/// (`rotation += angularVelocity * dt`).
/// {@category Particles}
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
