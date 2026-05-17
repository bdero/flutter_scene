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
      );
      _renderItems.add(item);
      renderScene.add(item);
    }
  }

  void _unregisterRenderItems() {
    if (isMounted) {
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

    final frustumCulled = node.frustumCulled;
    for (final item in _renderItems) {
      item.visible = true;
      item.frustumCulled = frustumCulled;
      item.worldTransform.setFrom(worldTransform);
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
