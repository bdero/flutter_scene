/// Spatial environment volumes: regions that override the scene look, blended
/// by camera position so the environment and post-processing transition as the
/// camera moves between areas (the Unity Volume / Unreal Post Process Volume
/// model).
library;

import 'dart:math' as math;

import 'package:vector_math/vector_math.dart';

import 'package:flutter_scene/src/environment_settings.dart';

/// The shape of an [EnvironmentVolume]'s region.
/// {@category Lighting and environment}
sealed class EnvironmentVolumeBounds {
  const EnvironmentVolumeBounds();

  /// Distance from [point] to the boundary surface in world units, `0` when
  /// [point] is inside.
  double distanceTo(Vector3 point);
}

/// An axis-aligned box region.
/// {@category Lighting and environment}
class BoxVolumeBounds extends EnvironmentVolumeBounds {
  BoxVolumeBounds({required this.center, required this.halfExtents});

  /// World-space center.
  Vector3 center;

  /// Half the box size along each axis.
  Vector3 halfExtents;

  @override
  double distanceTo(Vector3 point) {
    final dx = (point.x - center.x).abs() - halfExtents.x;
    final dy = (point.y - center.y).abs() - halfExtents.y;
    final dz = (point.z - center.z).abs() - halfExtents.z;
    final ox = dx > 0 ? dx : 0.0;
    final oy = dy > 0 ? dy : 0.0;
    final oz = dz > 0 ? dz : 0.0;
    return math.sqrt(ox * ox + oy * oy + oz * oz);
  }
}

/// A sphere region.
/// {@category Lighting and environment}
class SphereVolumeBounds extends EnvironmentVolumeBounds {
  SphereVolumeBounds({required this.center, required this.radius});

  /// World-space center.
  Vector3 center;

  /// Sphere radius.
  double radius;

  @override
  double distanceTo(Vector3 point) {
    final d = (point - center).length - radius;
    return d > 0 ? d : 0.0;
  }
}

/// A region that overrides the scene look with its [settings], contributing by
/// camera position.
///
/// A global volume ([bounds] null) always contributes; a local one contributes
/// fully inside its [bounds] and fades to nothing across [blendDistance] outside
/// the surface, scaled by [weight]. Overlapping volumes apply in [priority]
/// order (higher last, so it wins). Assign a list to `Scene.environmentVolumes`
/// over a `Scene.baseEnvironment`.
/// {@category Lighting and environment}
class EnvironmentVolume {
  EnvironmentVolume({
    required this.settings,
    this.bounds,
    this.priority = 0.0,
    this.weight = 1.0,
    this.blendDistance = 0.0,
  });

  /// The look this volume blends toward where it is in effect.
  EnvironmentSettings settings;

  /// The region, or null for a global (unbounded) volume.
  EnvironmentVolumeBounds? bounds;

  /// Blend order; higher priority volumes are applied later (on top).
  double priority;

  /// Master contribution scale, `0`..`1`.
  double weight;

  /// World-space fade band outside the [bounds] surface over which the
  /// contribution falls from full to zero. `0` is a hard edge.
  double blendDistance;

  /// This volume's coverage at [cameraPosition], `0`..`1` (before [weight]).
  double coverage(Vector3 cameraPosition) {
    final b = bounds;
    if (b == null) return 1.0;
    final dist = b.distanceTo(cameraPosition);
    if (blendDistance <= 0) return dist <= 0 ? 1.0 : 0.0;
    final c = 1.0 - dist / blendDistance;
    return c.clamp(0.0, 1.0);
  }
}

/// Blends [volumes] over [base] for a camera at [cameraPosition].
///
/// Starts from [base] and applies each volume whose contribution is non-zero in
/// ascending [EnvironmentVolume.priority] order, lerping toward the volume's
/// settings by `coverage * weight`. Continuous fields interpolate; discrete
/// fields (the environment/sky bindings, tone-mapping operator, effect flags)
/// switch when a volume's contribution passes half (see [EnvironmentSettings]).
/// {@category Lighting and environment}
EnvironmentSettings blendEnvironmentVolumes(
  EnvironmentSettings base,
  List<EnvironmentVolume> volumes,
  Vector3 cameraPosition,
) {
  final contributions = <(EnvironmentVolume, double)>[];
  for (final volume in volumes) {
    final w = volume.coverage(cameraPosition) * volume.weight;
    if (w > 0) contributions.add((volume, w.clamp(0.0, 1.0)));
  }
  contributions.sort((a, b) => a.$1.priority.compareTo(b.$1.priority));

  var result = base;
  for (final (volume, w) in contributions) {
    result = EnvironmentSettings.lerp(result, volume.settings, w);
  }
  return result;
}
