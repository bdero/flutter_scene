import 'dart:math' as math;

import 'package:vector_math/vector_math.dart';

import 'package:flutter_scene/src/particles/distribution.dart';
import 'package:flutter_scene/src/particles/emitter_shape.dart';
import 'package:flutter_scene/src/particles/particle_module.dart';
import 'package:flutter_scene/src/particles/particle_storage.dart';
import 'package:flutter_scene/src/particles/spawner.dart';

// Salts for deriving independent spawn-property randoms from a particle's
// stored seed. Kept disjoint from the 20+ range emitter shapes use.
const int _saltLifetime = 1;
const int _saltSpeed = 2;
const int _saltSize = 3;
const int _saltRotation = 4;
const int _saltAngularVelocity = 5;
const int _saltColor = 6;

// Lifetimes are clamped to this minimum so normalized age never divides by
// zero and particles always live at least one step.
const double _minLifetime = 1e-4;

/// A self-contained, CPU-driven particle simulation: storage plus the config,
/// shape, spawner, and module stack that fill and advance it.
///
/// The system is pure Dart with no scene-graph or GPU dependency, so it can be
/// driven by a component, a headless test, or a future alternative backend.
/// [step] advances the simulation with a fixed-timestep accumulator (so the
/// result is independent of frame rate) using semi-implicit Euler integration;
/// after stepping, a renderer reads the live columns out of [storage].
///
/// Spawning is gated by [looping]/[duration]: a looping system emits forever,
/// while a non-looping one stops emitting once its run passes [duration]
/// (already-live particles still finish their lives). All randomness derives
/// from [seed], so a given seed and step sequence reproduce exactly (the basis
/// for byte-for-byte tests and editor scrubbing).
class ParticleSystem {
  /// Creates a particle system. The distributions, shape, spawner, gravity,
  /// looping behaviour, fixed-step size, and seed are all configurable; only
  /// [shape] and [spawner] are required.
  ///
  /// When [prewarm] is positive the system is advanced that many seconds at
  /// construction so it starts already populated.
  ParticleSystem({
    int maxParticles = 1024,
    required this.shape,
    required this.spawner,
    List<ParticleModule> modules = const <ParticleModule>[],
    this.lifetime = const ConstantFloat(1.0),
    this.startSpeed = const ConstantFloat(0.0),
    this.startSize = const ConstantFloat(1.0),
    this.startRotation = const ConstantFloat(0.0),
    this.startAngularVelocity = const ConstantFloat(0.0),
    ColorDistribution? startColor,
    Vector3? gravity,
    this.looping = true,
    this.duration = 5.0,
    this.fixedStep = 1.0 / 60.0,
    this.maxFrameTime = 0.25,
    this.seed = 0,
    double prewarm = 0.0,
  }) : assert(maxParticles > 0),
       assert(duration > 0),
       assert(fixedStep > 0),
       assert(maxFrameTime >= fixedStep),
       assert(prewarm >= 0),
       storage = ParticleStorage(maxParticles),
       modules = List<ParticleModule>.unmodifiable(modules),
       startColor = startColor ?? ConstantColor(Vector4(1, 1, 1, 1)),
       gravity = gravity?.clone() ?? Vector3.zero(),
       _random = math.Random(seed) {
    if (prewarm > 0.0) {
      final steps = (prewarm / fixedStep).floor();
      for (var i = 0; i < steps; i++) {
        _stepFixed(fixedStep);
      }
    }
  }

  /// The backing structure-of-arrays storage; a renderer reads its live prefix.
  final ParticleStorage storage;

  /// Where particles spawn and which way they initially head.
  EmitterShape shape;

  /// How many particles to emit each step.
  final Spawner spawner;

  /// The ordered behaviour stack (forces and over-life evaluators).
  final List<ParticleModule> modules;

  /// Per-particle spawn properties sampled (with independent randoms) at birth.
  FloatDistribution lifetime,
      startSpeed,
      startSize,
      startRotation,
      startAngularVelocity;

  /// The color assigned at spawn (a color-over-life module may overwrite it).
  ColorDistribution startColor;

  /// Constant acceleration applied to every particle during integration.
  final Vector3 gravity;

