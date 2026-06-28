import 'dart:math' as math;

import 'package:vector_math/vector_math.dart';

import 'package:flutter_scene/src/geometry/geometry.dart';
import 'package:flutter_scene/src/material/material.dart';

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

/// The level(s) to draw for a projected [screenSize] when cross-fading, each
/// with a fade weight in `(0, 1]`. Returns one entry away from a boundary,
/// two complementary entries (fades summing to 1) inside a boundary's blend
/// band so the encoder can dither-blend them, the last level alone fading out
/// across the cull band, or an empty list to cull.
///
/// [thresholds] are the same descending list as [selectLodLevel]. [blendRange]
/// is the half-width of each band as a fraction of the threshold; `0` reduces
/// to a hard switch (one level or cull). Bands must not overlap, so keep
/// [blendRange] smaller than the relative gap between adjacent thresholds.
List<({int level, double fade})> blendLodLevels(
  double screenSize,
  List<double> thresholds, {
  double blendRange = 0.1,
}) {
  final count = thresholds.length;
  if (blendRange > 0) {
    for (var k = 0; k < count; k++) {
      final lo = thresholds[k] * (1 - blendRange);
      final hi = thresholds[k] * (1 + blendRange);
      if (screenSize >= lo && screenSize < hi) {
        // Boundary k sits between level k (above) and level k+1 or, for the
        // last threshold, the cull floor (below). Fade from the lower to the
        // upper level across the band.
        final t = (screenSize - lo) / (hi - lo);
        return [
          (level: k, fade: t),
          if (k + 1 < count) (level: k + 1, fade: 1 - t),
        ];
      }
    }
  }
  for (var i = 0; i < count; i++) {
    if (screenSize >= thresholds[i]) return [(level: i, fade: 1.0)];
  }
  return const [];
}

/// One level of detail for an [LodComponent]: a drawable variant shown while
/// the object's projected on-screen size (see [lodScreenSize]) is at least
/// [screenSize], a fraction of the viewport height.
///
/// Levels are listed highest detail first, with strictly descending
/// [screenSize] thresholds. The smallest threshold is the cull floor: below
/// it the object is not drawn. Set the last level's [screenSize] to `0` to
/// never cull.
/// {@category Scene graph}
class LodLevel {
  /// A level drawing [geometry] with [material] down to a [screenSize]
  /// fraction of the viewport height.
  const LodLevel({
    required this.geometry,
    required this.material,
    required this.screenSize,
  });

  /// The geometry drawn at this level.
  final Geometry geometry;

  /// The material drawn at this level.
  final Material material;

  /// The smallest projected size (fraction of viewport height) at which this
  /// level is used.
  final double screenSize;
}

/// The per-item level-of-detail state the encoder consults each frame: the
/// ordered [levels], the policy ([lodBias], [hysteresis]), and the level
/// selected last frame so the hysteresis dead-band has memory.
///
/// One instance is shared by the item across views, so in a multi-view frame
/// the hysteresis memory is shared (acceptable for V1; per-view selection is
/// a later refinement).
class LodSelection {
  LodSelection(this.levels, {this.lodBias = 1.0, this.hysteresis = 0.1})
    : assert(levels.isNotEmpty, 'LOD needs at least one level'),
      assert(
        _strictlyDescending(levels),
        'LOD level screenSize thresholds must strictly descend',
      ),
      _thresholds = [for (final level in levels) level.screenSize];

  static bool _strictlyDescending(List<LodLevel> levels) {
    for (var i = 1; i < levels.length; i++) {
      if (levels[i].screenSize >= levels[i - 1].screenSize) return false;
    }
    return true;
  }

  /// The drawable variants, highest detail first.
  final List<LodLevel> levels;

  /// Multiplies the projected size before selection. Above `1` keeps higher
  /// detail at a greater distance; below `1` drops detail sooner.
  final double lodBias;

  /// Fractional dead-band around each threshold; see [selectLodLevel].
  final double hysteresis;

  final List<double> _thresholds;
  int _currentLevel = -1;

  /// Selects the level index for a projected [screenSize], or `-1` to cull,
  /// applying [lodBias] and the [hysteresis] dead-band, and remembering the
  /// result for next frame.
  int select(double screenSize) {
    _currentLevel = selectLodLevel(
      screenSize * lodBias,
      _thresholds,
      hysteresis: hysteresis,
      currentLevel: _currentLevel,
    );
    return _currentLevel;
  }
}
