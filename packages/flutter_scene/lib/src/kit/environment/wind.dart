/// One wind, read by everything the weather touches.
///
/// A storm is not a sky effect plus a rain effect plus a tree effect. It is
/// one wind, and every one of those things is a different thing the same wind
/// is doing. Before this each of them drifted on its own constant, so turning
/// a scene from a breeze into a gale meant editing a cloud scroll, a rain
/// module, and a snow module, and they could disagree -- clouds running east
/// over rain falling west, which no viewer can name but everyone can feel.
///
/// The gust is what makes it read as weather rather than as a fan. A steady
/// vector is uncanny: real wind rises and falls, and the rise and fall is
/// shared, so a gust that leans the rain leans the clouds at the same moment.
library;

import 'dart:math' as math;

import 'package:vector_math/vector_math.dart' as vm;

/// A wind: a steady direction and speed, plus the gust riding on it.
///
/// Advance it once a frame with [advance] and read [velocity]. It is a plain
/// value holder on purpose -- the thing that drives it and the things that
/// read it are components that have no way to reach each other, and a shared
/// object is a cheaper connection than a lookup.
/// {@category Gameplay kit}
class Wind {
  Wind({
    vm.Vector2? direction,
    this.speed = 3.0,
    this.gustAmplitude = 0.35,
    this.gustFrequency = 0.15,
    this.seed = 1337,
  }) : direction = (direction ?? vm.Vector2(1, 0.25))..normalize();

  /// The scene's wind, for the common case of one weather system in one
  /// world.
  ///
  /// A [WindComponent] with no wind of its own drives this, and a
  /// [WindModule] with none reads it, so an author who never thinks about
  /// wiring gets rain that leans the way the clouds are going. A scene that
  /// needs two -- an indoor volume and an outdoor one -- gives each its own
  /// [Wind] and passes it explicitly.
  static final Wind ambient = Wind();

  /// Where the wind is going, on the ground plane. Normalized.
  final vm.Vector2 direction;

  /// Steady speed in world units per second.
  double speed;

  /// How far the gust swings the speed, as a fraction of [speed].
  ///
  /// At `0` the wind is a constant, which reads as a fan. At `1` it drops to
  /// nothing and doubles, which is a squall.
  double gustAmplitude;

  /// How often the gust cycles, in hertz. Low is a slow swell; high is a
  /// choppy day.
  double gustFrequency;

  /// Which gust pattern this wind follows. Two winds with different seeds
  /// gust at different moments.
  final int seed;

  /// Seconds of wind so far. Set it for a deterministic replay.
  double time = 0;

  /// The current speed including the gust, never negative: a gust may still
  /// the wind but does not reverse it.
  double get gustedSpeed {
    final gust = 1.0 + gustAmplitude * _gust(time);
    final value = speed * gust;
    return value < 0 ? 0 : value;
  }

  /// The current wind velocity, in world space, on the XZ plane.
  vm.Vector3 get velocity {
    final magnitude = gustedSpeed;
    return vm.Vector3(direction.x * magnitude, 0, direction.y * magnitude);
  }

  /// Where the wind is in its gust cycle, `-1` to `1`.
  double get gust => _gust(time);

  /// Advances the gust by [deltaSeconds].
  void advance(double deltaSeconds) {
    if (deltaSeconds > 0) time += deltaSeconds;
  }

  /// Points the wind along [heading], which is normalized in place.
  void setDirection(vm.Vector2 heading) {
    if (heading.length2 < 1e-12) return;
    direction
      ..setFrom(heading)
      ..normalize();
  }

  /// The gust shape: two sines at incommensurate rates, so it never settles
  /// into an audible loop the way one sine does.
  double _gust(double t) {
    final phase = (seed % 997) * 0.031;
    final slow = math.sin(t * gustFrequency * 2 * math.pi + phase);
    final fast = math.sin(t * gustFrequency * 5.13 * 2 * math.pi + phase * 1.7);
    return slow * 0.72 + fast * 0.28;
  }
}
