import 'package:vector_math/vector_math.dart';

import 'package:flutter_scene/src/render/bvh.dart';
import 'package:flutter_scene/src/render/render_scene.dart';

/// A punctual light reduced to what culling needs: its row [index] in the
/// shared light-parameter buffer and its world-space influence [bounds].
///
/// A null [bounds] means infinite influence (a directional light, or a point or
/// spot light with no range), so the light reaches every item and is never
/// culled.
class CullableLight {
  const CullableLight(this.index, this.bounds);

  final int index;
  final Aabb3? bounds;
}

/// The world-space AABB a point or spot light at [worldPosition] with [range]
/// can influence, or null when [range] is not positive (infinite influence).
///
/// A spot light is bounded by the same sphere as a point light of its range; a
/// tighter cone bound is a future refinement.
Aabb3? lightInfluenceBounds(Vector3 worldPosition, double range) {
  if (range <= 0.0) return null;
  final r = Vector3.all(range);
  return Aabb3.minMax(worldPosition - r, worldPosition + r);
}

/// The result of a cull: the flattened light-index buffer (each item's slice is
/// `[offset, offset + count)`, written onto the items) and whether any item had
/// more lights than [maxPerItem] and dropped the excess.
class LightCullResult {
  const LightCullResult(this.indices, this.overflowed);

  final List<int> indices;
  final bool overflowed;
}

/// Assigns each item in [items] the punctual [lights] that reach it, writing
/// [RenderItem.lightListOffset]/[RenderItem.lightListCount] onto each and
/// returning the flattened index buffer the light-index texture is built from.
///
/// Infinite-influence lights reach every item. Ranged lights are scattered onto
/// the items their influence AABB overlaps using [bvh] (which holds the bounded
/// items); unbounded items (no [RenderItem.worldBounds]) cannot be culled, so
/// they conservatively receive every light. Each item's list is capped at
/// [maxPerItem]; the excess is dropped and flagged in the result.
LightCullResult assignLightsToItems({
  required List<RenderItem> items,
  required Bvh bvh,
  required List<CullableLight> lights,
  required int maxPerItem,
}) {
  for (final item in items) {
    item.lightScratch.clear();
  }

  final infinite = <int>[
    for (final light in lights)
      if (light.bounds == null) light.index,
  ];
  final unbounded = <RenderItem>[
    for (final item in items)
      if (item.worldBounds == null) item,
  ];

  // Infinite-influence lights reach every item.
  if (infinite.isNotEmpty) {
    for (final item in items) {
      item.lightScratch.addAll(infinite);
    }
  }

  // Ranged lights: scatter onto bounded items via the BVH, and onto the (few)
  // unbounded items unconditionally since they cannot be culled.
  for (final light in lights) {
    final bounds = light.bounds;
    if (bounds == null) continue;
    bvh.queryAabb(bounds, (item) => item.lightScratch.add(light.index));
    for (final item in unbounded) {
      item.lightScratch.add(light.index);
    }
  }

  final flat = <int>[];
  var overflowed = false;
  for (final item in items) {
    final scratch = item.lightScratch;
    var count = scratch.length;
    if (count > maxPerItem) {
      count = maxPerItem;
      overflowed = true;
    }
    item.lightListOffset = flat.length;
    item.lightListCount = count;
    for (var i = 0; i < count; i++) {
      flat.add(scratch[i]);
    }
  }
  return LightCullResult(flat, overflowed);
}
