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
/// rotation aims the light; its translation and scale have no effect. The
/// default constructor checks [DirectionalLight.direction] only when the
/// component is created. Later mutations of that field remain ignored.
/// {@category Scene graph}
class DirectionalLightComponent extends Component {
  /// Creates a component that lights the scene with [light].
  DirectionalLightComponent(this.light)
    : assert(
        _hasDefaultDirection(light),
        'DirectionalLight.direction is ignored by DirectionalLightComponent. '
        'Aim the owning node or use DirectionalLightComponent.aimed.',
      ),
      _usesLightDirection = false,
      _localDirection = null;

  /// Creates a component that travels along [localDirection].
  ///
  /// The owning node's rotation transforms this direction into world space.
  DirectionalLightComponent.aimed(this.light, Vector3 localDirection)
    : _usesLightDirection = false,
      _localDirection = localDirection.clone();

  DirectionalLightComponent._copy(
    this.light, {
    required bool usesLightDirection,
    Vector3? localDirection,
  }) : _usesLightDirection = usesLightDirection,
       _localDirection = localDirection?.clone();

  /// Creates the component backing the scene-level light convenience.
  ///
  /// Unlike an authored component, this reads [DirectionalLight.direction]
  /// directly because it has no independently rotatable node.
  @internal
  DirectionalLightComponent.fromLightDirection(this.light)
    : _usesLightDirection = true,
      _localDirection = null;

  /// The light this component contributes.
  DirectionalLight light;

  final bool _usesLightDirection;
  final Vector3? _localDirection;

  /// The fixed node-local travel direction set by [DirectionalLightComponent.aimed]
  /// (a copy), or null when the node's rotation aims the light.
  Vector3? get localDirection => _localDirection?.clone();

  static bool _hasDefaultDirection(DirectionalLight light) {
    final direction = light.direction;
    final expected = DirectionalLight.defaultDirection;
    return (direction.x - expected.x).abs() < 1e-6 &&
        (direction.y - expected.y).abs() < 1e-6 &&
        (direction.z - expected.z).abs() < 1e-6;
  }

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
    if (_usesLightDirection) return light.direction.normalized();
    final localDirection = _localDirection;
    if (localDirection != null) {
      return node.globalTransform.rotate3(localDirection.clone()).normalized();
    }
    return (node.globalTransform.getRotation() * Vector3(0, 0, 1))..normalize();
  }

  /// Clones carry the light, sharing the light object like other clone
  /// payloads (geometry, materials).
  @override
  Component? cloneFor(Node cloneOwner) {
    if (_usesLightDirection) {
      return DirectionalLightComponent.fromLightDirection(light);
    }
    final localDirection = _localDirection;
    return DirectionalLightComponent._copy(
      light,
      usesLightDirection: false,
      localDirection: localDirection,
    );
  }
}
