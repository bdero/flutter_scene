import 'dart:math' as math;

import 'package:vector_math/vector_math.dart';

import 'package:flutter_scene/src/particles/particle_storage.dart';
import 'package:flutter_scene/src/particles/vec3_distribution.dart';

/// Decides where a freshly spawned particle starts and which way it initially
/// heads.
///
/// [sample] writes the spawn position into the storage's `pos*` columns and a
/// **unit** emission direction into the `vel*` columns at [index]; the owning
/// system scales that direction by the start speed to produce the launch
/// velocity. Positions and directions are in the emitter's local space.
///
/// Shapes draw their randomness from [ParticleStorage.randomFor] with salts in
/// the `20+` range, kept disjoint from the salts the system uses for its other
/// spawn properties so values do not correlate.
abstract class EmitterShape {
  /// Creates an emitter shape.
  const EmitterShape();

  /// Writes the spawn position and unit emission direction for particle
  /// [index] into [storage].
  void sample(ParticleStorage storage, int index);
}

const int _saltA = 20;
const int _saltB = 21;
const int _saltC = 22;
const int _saltD = 23;

/// Emits every particle from the local origin along a single [direction].
class PointShape extends EmitterShape {
  /// Creates a point emitter heading along [direction] (default +Y).
  PointShape({Vector3? direction})
    : direction = (direction?.clone() ?? Vector3(0, 1, 0))..normalize();

  /// The unit emission direction shared by every particle.
  final Vector3 direction;

  @override
  void sample(ParticleStorage storage, int index) {
    storage.posX[index] = 0.0;
    storage.posY[index] = 0.0;
    storage.posZ[index] = 0.0;
    storage.velX[index] = direction.x;
    storage.velY[index] = direction.y;
    storage.velZ[index] = direction.z;
  }
}

/// Emits particles from a sphere (or its surface, or a hemisphere), each headed
/// radially outward.
///
/// With [surfaceOnly] false (the default) positions fill the volume uniformly
/// (a cube-root correction keeps the density even); with it true they land on
/// the shell. [hemisphere] restricts both position and direction to the +Y
/// half. A zero [radius] degenerates to a point emitting in uniformly random
/// directions.
class SphereShape extends EmitterShape {
  /// Creates a sphere emitter of the given [radius].
  const SphereShape({
    this.radius = 1.0,
    this.surfaceOnly = false,
    this.hemisphere = false,
  }) : assert(radius >= 0);

  /// The sphere radius.
  final double radius;

  /// Whether to spawn only on the shell rather than throughout the volume.
  final bool surfaceOnly;

  /// Whether to restrict to the +Y half (hemisphere).
  final bool hemisphere;

  @override
  void sample(ParticleStorage storage, int index) {
    final u = storage.randomFor(index, _saltA);
    final v = storage.randomFor(index, _saltB);
    // A uniform direction on the unit sphere (or +Y hemisphere).
    final y = hemisphere ? u : (2.0 * u - 1.0);
    final ring = math.sqrt(math.max(0.0, 1.0 - y * y));
    final phi = 2.0 * math.pi * v;
    final dx = ring * math.cos(phi);
    final dy = y;
    final dz = ring * math.sin(phi);

    var magnitude = radius;
    if (!surfaceOnly && radius > 0.0) {
      // Cube-root keeps the volume density uniform rather than centre-heavy.
      final w = storage.randomFor(index, _saltC);
      magnitude = radius * math.pow(w, 1.0 / 3.0).toDouble();
    }

    storage.posX[index] = dx * magnitude;
    storage.posY[index] = dy * magnitude;
    storage.posZ[index] = dz * magnitude;
    storage.velX[index] = dx;
    storage.velY[index] = dy;
    storage.velZ[index] = dz;
  }
}

/// Emits particles from a disc of [radius] in the local XZ plane, each headed
/// within a cone of half-angle [angle] about +Y.
///
/// The disc is sampled area-uniform and the directions are sampled uniform over
/// the cone's solid angle, so neither the centre nor the axis is over-weighted.
class ConeShape extends EmitterShape {
  /// Creates a cone emitter with base [radius] and cone half-[angle] (radians).
  const ConeShape({this.angle = 0.5, this.radius = 0.0})
    : assert(angle >= 0),
      assert(radius >= 0);

  /// The cone half-angle in radians (the spread away from +Y).
  final double angle;

  /// The base disc radius.
  final double radius;

  @override
  void sample(ParticleStorage storage, int index) {
    // Area-uniform disc position in the XZ plane.
    final rr = radius * math.sqrt(storage.randomFor(index, _saltA));
    final theta = 2.0 * math.pi * storage.randomFor(index, _saltB);
    storage.posX[index] = rr * math.cos(theta);
    storage.posY[index] = 0.0;
    storage.posZ[index] = rr * math.sin(theta);

    // Solid-angle-uniform direction within the cone about +Y.
    final cosT =
        1.0 - storage.randomFor(index, _saltC) * (1.0 - math.cos(angle));
    final sinT = math.sqrt(math.max(0.0, 1.0 - cosT * cosT));
    final phi = 2.0 * math.pi * storage.randomFor(index, _saltD);
    storage.velX[index] = sinT * math.cos(phi);
    storage.velY[index] = cosT;
    storage.velZ[index] = sinT * math.sin(phi);
  }
}

/// Emits particles uniformly inside an axis-aligned box, each headed along a
/// shared [direction].
class BoxShape extends EmitterShape {
  /// Creates a box emitter spanning `[-halfExtents, halfExtents]`, heading
  /// along [direction] (default +Y).
  BoxShape({Vector3? halfExtents, Vector3? direction})
    : direction = (direction?.clone() ?? Vector3(0, 1, 0))..normalize(),
      _box = UniformBoxVec3(
        (halfExtents?.clone() ?? Vector3.all(0.5))..scale(-1.0),
        halfExtents?.clone() ?? Vector3.all(0.5),
      );

  /// The unit emission direction shared by every particle.
  final Vector3 direction;

  final UniformBoxVec3 _box;
  final Vector3 _tmp = Vector3.zero();

  @override
  void sample(ParticleStorage storage, int index) {
    _box.sample(storage, index, _saltA, _tmp);
    storage.posX[index] = _tmp.x;
    storage.posY[index] = _tmp.y;
    storage.posZ[index] = _tmp.z;
    storage.velX[index] = direction.x;
    storage.velY[index] = direction.y;
    storage.velZ[index] = direction.z;
  }
}
