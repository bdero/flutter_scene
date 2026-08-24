import 'dart:math' as math;
import 'package:flutter_scene/src/camera.dart';
import 'package:vector_math/vector_math.dart' as vm;

/// Utility for computing camera framing transforms for scene nodes.
///
/// Computes a look-at transform placing a camera node so that a target bounding box
/// fills the view. For standalone camera instances, prefer [PerspectiveCamera.framing].
/// {@category Gameplay kit}
class BoundsFraming {
  /// Computes a camera node world transform that frames [bounds] with [paddingFactor].
  ///
  /// The camera looks toward the bounds center from [viewDirection] (offset from center
  /// toward the eye, defaulting to `(0, 0, -1)` to match glTF front-facing orientation).
  /// The resulting matrix is oriented with +Z facing the target, matching `NodeCamera`.
  static vm.Matrix4 computeFramingTransform(
    vm.Aabb3 bounds,
    CameraProjection projection, {
    double paddingFactor = 1.25,
    vm.Vector3? viewDirection,
    vm.Vector3? upVector,
  }) {
    final center = bounds.center;
    final extents = (bounds.max - bounds.min) * 0.5;
    final radius = math.max(0.1, extents.length);

    final dir = (viewDirection ?? vm.Vector3(0.0, 0.0, -1.0)).normalized();
    var up = upVector ?? vm.Vector3(0.0, 1.0, 0.0);

    // Solve distance from projection FOV
    double distance;
    if (projection is PerspectiveProjection) {
      final halfFov = projection.fovRadiansY * 0.5;
      distance = (radius / math.sin(halfFov)) * paddingFactor;
    } else {
      distance = radius * 2.0 * paddingFactor;
    }

    final eye = center + dir * distance;
    final forward = (center - eye).normalized();
    if (up.cross(forward).length2 < 1e-6) {
      up = vm.Vector3(0, 0, 1);
    }
    final right = up.cross(forward).normalized();
    final actualUp = forward.cross(right).normalized();

    return vm.Matrix4.columns(
      vm.Vector4(right.x, right.y, right.z, 0.0),
      vm.Vector4(actualUp.x, actualUp.y, actualUp.z, 0.0),
      vm.Vector4(forward.x, forward.y, forward.z, 0.0),
      vm.Vector4(eye.x, eye.y, eye.z, 1.0),
    );
  }
}
