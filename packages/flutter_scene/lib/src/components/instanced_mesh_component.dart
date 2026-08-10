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
/// {@category Scene graph}
class InstancedMeshComponent extends Component {
  /// Creates a component that draws [instancedMesh].
  InstancedMeshComponent(this.instancedMesh);

  /// The instanced mesh this component draws.
  final InstancedMesh instancedMesh;

  RenderItem? _renderItem;
  int _worldTransformVersion = -1;
  int _instanceRevision = -1;
  int _geometryBoundsVersion = -1;

  @override
  void onMount() {
    final renderScene = node.internalRenderScene;
    if (renderScene == null) return;
    final item = RenderItem(
      geometry: instancedMesh.geometry,
      material: instancedMesh.material,
    )..sourceNode = node;
    _renderItem = item;
    renderScene.add(item);
  }

  @override
  void onUnmount() {
    final item = _renderItem;
    if (item != null) {
      node.internalRenderScene?.remove(item);
      _renderItem = null;
      _worldTransformVersion = -1;
      _instanceRevision = -1;
      _geometryBoundsVersion = -1;
    }
  }

  /// Refreshes this component's render item from the owning node's
  /// transform and cull state and the current instance list. Called once
  /// per frame by the scene pre-pass while the node is visible.
  @internal
  void refreshRenderItem() {
    final item = _renderItem;
    if (item == null) return;
    final materialCandidateChanged =
        !item.visible || item.layers != node.layers;
    item.visible = true;
    final frustumCulled = node.frustumCulled;
    final frustumCulledChanged = item.frustumCulled != frustumCulled;
    item.frustumCulled = frustumCulled;
    item.layers = node.layers;
    final worldTransform = node.globalTransform;
    final worldTransformVersion = node.worldTransformVersion;
    final instanceRevision = instancedMesh.revision;
    final geometryBoundsVersion = instancedMesh.geometry.localBoundsVersion;
    final boundsChangedByInput =
        worldTransformVersion != _worldTransformVersion ||
        instanceRevision != _instanceRevision ||
        geometryBoundsVersion != _geometryBoundsVersion;
    final staticShadowChanged =
        (item.visible != true ||
            item.shadowStatic != node.shadowStatic ||
            item.castsShadows != node.castsShadows ||
            boundsChangedByInput) &&
        (item.shadowStatic || node.shadowStatic) &&
        (item.castsShadows || node.castsShadows);
    if (worldTransformVersion != _worldTransformVersion) {
      item.worldTransform.setFrom(worldTransform);
    }
    item.refreshWinding(node.windingFlipped);
    item.shadowStatic = node.shadowStatic;
    item.castsShadows = node.castsShadows;
    item.instanceTransforms = instancedMesh.instances;
    item.instanceColors = instancedMesh.colors;
    item.instanceWindingFlipped = instancedMesh.windingFlipped;
    item.cullInstances = instancedMesh.cullInstances;
    item.sortTransparentInstances = instancedMesh.sortTransparentInstances;
    if (staticShadowChanged) {
      node.internalRenderScene?.markStaticShadowDirty();
    }
    if (instanceRevision != _instanceRevision ||
        geometryBoundsVersion != _geometryBoundsVersion) {
      item.instanceBounds = instancedMesh.aggregateBounds;
    }
    if (boundsChangedByInput) {
      item.refreshInstanceData();
    }

    final wasBounded = item.worldBounds != null;
    final boundsChanged = boundsChangedByInput
        ? item.refreshWorldBounds()
        : false;
    final isBounded = item.worldBounds != null;

    // A toggled cull flag or a bounded/unbounded transition changes the
    // BVH membership and needs a rebuild; a plain move only needs a
    // refit.
    final renderScene = node.internalRenderScene;
    if (materialCandidateChanged) {
      renderScene?.markMaterialCandidatesDirty();
    }
    if (frustumCulledChanged || wasBounded != isBounded) {
      renderScene?.markBvhStructureDirty();
    } else if (boundsChanged && item.frustumCulled) {
      renderScene?.markBvhBoundsDirty();
    }
    _worldTransformVersion = worldTransformVersion;
    _instanceRevision = instanceRevision;
    _geometryBoundsVersion = geometryBoundsVersion;
  }

  /// Keeps this component's render item out of the render passes. Called
  /// by the scene pre-pass while the owning node is hidden.
  @internal
  void hideRenderItem() {
    final item = _renderItem;
    if (item == null) return;
    if (item.visible && item.shadowStatic && item.castsShadows) {
      node.internalRenderScene?.markStaticShadowDirty();
    }
    if (item.visible) {
      node.internalRenderScene?.markMaterialCandidatesDirty();
    }
    item.visible = false;
  }
}
