import 'package:vector_math/vector_math.dart';

import 'package:flutter_scene/src/geometry/geometry.dart';
import 'package:flutter_scene/src/material/material.dart';

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
}

/// The flat list of [RenderItem]s the renderer iterates.
///
/// Owned by a `Scene`. The node graph registers and unregisters items as
/// mesh-bearing nodes are mounted into and out of the scene.
class RenderScene {
  /// Every registered render item, in no particular order.
  final List<RenderItem> items = [];

  void add(RenderItem item) => items.add(item);

  void remove(RenderItem item) => items.remove(item);
}
