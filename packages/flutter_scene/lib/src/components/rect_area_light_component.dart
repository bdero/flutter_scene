import 'package:vector_math/vector_math.dart';

import 'package:flutter_scene/src/components/component.dart';
import 'package:flutter_scene/src/light.dart';
import 'package:flutter_scene/src/node.dart';

/// An engine [Component] that places a [RectAreaLight] in the scene.
///
/// The rectangle lies in the owning node's local XY plane and emits along
/// local +Z; the node's world transform positions and aims it.
/// {@category Scene graph}
class RectAreaLightComponent extends Component {
  /// Creates a component that lights the scene with [light].
  RectAreaLightComponent(this.light);

  /// The light this component contributes.
  RectAreaLight light;

  @override
  void onMount() {
    node.internalRenderScene?.addRectAreaLight(this);
  }

  @override
  void onUnmount() {
    // Guard on attachment, not mount state: Component.unmount clears the
    // mounted flag before invoking onUnmount, and the owning node's render
    // scene is still reachable during teardown (mirrors MeshComponent).
    if (isAttached) {
      node.internalRenderScene?.removeRectAreaLight(this);
    }
  }

  /// The panel center: the owning node's world-space translation.
  Vector3 get worldPosition => node.globalTransform.getTranslation();

  /// The panel's world-space width axis (the node's rotated local +X),
  /// unit length.
  Vector3 get worldRight =>
      (node.globalTransform.getRotation() * Vector3(1, 0, 0))..normalize();

  /// The panel's world-space height axis (the node's rotated local +Y),
  /// unit length.
  Vector3 get worldUp =>
      (node.globalTransform.getRotation() * Vector3(0, 1, 0))..normalize();

  /// Clones carry the light, sharing the light object like other clone
  /// payloads (geometry, materials).
  @override
  Component? cloneFor(Node cloneOwner) => RectAreaLightComponent(light);
}
