import 'dart:math' as math;

import 'package:flutter/foundation.dart' show internal;

/// The share of the nearest visible depth a fitted near plane takes, leaving
/// room for float rounding in the bounds and in the clip.
const double kNearFitSafety = 0.8;

/// The smallest share of [far] a fitted near plane may reach, so a fit never
/// collapses the depth range.
const double kNearFitMaxShareOfFar = 0.1;

/// One view's near-plane fit, kept for the debug advisory.
@internal
class NearPlaneFit {
  const NearPlaneFit({
    required this.authoredNear,
    required this.fittedNear,
    required this.visibleDepth,
    required this.nearestNode,
    this.nearestContainsEye = false,
    this.nearestExtent = 0.0,
  });

  /// The projection's own near plane, the fit's floor.
  final double authoredNear;

  /// The plane the view rasterized with.
  final double fittedNear;

  /// The lower bound on the nearest visible planar depth (zero or less when
  /// something reaches the eye, infinity when nothing is visible).
  final double visibleDepth;

  /// The node whose bounds set [visibleDepth], when one did.
  final Object? nearestNode;

  /// Whether [nearestNode]'s bounds hold the eye, which pins the plane.
  final bool nearestContainsEye;

  /// The largest side of [nearestNode]'s bounds, in world units.
  final double nearestExtent;
}

/// A node at least this large (world units) holding the eye is reported as
/// what pins the near plane; smaller ones are ordinary nearby geometry.
const double kNearFitContainerExtent = 50.0;

/// The ratio of available to used depth precision worth an advisory.
const double kNearFitAdvisoryRatio = 4.0;

/// The debug advisory for a view whose near plane wastes most of its depth
/// precision, or null when there is nothing worth saying.
///
/// With [fitEnabled] off it reports how much a fitted (or hand-picked) near
/// plane would gain. With it on it reports a large node whose bounds hold
/// the eye, since that keeps the fit at the authored plane. [nodeName] names
/// [fit]'s nearest node.
@internal
String? nearPlaneAdvisory(
  NearPlaneFit fit, {
  required bool fitEnabled,
  String? nodeName,
}) {
  final label = nodeName == null || nodeName.isEmpty ? 'a node' : "'$nodeName'";
  if (!fitEnabled) {
    final available = fittedNearPlane(
      visibleDepth: fit.visibleDepth,
      authoredNear: fit.authoredNear,
      far: double.infinity,
    );
    final ratio = available / fit.authoredNear;
    if (ratio < kNearFitAdvisoryRatio) return null;
    return 'flutter_scene: camera near is ${_metres(fit.authoredNear)} but '
        'nothing it draws is closer than ${_metres(fit.visibleDepth)}, so '
        'most of the depth precision goes unused and surfaces a few '
        'centimetres apart flicker (z-fighting) in the distance. Turn '
        'Scene.fitNearPlane back on, or set near to ${_metres(available)} '
        '(${ratio.toStringAsFixed(0)}x the precision).';
  }
  if (fit.nearestContainsEye &&
      fit.nearestExtent >= kNearFitContainerExtent &&
      fit.fittedNear <= fit.authoredNear) {
    return 'flutter_scene: the near plane stays at '
        '${_metres(fit.authoredNear)} because the camera is inside the bounds '
        'of $label (${_metres(fit.nearestExtent)} across), so it cannot be '
        'raised for depth precision and distant surfaces a few centimetres '
        'apart may flicker (z-fighting). Draw a sky with Scene.skybox rather '
        'than a mesh around the camera, and split merged meshes the camera '
        'moves inside of.';
  }
  return null;
}

String _metres(double value) => value >= 10
    ? '${value.toStringAsFixed(0)} m'
    : (value >= 1
          ? '${value.toStringAsFixed(1)} m'
          : '${value.toStringAsFixed(2)} m');

/// The near plane a perspective view rasterizes with when nothing it draws is
/// nearer than [visibleDepth] (a lower bound from bounds): [kNearFitSafety]
/// of it, snapped down to a power of the square root of two so small camera
/// moves leave it alone, and clamped between [authoredNear] and
/// [kNearFitMaxShareOfFar] of [far].
///
/// [previous] is the plane the view used last frame. It is kept while still
/// safe until the fit can at least double it, so the plane (and with it the
/// depth precision) does not step back and forth across one snap boundary.
@internal
double fittedNearPlane({
  required double visibleDepth,
  required double authoredNear,
  required double far,
  double? previous,
}) {
  if (visibleDepth == double.infinity) {
    // Nothing is visible, so nothing can clip; keep what the view had.
    return previous ?? authoredNear;
  }
  final safe = visibleDepth * kNearFitSafety;
  if (!(safe > authoredNear)) return authoredNear;
  final ceiling = far.isFinite
      ? math.max(authoredNear, far * kNearFitMaxShareOfFar)
      : double.infinity;
  final snapped = math.min(_snapDown(safe), ceiling);
  if (snapped <= authoredNear) return authoredNear;
  if (previous != null &&
      previous >= authoredNear &&
      previous <= safe &&
      previous <= ceiling &&
      snapped < previous * 2.0) {
    return previous;
  }
  return snapped;
}

// The largest power of the square root of two at or below [value].
double _snapDown(double value) {
  final halfSteps = (math.log(value) / math.ln2 * 2.0).floorToDouble();
  final snapped = math.pow(2.0, halfSteps / 2.0).toDouble();
  // Guard against log rounding landing one step high.
  return snapped > value ? snapped / math.sqrt2 : snapped;
}
