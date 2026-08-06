import 'package:vector_math/vector_math.dart';

import 'package:flutter_scene/src/render/bvh.dart';
import 'package:flutter_scene/src/render/render_scene.dart';

/// A punctual light reduced to what culling needs: its row [index] in the
/// shared light-parameter buffer, world-space influence [bounds], and optional
/// [worldPosition] used to choose the nearest lights when an item overflows its
/// light budget.
///
/// A null [bounds] means infinite influence (a directional light, or a point or
/// spot light with no range), so the light reaches every item and is never
/// culled. A null [worldPosition] identifies a directional light, which sorts
/// ahead of local lights because its influence is independent of distance.
class CullableLight {
  const CullableLight(this.index, this.bounds, {this.worldPosition});

  final int index;
  final Aabb3? bounds;
  final Vector3? worldPosition;
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
/// [maxPerItem]. Directional lights and the nearest local lights are retained;
/// the excess is dropped and flagged in the result.
LightCullResult assignLightsToItems({
  required List<RenderItem> items,
  required Bvh bvh,
  required List<CullableLight> lights,
  required int maxPerItem,
}) {
  if (lights.every(
    (light) => light.bounds == null && light.worldPosition == null,
  )) {
    final count = lights.length.clamp(0, maxPerItem);
    for (final item in items) {
      item.lightListOffset = 0;
      item.lightListCount = count;
    }
    return LightCullResult([
      for (var i = 0; i < count; i++) lights[i].index,
    ], lights.length > maxPerItem);
  }

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
  final lightsByIndex = <int, CullableLight>{
    for (final light in lights) light.index: light,
  };
  var overflowed = false;
  for (final item in items) {
    final scratch = item.lightScratch;
    var count = scratch.length;
    if (count > maxPerItem) {
      scratch.sort(
        (a, b) =>
            _compareLightsForItem(item, lightsByIndex[a]!, lightsByIndex[b]!),
      );
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

int _compareLightsForItem(RenderItem item, CullableLight a, CullableLight b) {
  final bounds = item.worldBounds;
  final aDistance = _distanceToItemSquared(item, bounds, a.worldPosition);
  final bDistance = _distanceToItemSquared(item, bounds, b.worldPosition);
  final distanceOrder = aDistance.compareTo(bDistance);
  if (distanceOrder != 0) return distanceOrder;

  // Lights inside or touching a large item's bounds all have zero distance.
  // Prefer the one nearest its center before falling back to row order.
  if (bounds != null && a.worldPosition != null && b.worldPosition != null) {
    final centerX = (bounds.min.x + bounds.max.x) * 0.5;
    final centerY = (bounds.min.y + bounds.max.y) * 0.5;
    final centerZ = (bounds.min.z + bounds.max.z) * 0.5;
    final aCenterDistance = _distanceSquared(
      a.worldPosition!,
      centerX,
      centerY,
      centerZ,
    );
    final bCenterDistance = _distanceSquared(
      b.worldPosition!,
      centerX,
      centerY,
      centerZ,
    );
    final centerOrder = aCenterDistance.compareTo(bCenterDistance);
    if (centerOrder != 0) return centerOrder;
  }
  return a.index.compareTo(b.index);
}

double _distanceToItemSquared(
  RenderItem item,
  Aabb3? bounds,
  Vector3? position,
) {
  // Directional lights have no position and must survive any local-light cap.
  if (position == null) return double.negativeInfinity;
  if (bounds == null) {
    final transform = item.worldTransform.storage;
    return _distanceSquared(
      position,
      transform[12],
      transform[13],
      transform[14],
    );
  }
  final dx = position.x < bounds.min.x
      ? bounds.min.x - position.x
      : position.x > bounds.max.x
      ? position.x - bounds.max.x
      : 0.0;
  final dy = position.y < bounds.min.y
      ? bounds.min.y - position.y
      : position.y > bounds.max.y
      ? position.y - bounds.max.y
      : 0.0;
  final dz = position.z < bounds.min.z
      ? bounds.min.z - position.z
      : position.z > bounds.max.z
      ? position.z - bounds.max.z
      : 0.0;
  return dx * dx + dy * dy + dz * dz;
}

double _distanceSquared(Vector3 position, double x, double y, double z) {
  final dx = position.x - x;
  final dy = position.y - y;
  final dz = position.z - z;
  return dx * dx + dy * dy + dz * dz;
}