  /// Whether the system emits forever; when false it stops emitting past
  /// [duration].
  bool looping;

  /// The length of one run in seconds (the emit cutoff for a non-looping
  /// system).
  double duration;

  /// The fixed simulation timestep in seconds.
  final double fixedStep;

  /// The largest frame delta honored by [step]; longer frames are clamped so a
  /// hitch cannot spiral the accumulator.
  final double maxFrameTime;

  /// The seed for all spawn randomness.
  final int seed;

  final math.Random _random;
  double _accumulator = 0.0;
  double _systemTime = 0.0;
  final Vector4 _tmpColor = Vector4.zero();

  /// Seconds the system has been running (advances by whole fixed steps).
  double get time => _systemTime;

  /// Advances the simulation by [dt] seconds in fixed-size steps, draining a
  /// clamped accumulator so the outcome is frame-rate independent.
  void step(double dt) {
    var frame = dt;
    if (frame < 0.0) frame = 0.0;
    if (frame > maxFrameTime) frame = maxFrameTime;
    _accumulator += frame;
    while (_accumulator >= fixedStep) {
      _stepFixed(fixedStep);
      _accumulator -= fixedStep;
    }
  }

  /// Removes every live particle and rewinds the clock (the seed stream and
  /// fractional spawn accumulator reset, so a restart replays identically).
  void reset() {
    storage.clear();
    spawner.reset();
    _accumulator = 0.0;
    _systemTime = 0.0;
  }

  void _stepFixed(double dt) {
    // Spawn, unless a non-looping run has elapsed.
    if (looping || _systemTime < duration) {
      final toSpawn = spawner.emit(dt, _systemTime);
      for (var i = 0; i < toSpawn; i++) {
        final index = storage.spawn();
        if (index < 0) break; // pool full
        _initParticle(index);
      }
    }

    // Update-phase modules (forces, over-life evaluators) over all live.
    for (final module in modules) {
      module.update(storage, dt);
    }

    // Semi-implicit Euler: gravity into velocity, then velocity into position.
    final gx = gravity.x * dt, gy = gravity.y * dt, gz = gravity.z * dt;
    final n = storage.aliveCount;
    for (var i = 0; i < n; i++) {
      storage.velX[i] += gx;
      storage.velY[i] += gy;
      storage.velZ[i] += gz;
      storage.posX[i] += storage.velX[i] * dt;
      storage.posY[i] += storage.velY[i] * dt;
      storage.posZ[i] += storage.velZ[i] * dt;
    }

    // Age and reap expired particles (reverse so swap-with-last is safe).
    for (var i = storage.aliveCount - 1; i >= 0; i--) {
      storage.age[i] += dt;
      if (storage.age[i] >= storage.lifetime[i]) {
        storage.kill(i);
      }
    }

    _systemTime += dt;
  }

  void _initParticle(int index) {
    final s = storage;
    s.random01[index] = _random.nextDouble();
    s.age[index] = 0.0;

    // The shape sets position and a unit emission direction.
    shape.sample(s, index);

    var life = lifetime.sample(0.0, s.randomFor(index, _saltLifetime));
    if (life < _minLifetime) life = _minLifetime;
    s.lifetime[index] = life;

    // Scale the unit direction by start speed to get launch velocity.
    final speed = startSpeed.sample(0.0, s.randomFor(index, _saltSpeed));
    s.velX[index] *= speed;
    s.velY[index] *= speed;
    s.velZ[index] *= speed;

    final size = startSize.sample(0.0, s.randomFor(index, _saltSize));
    s.size[index] = size;
    s.baseSize[index] = size;

    s.rotation[index] = startRotation.sample(
      0.0,
      s.randomFor(index, _saltRotation),
    );
    s.angularVelocity[index] = startAngularVelocity.sample(
      0.0,
      s.randomFor(index, _saltAngularVelocity),
    );

    final c = startColor.sample(0.0, s.randomFor(index, _saltColor), _tmpColor);
    s.colorR[index] = c.x;
    s.colorG[index] = c.y;
    s.colorB[index] = c.z;
    s.colorA[index] = c.w;

    // Spawn-phase modules can refine the birth state.
    for (final module in modules) {
      module.spawn(s, index);
    }
  }
}
