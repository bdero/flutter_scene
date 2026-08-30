import 'package:flutter/foundation.dart';
import 'package:flutter_scene/src/components/component.dart';
import 'package:flutter_scene/src/material/material.dart';
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
  /// Assigning a different mesh re-registers render items when its primitive
  /// geometry changes. Material-only changes retain the existing items.
  Mesh get mesh => _mesh;
  set mesh(Mesh value) {
    if (identical(_mesh, value)) return;
    if (_canRetainRenderItems(value)) {
      _mesh = value;
      _refreshRetainedMaterials();
      return;
    }
    _unregisterRenderItems();
    _mesh = value;
    _registerRenderItems();
    if (isAttached) node.markBoundsDirty();
  }

  bool _canRetainRenderItems(Mesh value) {
    if (_mesh.primitives.length != value.primitives.length) return false;
    for (var i = 0; i < value.primitives.length; i++) {
      if (!identical(
        _mesh.primitives[i].geometry,
        value.primitives[i].geometry,
      )) {
        return false;
      }
    }
    return true;
  }

  void _refreshRetainedMaterials() {
    if (_renderItems.length != _mesh.primitives.length) return;
    var staticShadowChanged = false;
    for (var i = 0; i < _renderItems.length; i++) {
      final item = _renderItems[i];
      final material = _mesh.primitives[i].material;
      if (identical(item.material, material)) continue;
      if (!setEquals(item.material.sceneInputs, material.sceneInputs)) {
        markMaterialSceneInputsChanged();
      }
      item.material = material;
      staticShadowChanged |= item.shadowStatic && item.castsShadows;
    }
    if (staticShadowChanged) {
      node.internalRenderScene?.markStaticShadowDirty();
    }
  }

  // One render item per mesh primitive. Empty while the component is not
  // mounted.
  final List<RenderItem> _renderItems = [];
  final List<int> _boundsVersions = [];
  int _worldTransformVersion = -1;

  /// The render items registered for this component's mesh primitives, empty
  /// while not mounted. Exposed so a subclass (the LOD component) can tag the
  /// items it just registered.
  @protected
  List<RenderItem> get renderItems => _renderItems;

  /// Morph weights the scene realizer recorded for this node instance
  /// (glTF `node.weights` overriding the mesh defaults), applied to the
  /// owning node when the component mounts.
  @internal
  List<double>? initialMorphWeights;

  @override
  void onMount() {
    _registerRenderItems();
    final weights = initialMorphWeights;
    if (weights != null && node.internalMorphWeights != null) {
      node.setMorphWeights(weights);
    }
  }

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
      _boundsVersions.add(-1);
      renderScene.add(item);
    }
    onRenderItemsRegistered();
  }

  /// Called after this component registers its render items, on mount and on
  /// geometry-changing [mesh] assignments.
  ///
  /// Subclasses that decorate the registered items (the LOD component tags
  /// them with its selection) must do so here rather than in [onMount], or
  /// the decoration is lost when the items are rebuilt.
  @protected
  void onRenderItemsRegistered() {}

  /// Updates render items after a [MeshPrimitive.material] change.
  ///
  /// No-op while unmounted since mounting registers fresh items.
  @internal
  void refreshMaterials() {
    _refreshRetainedMaterials();
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
    _boundsVersions.clear();
    _worldTransformVersion = -1;
  }

  /// Refreshes this component's render items from the owning node's
  /// current world transform, skin, and cull state. Called once per frame
  /// by the scene pre-pass while the node is visible.
  @internal
  void refreshRenderItems() {
    if (_renderItems.isEmpty) return;
    final worldTransformVersion = node.worldTransformVersion;
    var staticStateUnchanged =
        node.skin == null &&
        node.internalMorphWeights == null &&
        worldTransformVersion == _worldTransformVersion;
    for (
      var index = 0;
      staticStateUnchanged && index < _renderItems.length;
      index++
    ) {
      final item = _renderItems[index];
      final primitive = _mesh.primitives[index];
      staticStateUnchanged =
          item.jointsTexture == null &&
          item.morphWeights == null &&
          item.visible == !item.material.drawsNothing &&
          item.primitiveVisible == primitive.visible &&
          item.frustumCulled == node.frustumCulled &&
          item.layers == node.layers &&
          item.lightChannelMask == node.lightChannelMask &&
          item.shadowStatic == node.shadowStatic &&
          item.castsShadows == (primitive.castsShadow && node.castsShadows) &&
          item.highlightColor == node.highlightColor &&
          _boundsVersions[index] == item.geometry.localBoundsVersion;
    }
    if (staticStateUnchanged) {
      return;
    }
    final worldTransform = node.globalTransform;
    final transformChanged = worldTransformVersion != _worldTransformVersion;
    final windingFlipped = node.windingFlipped;

    // A skinned node uploads its joint matrices once per frame. The texture
    // rides on the render items, not the geometry, so nodes sharing one
    // skinned geometry (clones) each draw with their own skeleton; the
    // render passes apply it to the geometry per draw.
    final skin = node.skin;
    final jointsTexture = skin?.getJointsTexture();
    final jointsTextureWidth = skin?.getTextureWidth() ?? 0;

    final renderScene = node.internalRenderScene;
    final frustumCulled = node.frustumCulled;
    final layers = node.layers;
    final lightChannelMask = node.lightChannelMask;
    final highlightColor = node.highlightColor;
    for (var index = 0; index < _renderItems.length; index++) {
      final item = _renderItems[index];
      final primitive = _mesh.primitives[index];
      final effectiveCastsShadows = primitive.castsShadow && node.castsShadows;
      // A material can declare itself draw-less for the frame (the shadow
      // catcher at zero intensity); its item then joins no pass at all.
      final visible = !item.material.drawsNothing;
      final staticShadowChanged =
          (item.visible != visible ||
              item.shadowStatic != node.shadowStatic ||
              item.castsShadows != effectiveCastsShadows ||
              item.lightChannelMask != lightChannelMask ||
              transformChanged) &&
          (item.shadowStatic || node.shadowStatic) &&
          (item.castsShadows || effectiveCastsShadows);
      item.visible = visible;
      item.primitiveVisible = primitive.visible;
      final frustumCulledChanged = item.frustumCulled != frustumCulled;
      item.frustumCulled = frustumCulled;
      item.layers = layers;
      item.lightChannelMask = lightChannelMask;
      final isMoving =
          transformChanged || (skin != null && jointsTexture != null);
      item.isMoving = isMoving;
      if (transformChanged) {
        item.previousWorldTransform.setFrom(item.worldTransform);
        item.worldTransform.setFrom(worldTransform);
      }
      item.refreshWinding(windingFlipped);
      item.shadowStatic = node.shadowStatic;
      item.castsShadows = effectiveCastsShadows;
      item.shadowCastingMode = node.shadowCastingMode;
      item.highlightColor = highlightColor;
      if (skin != null) {
        item.previousJointsTexture = skin.getPreviousJointsTexture();
        item.jointsTexture = jointsTexture;
        item.jointsTextureWidth = jointsTextureWidth;
      }
      item.morphWeights = node.internalMorphWeights;
      if (staticShadowChanged) renderScene?.markStaticShadowDirty();

      final boundsVersion = item.geometry.localBoundsVersion;
      final geometryBoundsChanged = _boundsVersions[index] != boundsVersion;
      _boundsVersions[index] = boundsVersion;
      final wasBounded = item.worldBounds != null;
      final boundsChanged = transformChanged || geometryBoundsChanged
          ? item.refreshWorldBounds()
          : false;
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
    _worldTransformVersion = worldTransformVersion;
  }

  /// Keeps this component's render items out of the render passes.
  /// Called by the scene pre-pass while the owning node is hidden.
  @internal
  void hideRenderItems() {
    for (final item in _renderItems) {
      if (item.visible && item.shadowStatic && item.castsShadows) {
        node.internalRenderScene?.markStaticShadowDirty();
      }
      item.visible = false;
    }
  }
}
