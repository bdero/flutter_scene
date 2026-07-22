import 'package:vector_math/vector_math.dart';

import 'package:flutter_scene/src/components/component.dart';
import 'package:flutter_scene/src/light.dart';
import 'package:flutter_scene/src/node.dart';

/// An engine [Component] that places a [DirectionalLight] in the scene.
///
/// While the owning node is part of a live scene, the component registers
/// its light with the scene's render layer so the renderer can find it,
/// and unregisters it when the node leaves the scene.
///
/// The light's travel direction is the owning node's world-space
/// orientation applied to the light's [DirectionalLight.direction] (read
/// as a node-local direction), so re-orienting the node aims the light.
/// With an unrotated node the world direction equals the light's own
/// [DirectionalLight.direction].
///
/// The renderer currently shades a single directional light (the first one
/// registered); additional directional lights are collected but not yet
/// shaded.
/// {@category Scene graph}
// TODO(lighting): shade multiple directional lights once the material
// shader supports more than one.
class DirectionalLightComponent extends Component {
  /// Creates a component that lights the scene with [light].
  DirectionalLightComponent(this.light);

  /// The light this component contributes. Its
  /// [DirectionalLight.direction] is read in the owning node's local
  /// space; [worldDirection] is the world-space result.
  DirectionalLight light;

  @override
  void onMount() {
    node.internalRenderScene?.addDirectionalLight(this);
  }

  @override
  void onUnmount() {
    // Guard on attachment, not mount state: Component.unmount clears the
    // mounted flag before invoking onUnmount, and the owning node's render
    // scene is still reachable during teardown (mirrors MeshComponent).
    if (isAttached) {
      node.internalRenderScene?.removeDirectionalLight(this);
    }
  }

  /// The light's world-space travel direction: the owning node's
  /// world-space rotation applied to the light's local
  /// [DirectionalLight.direction]. Need not be unit length (the shader and
  /// the shadow-cascade fit both normalize it).
  Vector3 get worldDirection =>
      node.globalTransform.getRotation() * light.direction;

  /// Clones carry the light, sharing the light object like other clone
  /// payloads (geometry, materials).
  @override
  Component? cloneFor(Node cloneOwner) => DirectionalLightComponent(light);
}
