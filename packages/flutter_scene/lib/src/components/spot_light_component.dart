import 'package:vector_math/vector_math.dart';

import 'package:flutter_scene/src/components/component.dart';
import 'package:flutter_scene/src/light.dart';

/// An engine [Component] that places a [SpotLight] in the scene.
///
/// While the owning node is part of a live scene, the component registers its
/// light with the scene's render layer so the renderer can find it, and
/// unregisters it when the node leaves the scene.
///
/// The light's world position is the owning node's world-space translation,
/// and its aim is the node's world-space rotation applied to the light's
/// local [SpotLight.direction], so re-orienting the node aims the cone.
/// {@category Scene graph}
class SpotLightComponent extends Component {
  /// Creates a component that lights the scene with [light].
  SpotLightComponent(this.light);

  /// The light this component contributes. Its [SpotLight.direction] is read
  /// in the owning node's local space; [worldDirection] is the world result.
  SpotLight light;

  @override
  void onMount() {
    node.internalRenderScene?.addSpotLight(this);
  }

  @override
  void onUnmount() {
    // Guard on attachment, not mount state (mirrors MeshComponent): the
    // render scene is still reachable during teardown after the mounted flag
    // is cleared.
    if (isAttached) {
      node.internalRenderScene?.removeSpotLight(this);
    }
  }

  /// The light's world-space position: the owning node's world-space
  /// translation.
  Vector3 get worldPosition => node.globalTransform.getTranslation();

  /// The cone's world-space aim: the owning node's world-space rotation
  /// applied to the light's local [SpotLight.direction]. Need not be unit
  /// length (the shader normalizes it).
  Vector3 get worldDirection =>
      node.globalTransform.getRotation() * light.direction;
}
