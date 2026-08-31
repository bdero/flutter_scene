import 'package:vector_math/vector_math.dart';

import 'package:flutter_scene/src/components/point_light_component.dart';
import 'package:flutter_scene/src/light.dart' show ShadowCasterFaces;

// TODO(point-shadow-cache): point faces re-render every caster every frame;
// route static casters through cached tiles like the directional cascades.
/// The most point lights that can cast a shadow at once. Each costs six
/// perspective depth passes and two tiles in the shared shadow atlas (the six
/// quarter-resolution cube faces pack four to a tile), so the count is capped;
/// point lights past the budget shade unshadowed.
const int kMaxPointShadows = 4;

/// Cube faces per point-shadow caster.
const int kPointShadowFaces = 6;

/// Atlas tiles per point-shadow caster: six faces at half the tile edge, four
/// to a tile.
const int kPointShadowTilesPerLight = 2;

/// The shadow-casting point lights selected for a frame, in slot order (a
/// caster's slot is its index here; its two atlas tiles follow the spot tiles
/// at `slot * kPointShadowTilesPerLight`). Face rendering shares one caster
/// face mode, taken from the first caster; every other shadow parameter is
/// per-light (each rides its own params-texture row).
class PointShadowFrame {
  PointShadowFrame({
    required this.casters,
    required this.casterFaces,
    required this.casterChannelMasks,
  });

  /// The shadow-casting point components, index = slot.
  final List<PointLightComponent> casters;

  final ShadowCasterFaces casterFaces;

  /// Each caster's shadow-caster channel mask (parallel to [casters]); a node
  /// renders into that light's faces only when its light channels intersect.
  final List<int> casterChannelMasks;

  /// World -> clip matrix for face [face] of the caster in [slot].
  Matrix4 faceMatrix(int slot, int face) => casters[slot].light
      .pointShadowFaceViewProjection(casters[slot].worldPosition, face);

  /// The slot assigned to [component], or -1 when it is not a shadow caster
  /// this frame.
  int slotOf(PointLightComponent component) => casters.indexOf(component);
}

/// Selects up to [kMaxPointShadows] shadow-casting point lights from [points],
/// or null when none cast a shadow.
PointShadowFrame? collectPointShadows(List<PointLightComponent> points) {
  final casters = <PointLightComponent>[];
  for (final point in points) {
    if (!point.light.castsShadow) continue;
    casters.add(point);
    if (casters.length >= kMaxPointShadows) break;
  }
  if (casters.isEmpty) return null;
  return PointShadowFrame(
    casters: casters,
    casterFaces: casters.first.light.shadowCasterFaces,
    casterChannelMasks: [
      for (final caster in casters) caster.light.shadowCasterChannelMask,
    ],
  );
}
