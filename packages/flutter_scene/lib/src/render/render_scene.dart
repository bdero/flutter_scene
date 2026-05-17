import 'package:vector_math/vector_math.dart';

import 'package:flutter_scene/src/geometry/geometry.dart';
import 'package:flutter_scene/src/material/material.dart';
import 'package:flutter_scene/src/render/bvh.dart';

/// One drawable primitive in the flat render layer.
///
/// A [RenderItem] is created when a mesh-bearing node is mounted into a
/// scene and lives until that node is unmounted or its mesh changes. The
/// scene pre-pass refreshes [visible], [frustumCulled], and
/// [worldTransform] each frame; the render passes iterate the flat
/// [RenderScene] and never walk the node tree.
class RenderItem {
  RenderItem({required this.geometry, required this.material});

  /// Vertex and index data for this primitive.
  final Geometry geometry;

  /// Shader and per-material parameters.
  final Material material;

  /// Whether the owning node and all of its ancestors are visible.
  /// Refreshed each frame by the scene pre-pass.
  bool visible = false;

  /// Mirrors the owning node's frustum-cull opt-in, refreshed each frame.
  bool frustumCulled = true;

  /// World-space transform, refreshed each frame from the owning node.
  final Matrix4 worldTransform = Matrix4.identity();

  /// Per-instance model transforms, or `null` for a non-instanced item.
  ///
  /// When set, this item draws [geometry] / [material] once per entry,
  /// each at `worldTransform * transform`. Refreshed each frame from the
  /// owning [InstancedMeshComponent].
  List<Matrix4>? instanceTransforms;

  /// Node-local aggregate AABB covering every instance, used to
  /// frustum-cull an instanced item as a single unit.
  ///
  /// `null` means the instanced item is unbounded and always drawn.
  /// Ignored for non-instanced items.
  Aabb3? instanceBounds;

  /// The local-space AABB this item is frustum-culled against, or `null`
  /// when it should be treated as always visible.
  ///
  /// An instanced item uses its [instanceBounds]; a regular item uses its
  /// geometry's local bounds.
  Aabb3? get cullBounds =>
      instanceTransforms != null ? instanceBounds : geometry.localBounds;

  /// World-space AABB ([cullBounds] transformed by [worldTransform]), or
  /// `null` when the item is unbounded.
  ///
  /// Refreshed each frame by [refreshWorldBounds] and consumed by the
  /// scene's spatial structure.
  Aabb3? worldBounds;

  // Reused across [refreshWorldBounds] calls so a steady-state refresh
  // allocates nothing.
  static final Aabb3 _worldBoundsScratch = Aabb3();

  /// Recomputes [worldBounds] from [cullBounds] and [worldTransform], and
  /// returns whether the value changed since the previous call.
  ///
  /// Call after refreshing [worldTransform]. The owning component uses
  /// the return value to know when the spatial structure is stale.
  bool refreshWorldBounds() {
    final local = cullBounds;
    if (local == null) {
      if (worldBounds == null) return false;
      worldBounds = null;
      return true;
    }
    _worldBoundsScratch
      ..copyFrom(local)
      ..transform(worldTransform);
    final current = worldBounds;
    if (current == null) {
      worldBounds = Aabb3.copy(_worldBoundsScratch);
      return true;
    }
    if (current.min == _worldBoundsScratch.min &&
        current.max == _worldBoundsScratch.max) {
      return false;
    }
    current.copyFrom(_worldBoundsScratch);
    return true;
  }
}

/// The retained render layer for a `Scene`: every [RenderItem], plus a
/// spatial structure the render passes cull against.
///
/// The node graph registers and unregisters items as mesh-bearing nodes
/// are mounted into and out of the scene. Bounded items are placed in a
/// [Bvh]; unbounded items (no [RenderItem.worldBounds], or
/// [RenderItem.frustumCulled] off) are always visited.
class RenderScene {
  /// Every registered render item, in no particular order.
  final List<RenderItem> items = [];

  Bvh _bvh = Bvh.build([]);
  final List<RenderItem> _alwaysVisible = [];
  bool _bvhDirty = true;

  void add(RenderItem item) {
    items.add(item);
    _bvhDirty = true;
  }

  void remove(RenderItem item) {
    items.remove(item);
    _bvhDirty = true;
  }

  /// Flags the spatial structure stale. Called by the components when an
  /// item's world bounds or cull opt-in changed during the pre-pass.
  void markBvhDirty() {
    _bvhDirty = true;
  }

  /// Rebuilds the spatial structure when anything changed since the last
  /// build. Call once per frame, after the pre-pass and before the
  /// render passes.
  void rebuildIfDirty() {
    if (!_bvhDirty) return;
    _bvhDirty = false;
    _alwaysVisible.clear();
    final bounded = <RenderItem>[];
    for (final item in items) {
      if (item.frustumCulled && item.worldBounds != null) {
        bounded.add(item);
      } else {
        _alwaysVisible.add(item);
      }
    }
    _bvh = Bvh.build(bounded);
  }

  /// Visits every item potentially visible to [frustum]: the bounded
  /// items whose world AABB intersects it, plus every always-visible
  /// item.
  void cull(Frustum frustum, void Function(RenderItem) visit) {
    _bvh.query(frustum, visit);
    for (final item in _alwaysVisible) {
      visit(item);
    }
  }
}
