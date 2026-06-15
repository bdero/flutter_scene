import 'package:vector_math/vector_math.dart';

import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:flutter_scene/src/components/directional_light_component.dart';
import 'package:flutter_scene/src/geometry/geometry.dart';
import 'package:flutter_scene/src/material/material.dart';
import 'package:flutter_scene/src/render/bvh.dart';
import 'package:flutter_scene/src/render/render_layers.dart';

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

  /// The owning node's render layers (a 32-bit bitmask), refreshed each
  /// frame. A render pass skips this item when its view's layer mask does
  /// not intersect (`layers & layerMask == 0`).
  int layers = kRenderLayerAll;

  /// Whether the owning node's transform reverses triangle winding (a mirror
  /// up the chain). Refreshed each frame; the encoder flips cull winding when
  /// set so mirrored nodes don't render inside-out.
  bool windingFlipped = false;

  /// World-space transform, refreshed each frame from the owning node.
  final Matrix4 worldTransform = Matrix4.identity();

  /// The owning node's highlight color (linear RGBA), or null when the node
  /// is not highlighted. Refreshed each frame; the selection-outline pass
  /// draws only highlighted items, using this as the mask color.
  Vector4? highlightColor;

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

  /// The directional lights contributed by mounted
  /// [DirectionalLightComponent]s, in registration order. The renderer
  /// currently shades the first; the rest are collected for future
  /// multi-light support.
  final List<DirectionalLightComponent> directionalLights = [];

  /// Registers [light] as an active directional light. Called by a
  /// [DirectionalLightComponent] when its owning node mounts.
  void addDirectionalLight(DirectionalLightComponent light) {
    directionalLights.add(light);
  }

  /// The mounted widget components, in registration order. `SceneView`
  /// listens to [widgetComponentsChanged] and hosts each component's widget
  /// subtree invisibly.
  final List<Object> widgetComponents = [];

  /// Bumped whenever [widgetComponents] changes.
  final ValueNotifier<int> widgetComponentsChanged = ValueNotifier<int>(0);

  /// Registers a mounted widget component (typed as Object to keep this
  /// render-layer file free of a widgets dependency).
  void addWidgetComponent(Object component) {
    widgetComponents.add(component);
    widgetComponentsChanged.value++;
  }

  /// Unregisters an unmounted widget component.
  void removeWidgetComponent(Object component) {
    widgetComponents.remove(component);
    widgetComponentsChanged.value++;
  }

  /// Unregisters [light]. Called when its owning node unmounts.
  void removeDirectionalLight(DirectionalLightComponent light) {
    directionalLights.remove(light);
  }

  Bvh _bvh = Bvh.build([]);
  final List<RenderItem> _alwaysVisible = [];

  // The BVH needs a full rebuild: an item was added or removed, or an
  // item's BVH membership changed.
  bool _structureDirty = true;

  // A bounded item moved; the BVH can refit instead of rebuilding.
  bool _boundsDirty = false;

  void add(RenderItem item) {
    items.add(item);
    _structureDirty = true;
  }

  void remove(RenderItem item) {
    items.remove(item);
    _structureDirty = true;
  }

  /// Flags the BVH for a full rebuild. Called when an item's BVH
  /// membership changed (its `frustumCulled` flag toggled, or it became
  /// bounded or unbounded).
  void markBvhStructureDirty() {
    _structureDirty = true;
  }

  /// Flags the BVH for a refit. Called when a bounded item moved but the
  /// item set and membership are unchanged.
  void markBvhBoundsDirty() {
    _boundsDirty = true;
  }

  /// Brings the spatial structure up to date with the current items.
  /// Call once per frame, after the pre-pass and before the render
  /// passes. Rebuilds on a structural change, otherwise refits when an
  /// item moved, otherwise does nothing.
  void rebuildIfDirty() {
    if (_structureDirty) {
      _structureDirty = false;
      _boundsDirty = false;
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
    } else if (_boundsDirty) {
      _boundsDirty = false;
      _bvh.refit();
    }
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
