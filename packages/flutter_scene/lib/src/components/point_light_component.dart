import 'package:vector_math/vector_math.dart';

import 'package:flutter_scene/src/components/component.dart';
import 'package:flutter_scene/src/light.dart';

/// An engine [Component] that places a [PointLight] in the scene.
///
/// While the owning node is part of a live scene, the component registers its
/// light with the scene's render layer so the renderer can find it, and
/// unregisters it when the node leaves the scene.
///
/// The light's world position is the owning node's world-space translation,
/// so moving the node moves the light.
/// {@category Scene graph}
class PointLightComponent extends Component {
  /// Creates a component that lights the scene with [light].
  PointLightComponent(this.light);

  /// The light this component contributes.
  PointLight light;

  @override
  void onMount() {
    node.internalRenderScene?.addPointLight(this);
  }

  @override
  void onUnmount() {
    // Guard on attachment, not mount state: Component.unmount clears the
    // mounted flag before invoking onUnmount, and the owning node's render
    // scene is still reachable during teardown (mirrors MeshComponent).
    if (isAttached) {
      node.internalRenderScene?.removePointLight(this);
    }
  }

  /// The light's world-space position: the owning node's world-space
  /// translation.
  Vector3 get worldPosition => node.globalTransform.getTranslation();
}
