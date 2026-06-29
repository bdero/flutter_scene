import 'package:vector_math/vector_math.dart';

import 'package:flutter_scene/src/particles/particle_storage.dart';

/// A vector value generator sampled per particle, the vector analog of the
/// scalar `FloatDistribution`.
///
/// Unlike the scalar and color distributions (which sample from a single stored
/// random), a vector needs up to three independent randoms (one per axis). It
/// therefore samples directly against the storage and a particle [index],
/// deriving its randoms through [ParticleStorage.randomFor] with the supplied
/// [saltBase] (and `saltBase + 1`, `saltBase + 2`). Callers pass disjoint salt
/// bases so different vector properties of the same particle do not correlate.
sealed class Vec3Distribution {
  const Vec3Distribution();

  /// Writes the vector for particle [index] into [out] (allocated when null)
  /// and returns it. Per-axis randomness is drawn from
  /// [ParticleStorage.randomFor] starting at [saltBase].
  Vector3 sample(
    ParticleStorage storage,
    int index,
    int saltBase, [
    Vector3? out,
  ]);
}

/// A [Vec3Distribution] that is [value] for every particle.
class ConstantVec3 extends Vec3Distribution {
  /// Creates a constant vector distribution.
  const ConstantVec3(this.value);

  /// The constant vector.
  final Vector3 value;

  @override
  Vector3 sample(
    ParticleStorage storage,
    int index,
    int saltBase, [
    Vector3? out,
  ]) => (out ?? Vector3.zero())..setFrom(value);
}

/// A [Vec3Distribution] that picks a vector uniformly inside the axis-aligned
/// box `[min, max]` per particle, each axis from its own random stream.
class UniformBoxVec3 extends Vec3Distribution {
  /// Creates a uniform-box distribution over the corners [min] and [max].
  const UniformBoxVec3(this.min, this.max);

  /// The box corners; [min] is returned when every axis random is `0`.
  final Vector3 min, max;

  @override
  Vector3 sample(
    ParticleStorage storage,
    int index,
    int saltBase, [
    Vector3? out,
  ]) {
    final result = out ?? Vector3.zero();
    final rx = storage.randomFor(index, saltBase);
    final ry = storage.randomFor(index, saltBase + 1);
    final rz = storage.randomFor(index, saltBase + 2);
    result.setValues(
      min.x + (max.x - min.x) * rx,
      min.y + (max.y - min.y) * ry,
      min.z + (max.z - min.z) * rz,
    );
    return result;
  }
}
