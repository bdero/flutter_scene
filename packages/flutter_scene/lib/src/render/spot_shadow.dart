import 'package:vector_math/vector_math.dart';

import 'package:flutter_scene/src/components/spot_light_component.dart';

/// The most spot lights that can cast a shadow at once. Each takes a tile in
/// the shared shadow atlas and a perspective depth pass, so the count is
/// capped; spots past the budget shade unshadowed. Kept small deliberately
/// (shadowed local lights are expensive, especially on mobile).
const int kMaxSpotShadows = 4;

/// The shadow-casting spots selected for a frame, in slot order (a spot's slot
/// is its index here, matching its shadow atlas tile and its matrix). All tiles
/// share one resolution and bias, taken from the first caster (per-spot shadow
/// parameters are a future refinement).
class SpotShadowFrame {
  SpotShadowFrame({
    required this.casters,
    required this.matrices,
    required this.tileResolution,
    required this.depthBias,
    required this.normalBias,
    required this.softness,
  });

  /// The shadow-casting spot components, index = slot.
  final List<SpotLightComponent> casters;

  /// World -> spot-clip matrix per caster (parallel to [casters]).
  final List<Matrix4> matrices;

  final int tileResolution;
  final double depthBias;
  final double normalBias;
  final double softness;

  /// The slot assigned to [component] (its atlas tile and matrix), or -1 when
  /// it is not a shadow caster this frame.
  int slotOf(SpotLightComponent component) => casters.indexOf(component);
}

/// Selects up to [kMaxSpotShadows] shadow-casting spots from [spots] and
/// computes their world -> spot-clip matrices, or null when none cast a shadow.
SpotShadowFrame? collectSpotShadows(List<SpotLightComponent> spots) {
  final casters = <SpotLightComponent>[];
  for (final spot in spots) {
    if (!spot.light.castsShadow) continue;
    casters.add(spot);
    if (casters.length >= kMaxSpotShadows) break;
  }
  if (casters.isEmpty) return null;

  final matrices = [
    for (final caster in casters)
      caster.light.shadowViewProjection(
        caster.worldPosition,
        caster.worldDirection,
      ),
  ];
  final first = casters.first.light;
  return SpotShadowFrame(
    casters: casters,
    matrices: matrices,
    tileResolution: first.shadowMapResolution,
    depthBias: first.shadowDepthBias,
    normalBias: first.shadowNormalBias,
    softness: first.shadowSoftness,
  );
}
