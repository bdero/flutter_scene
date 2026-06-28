import 'dart:math' as math;

import 'package:vector_math/vector_math.dart';

/// The projected on-screen size of a world-space bounding sphere, as a
/// fraction of the viewport height.
///
/// A value of `1.0` means the sphere's diameter spans the full viewport
/// height; `0.5` means half. This is the level-of-detail selection metric:
/// unlike raw camera distance it is field-of-view aware (a wider lens makes
/// everything smaller) and resolution independent (it is a fraction, not a
/// pixel count), matching how the major engines drive LOD.
///
/// [center] and [radius] are the sphere in world space, [cameraPosition] is
/// the eye, and [fovRadiansY] is the camera's vertical field of view. The
/// camera sitting inside the sphere yields [double.infinity] (treat as the
/// highest detail).
double lodScreenSize({
  required Vector3 center,
  required double radius,
  required Vector3 cameraPosition,
  required double fovRadiansY,
}) {
  final distance = center.distanceTo(cameraPosition);
  if (distance <= radius) return double.infinity;
  // The viewport spans 2 * distance * tan(fovY / 2) world units at the
  // sphere's depth, so the sphere's diameter (2 * radius) covers
  // radius / (distance * tan(fovY / 2)) of the height.
  return radius / (distance * math.tan(fovRadiansY / 2));
}

/// Selects the level-of-detail index for a projected [screenSize] against a
/// list of [thresholds], or `-1` to cull (draw nothing).
///
/// [thresholds] are ordered highest detail first with descending values:
/// `thresholds[i]` is the smallest [screenSize] at which level `i` is used.
/// The last (smallest) threshold doubles as the cull floor, so a size below
/// it culls the object; set the last threshold to `0` to never cull.
///
/// [currentLevel] is the level selected last frame (or `-1` if culled), and
/// [hysteresis] is a fractional dead-band around each boundary. With a
/// nonzero margin an adjacent level change only happens once the size moves
/// clearly past the boundary, so a size hovering on a threshold does not
/// flip-flop. Larger jumps (a fast camera move) switch immediately.
int selectLodLevel(
  double screenSize,
  List<double> thresholds, {
  double hysteresis = 0.0,
  int currentLevel = -1,
}) {
  assert(thresholds.isNotEmpty, 'LOD needs at least one level');
  var naive = -1;
  for (var i = 0; i < thresholds.length; i++) {
    if (screenSize >= thresholds[i]) {
      naive = i;
      break;
    }
  }
  if (naive == currentLevel || hysteresis <= 0) return naive;

  final last = thresholds.length - 1;
  // Switch to finer detail only once clearly past the upper boundary.
  if (currentLevel >= 1 && naive == currentLevel - 1) {
    return screenSize >= thresholds[currentLevel - 1] * (1 + hysteresis)
        ? naive
        : currentLevel;
  }
  // Switch to coarser detail only once clearly below the lower boundary.
  if (currentLevel >= 0 && naive == currentLevel + 1) {
    return screenSize < thresholds[currentLevel] * (1 - hysteresis)
        ? naive
        : currentLevel;
  }
  // The cull floor is just the boundary below the last level.
  if (currentLevel == last && naive == -1) {
    return screenSize < thresholds[last] * (1 - hysteresis) ? -1 : currentLevel;
  }
  if (currentLevel == -1 && naive == last) {
    return screenSize >= thresholds[last] * (1 + hysteresis) ? naive : -1;
  }
  // A multi-level jump (or any non-adjacent change) switches immediately.
  return naive;
}
