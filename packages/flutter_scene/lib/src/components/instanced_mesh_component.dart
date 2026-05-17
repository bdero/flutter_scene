import 'package:flutter/foundation.dart';
import 'package:flutter_scene/src/components/component.dart';
import 'package:flutter_scene/src/instanced_mesh.dart';
import 'package:flutter_scene/src/render/render_scene.dart';

/// An engine [Component] that draws an [InstancedMesh].
///
/// While the owning node is part of a live scene, this component
/// registers a single [RenderItem] for the whole instanced mesh and
/// refreshes it each frame. The render passes draw every instance from
/// that one item.
class InstancedMeshComponent extends Component {
  /// Creates a component that draws [instancedMesh].
  InstancedMeshComponent(this.instancedMesh);

  /// The instanced mesh this component draws.
  final InstancedMesh instancedMesh;

  RenderItem? _renderItem;

  @override
  void onMount() {
    final renderScene = node.internalRenderScene;
    if (renderScene == null) return;
    final item = RenderItem(
      geometry: instancedMesh.geometry,
      material: instancedMesh.material,
    );
    _renderItem = item;
    renderScene.add(item);
  }

  @override
  void onUnmount() {
    final item = _renderItem;
    if (item != null) {
      node.internalRenderScene?.remove(item);
      _renderItem = null;
    }
  }

  /// Refreshes this component's render item from the owning node's
  /// transform and cull state and the current instance list. Called once
  /// per frame by the scene pre-pass while the node is visible.
  @internal
  void refreshRenderItem() {
    final item = _renderItem;
    if (item == null) return;
    item.visible = true;
    final frustumCulled = node.frustumCulled;
    final frustumCulledChanged = item.frustumCulled != frustumCulled;
    item.frustumCulled = frustumCulled;
    item.worldTransform.setFrom(node.globalTransform);
    item.instanceTransforms = instancedMesh.instances;
    item.instanceBounds = instancedMesh.aggregateBounds;

    final wasBounded = item.worldBounds != null;
    final boundsChanged = item.refreshWorldBounds();
    final isBounded = item.worldBounds != null;

    // A toggled cull flag or a bounded/unbounded transition changes the
    // BVH membership and needs a rebuild; a plain move only needs a
    // refit.
    final renderScene = node.internalRenderScene;
    if (frustumCulledChanged || wasBounded != isBounded) {
      renderScene?.markBvhStructureDirty();
    } else if (boundsChanged && item.frustumCulled) {
      renderScene?.markBvhBoundsDirty();
    }
  }

  /// Keeps this component's render item out of the render passes. Called
  /// by the scene pre-pass while the owning node is hidden.
  @internal
  void hideRenderItem() {
    _renderItem?.visible = false;
  }
}
