import 'package:flutter/foundation.dart';
import 'package:flutter_scene/src/components/component.dart';
import 'package:flutter_scene/src/mesh.dart';
import 'package:flutter_scene/src/node.dart';
import 'package:flutter_scene/src/render/render_scene.dart';

/// An engine [Component] that draws a [Mesh].
///
/// While the owning node is part of a live scene, a `MeshComponent`
/// registers one [RenderItem] per [MeshPrimitive] with the scene's flat
/// render layer, and refreshes those items each frame.
///
/// A node's [Node.mesh] getter and setter are a convenience over the
/// node's first `MeshComponent`.
/// {@category Scene graph}
class MeshComponent extends Component {
  /// Creates a component that draws [mesh].
  MeshComponent(this._mesh);

  Mesh _mesh;

  /// The mesh this component draws.
  ///
  /// Assigning a different mesh re-registers the render items when the
  /// owning node is part of a live scene.
  Mesh get mesh => _mesh;
  set mesh(Mesh value) {
    if (identical(_mesh, value)) return;
    _unregisterRenderItems();
    _mesh = value;
    _registerRenderItems();
    if (isAttached) node.markBoundsDirty();
  }

  // One render item per mesh primitive. Empty while the component is not
  // mounted.
  final List<RenderItem> _renderItems = [];

  /// The render items registered for this component's mesh primitives, empty
  /// while not mounted. Exposed so a subclass (the LOD component) can tag the
  /// items it just registered.
  @protected
  List<RenderItem> get renderItems => _renderItems;

  @override
  void onMount() => _registerRenderItems();

  @override
  void onUnmount() => _unregisterRenderItems();

  void _registerRenderItems() {
    if (!isMounted) return;
    final renderScene = node.internalRenderScene;
    if (renderScene == null) return;
    for (final primitive in _mesh.primitives) {
      final item = RenderItem(
        geometry: primitive.geometry,
        material: primitive.material,
      )..sourceNode = node;
      _renderItems.add(item);
      renderScene.add(item);
    }
    onRenderItemsRegistered();
  }

  /// Called after this component registers its render items, on mount and on
  /// every re-registration ([mesh] assignment, [refreshMaterials]).
  ///
  /// Subclasses that decorate the registered items (the LOD component tags
  /// them with its selection) must do so here rather than in [onMount], or
  /// the decoration is lost when the items are rebuilt.
  @protected
  void onRenderItemsRegistered() {}

  /// Re-registers the render items so a changed [MeshPrimitive.material]
  /// takes effect.
  ///
  /// Render items capture the primitive's material when registered, so
  /// mutating `primitive.material` on a mounted mesh is invisible until the
  /// items are rebuilt. Re-registering also re-buckets items whose new
  /// material changes translucency. No-op while unmounted (mounting
  /// registers fresh items).
  @internal
  void refreshMaterials() {
    _unregisterRenderItems();
    _registerRenderItems();
  }

  void _unregisterRenderItems() {
    // Guard on attachment, not mount state: [Component.unmount] clears
    // the mounted flag before invoking [onUnmount], so checking
    // isMounted here would skip removal during teardown and leave the
    // render items in the scene forever. The owning node's render scene
    // is still reachable until after every component has unmounted.
    if (isAttached) {
      final renderScene = node.internalRenderScene;
      if (renderScene != null) {
        for (final item in _renderItems) {
          renderScene.remove(item);
        }
      }
    }
    _renderItems.clear();
  }

  /// Refreshes this component's render items from the owning node's
  /// current world transform, skin, and cull state. Called once per frame
  /// by the scene pre-pass while the node is visible.
  @internal
  void refreshRenderItems() {
    if (_renderItems.isEmpty) return;
    final worldTransform = node.globalTransform;
    final windingFlipped = node.windingFlipped;

    // A skinned node uploads its joint matrices once per frame; both
    // render passes then sample the same joints texture.
    final skin = node.skin;
    if (skin != null) {
      final jointsTexture = skin.getJointsTexture();
      final jointsTextureWidth = skin.getTextureWidth();
      for (final item in _renderItems) {
        item.geometry.setJointsTexture(jointsTexture, jointsTextureWidth);
      }
    }

    final renderScene = node.internalRenderScene;
    final frustumCulled = node.frustumCulled;
    final layers = node.layers;
    final highlightColor = node.highlightColor;
    for (final item in _renderItems) {
      item.visible = true;
      final frustumCulledChanged = item.frustumCulled != frustumCulled;
      item.frustumCulled = frustumCulled;
      item.layers = layers;
      item.worldTransform.setFrom(worldTransform);
      item.windingFlipped = windingFlipped;
      item.shadowStatic = node.shadowStatic;
      item.highlightColor = highlightColor;

      final wasBounded = item.worldBounds != null;
      final boundsChanged = item.refreshWorldBounds();
      final isBounded = item.worldBounds != null;

      // A toggled cull flag or a bounded/unbounded transition changes the
      // BVH membership and needs a rebuild; a plain move only needs a
      // refit.
      if (frustumCulledChanged || wasBounded != isBounded) {
        renderScene?.markBvhStructureDirty();
      } else if (boundsChanged && item.frustumCulled) {
        renderScene?.markBvhBoundsDirty();
      }
    }
  }

  /// Keeps this component's render items out of the render passes.
  /// Called by the scene pre-pass while the owning node is hidden.
  @internal
  void hideRenderItems() {
    for (final item in _renderItems) {
      item.visible = false;
    }
  }
}
