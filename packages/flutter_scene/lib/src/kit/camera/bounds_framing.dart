import 'dart:math' as math;
import 'package:flutter_scene/src/camera.dart';
import 'package:vector_math/vector_math.dart' as vm;

/// Utility for framing node hierarchies or bounding boxes in a camera's view.
/// {@category Gameplay kit}
class BoundsFraming {
  /// Computes a camera world transform that frames [bounds] with [paddingFactor].
  ///
  /// [viewDirection] is the normalized direction vector from the bounds center
  /// towards the camera eye (defaults to a diagonal elevated view: `(1, 1, 1)`).
  static vm.Matrix4 computeFramingTransform(
    vm.Aabb3 bounds,
    Camera camera, {
    double paddingFactor = 1.25,
    vm.Vector3? viewDirection,
    vm.Vector3? upVector,
  }) {
    final center = bounds.center;
    final extents = (bounds.max - bounds.min) * 0.5;
    final radius = math.max(0.1, extents.length);

    final dir = (viewDirection ?? vm.Vector3(1.0, 0.8, 1.0)).normalized();
    final up = upVector ?? vm.Vector3(0.0, 1.0, 0.0);

    // Solve distance from projection FOV
    double distance;
    final proj = camera.projection;
    if (proj is PerspectiveProjection) {
      final halfFov = proj.fovRadiansY * 0.5;
      distance = (radius / math.sin(halfFov)) * paddingFactor;
    } else {
      distance = radius * 2.0 * paddingFactor;
    }

    final eye = center + dir * distance;
    final viewMat = vm.makeViewMatrix(eye, center, up);
    return viewMat..invert();
  }
}
