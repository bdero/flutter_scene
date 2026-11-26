import 'dart:math' as math;

import 'package:vector_math/vector_math.dart';

import 'package:flutter_scene/src/components/spot_light_component.dart';
import 'package:flutter_scene/src/render/shadow_caster_selection.dart';

/// The most spot lights that can cast a shadow at once. Each takes a tile in
/// the shared shadow atlas and a perspective depth pass, so the count is
/// capped; spots past the budget shade unshadowed. Kept small deliberately
/// (shadowed local lights are expensive, especially on mobile).
const int kMaxSpotShadows = 4;

/// The shadow-casting spots selected for a frame, in slot order (a spot's slot
/// is its index here, matching its shadow atlas tile and its matrix). Each
/// spot's resolution, bias, softness, and caster faces are its own light's.
class SpotShadowFrame {
  SpotShadowFrame({
    required this.casters,
    required this.matrices,
    required this.casterChannelMasks,
    required this.dropped,
  });

  /// The shadow-casting spot components, index = slot.
  final List<SpotLightComponent> casters;

  /// World -> spot-clip matrix per caster (parallel to [casters]).
  final List<Matrix4> matrices;

  /// Each caster's shadow-caster channel mask (parallel to [casters]); a node
  /// renders into that spot's tile only when its light channels intersect.
  final List<int> casterChannelMasks;

  /// In-view spots that asked for a shadow but got no slot.
  final List<SpotLightComponent> dropped;

  /// The slot assigned to [component] (its atlas tile and matrix), or -1 when
  /// it is not a shadow caster this frame.
  int slotOf(SpotLightComponent component) => casters.indexOf(component);
}

/// Selects up to [kMaxSpotShadows] shadow-casting spots from [spots] (see
/// [selectShadowCasters] for how [views] and [previous] pick them) and
/// computes their world -> spot-clip matrices, or null when none cast a shadow.
SpotShadowFrame? collectSpotShadows(
  List<SpotLightComponent> spots, {
  ShadowViewVolumes? views,
  Set<Object>? previous,
}) {
  final selection = selectShadowCasters(
    spots,
    budget: kMaxSpotShadows,
    castsShadow: (spot) => spot.light.castsShadow,
    bounds: spotInfluenceBounds,
    views: views,
    previous: previous,
  );
  final casters = selection.casters;
  if (casters.isEmpty) return null;

  final matrices = [
    for (final caster in casters)
      caster.light.shadowViewProjection(
        caster.worldPosition,
        caster.worldDirection,
      ),
  ];
  return SpotShadowFrame(
    casters: casters,
    matrices: matrices,
    casterChannelMasks: [
      for (final caster in casters) caster.light.shadowCasterChannelMask,
    ],
    dropped: selection.dropped,
  );
}

/// The smallest sphere holding [spot]'s lit cone (the sector within its range
/// and outer cone angle), or a zero radius when its range is unbounded.
Sphere spotInfluenceBounds(SpotLightComponent spot) {
  final apex = spot.worldPosition;
  final range = spot.light.range;
  if (range <= 0.0) return Sphere.centerRadius(apex, 0.0);
  final angle = spot.light.outerConeAngle;
  if (angle >= math.pi / 2) return Sphere.centerRadius(apex, range);
  final axis = spot.worldDirection.normalized();
  // A wide cone is bounded by its cap's rim; a narrow one by the sphere
  // through its apex and rim.
  if (angle > math.pi / 4) {
    return Sphere.centerRadius(
      apex + axis * (range * math.cos(angle)),
      range * math.sin(angle),
    );
  }
  final radius = range / (2.0 * math.cos(angle));
  return Sphere.centerRadius(apex + axis * radius, radius);
}
