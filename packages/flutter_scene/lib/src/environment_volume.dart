/// Spatial environment volumes: regions that override the scene look, blended
/// by camera position so the environment and post-processing transition as the
/// camera moves between areas (the Unity Volume / Unreal Post Process Volume
/// model).
library;

import 'dart:math' as math;

import 'package:vector_math/vector_math.dart';

import 'package:flutter_scene/src/environment_settings.dart';
import 'package:flutter_scene/src/material/environment.dart';

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

/// One resolved environment contribution to blend over the base: a look and how
/// strongly it applies (`weight` already folds in coverage and master weight),
/// ordered by `priority`. The engine builds these from manual
/// [EnvironmentVolume]s and from environment-volume components alike.
class EnvironmentContribution {
  /// Creates a contribution.
  EnvironmentContribution(this.settings, this.weight, this.priority);

  /// The look this contributes toward.
  final EnvironmentSettings settings;

  /// The effective `0`..`1` strength (coverage times weight).
  final double weight;

  /// Blend order; higher applies later (on top).
  final double priority;
}

/// Folds [contributions] over [base] in ascending priority, lerping toward each
/// by its weight. Continuous fields interpolate; discrete fields switch when a
/// contribution passes half (see [EnvironmentSettings]).
EnvironmentSettings blendEnvironmentContributions(
  EnvironmentSettings base,
  List<EnvironmentContribution> contributions,
) {
  final active = [
    for (final c in contributions)
      if (c.weight > 0) c,
  ]..sort((a, b) => a.priority.compareTo(b.priority));
  var result = base;
  for (final c in active) {
    result = EnvironmentSettings.lerp(result, c.settings, c.weight.clamp(0, 1));
  }
  return result;
}

/// The dominant pair of image-based-lighting environments and the factor to
/// blend between them, from [contributions] over [base], so reflections and
/// ambient cross-fade rather than switching at the midpoint.
///
/// Returns `(primary, secondary, blend)`: sample `primary` and `secondary` and
/// mix toward `secondary` by `blend`. `secondary` is null (and `blend` 0) when
/// a single environment is in effect. Only static environments cross-fade; a
/// sky-lit look's lighting comes from a per-frame bake owning a single
/// environment, so when a contributing look is sky-lit this returns no
/// secondary and the discrete switch stands. See `notes` `TODO(dual-sky-bake)`.
({EnvironmentMap? primary, EnvironmentMap? secondary, double blend})
resolveEnvironmentCrossfadeFromContributions(
  EnvironmentSettings base,
  List<EnvironmentContribution> contributions,
) {
  bool isStatic(EnvironmentSettings s) =>
      s.skyEnvironment == null && s.environment != null;
  if (!isStatic(base)) {
    return (primary: base.environment, secondary: null, blend: 0.0);
  }

  final active = [
    for (final c in contributions)
      if (c.weight > 0) c,
  ]..sort((a, b) => a.priority.compareTo(b.priority));

  var primary = base.environment;
  EnvironmentMap? secondary;
  var blend = 0.0;
  for (final c in active) {
    if (!isStatic(c.settings)) {
      return (primary: base.environment, secondary: null, blend: 0.0);
    }
    final env = c.settings.environment;
    if (identical(env, primary)) continue;
    // Collapse the running pair to its dominant member, then start a new fade.
    primary = blend >= 0.5 ? (secondary ?? primary) : primary;
    secondary = env;
    blend = c.weight.clamp(0.0, 1.0);
  }
  return (primary: primary, secondary: secondary, blend: blend);
}

List<EnvironmentContribution> _volumeContributions(
  List<EnvironmentVolume> volumes,
  Vector3 cameraPosition,
) => [
  for (final v in volumes)
    EnvironmentContribution(
      v.settings,
      (v.coverage(cameraPosition) * v.weight).clamp(0.0, 1.0),
      v.priority,
    ),
];

/// Blends [volumes] over [base] for a camera at [cameraPosition]. A thin
/// wrapper over [blendEnvironmentContributions] for the manual volume API.
/// {@category Lighting and environment}
EnvironmentSettings blendEnvironmentVolumes(
  EnvironmentSettings base,
  List<EnvironmentVolume> volumes,
  Vector3 cameraPosition,
) => blendEnvironmentContributions(
  base,
  _volumeContributions(volumes, cameraPosition),
);

/// The cross-fade pair for [volumes] over [base] at [cameraPosition]. A thin
/// wrapper over [resolveEnvironmentCrossfadeFromContributions].
({EnvironmentMap? primary, EnvironmentMap? secondary, double blend})
resolveEnvironmentCrossfade(
  EnvironmentSettings base,
  List<EnvironmentVolume> volumes,
  Vector3 cameraPosition,
) => resolveEnvironmentCrossfadeFromContributions(
  base,
  _volumeContributions(volumes, cameraPosition),
);
