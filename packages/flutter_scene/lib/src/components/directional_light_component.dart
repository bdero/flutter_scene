import 'package:flutter/foundation.dart' show internal;
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
/// Light travels along the owning node's local +Z axis. The node's world-space
/// rotation aims the light; its translation and scale have no effect.
/// {@category Scene graph}
class DirectionalLightComponent extends Component {
  /// Creates a component that lights the scene with [light].
  DirectionalLightComponent(this.light)
    : _usesLightDirection = false,
      _localDirection = null;

  /// Creates the component backing the scene-level light convenience.
  ///
  /// Unlike an authored component, this reads [DirectionalLight.direction]
  /// directly because it has no independently rotatable node.
  @internal
  DirectionalLightComponent.fromLightDirection(this.light)
    : _usesLightDirection = true,
      _localDirection = null;

  /// Creates a component inside a runtime coordinate boundary.
  @internal
  DirectionalLightComponent.fromLocalDirection(this.light, Vector3 direction)
    : _usesLightDirection = false,
      _localDirection = direction.clone();

  /// The light this component contributes.
  DirectionalLight light;

  final bool _usesLightDirection;
  final Vector3? _localDirection;

  static final Vector3 _localForward = Vector3(0, 0, 1);

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

  /// The light's world-space travel direction.
  Vector3 get worldDirection {
    if (_usesLightDirection) return light.direction;
    final localDirection = _localDirection;
    if (localDirection != null) {
      return node.globalTransform.rotate3(localDirection.clone()).normalized();
    }
    return node.globalTransform.getRotation() * _localForward;
  }

  /// Clones carry the light, sharing the light object like other clone
  /// payloads (geometry, materials).
  @override
  Component? cloneFor(Node cloneOwner) {
    if (_usesLightDirection) {
      return DirectionalLightComponent.fromLightDirection(light);
    }
    final localDirection = _localDirection;
    return localDirection == null
        ? DirectionalLightComponent(light)
        : DirectionalLightComponent.fromLocalDirection(light, localDirection);
  }
}
