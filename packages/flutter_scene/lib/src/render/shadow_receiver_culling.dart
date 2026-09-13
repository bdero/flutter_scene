import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:vector_math/vector_math.dart';

import 'package:flutter_scene/src/light.dart';

/// Forces shadow receiver culling off, so parity tests can render the same
/// frame with and without it.
bool debugDisableShadowReceiverCulling = false;

/// Screen pixels the camera frustum is widened by before it bounds receivers,
/// covering temporal anti-aliasing's subpixel projection jitter.
const double _jitterPaddingPixels = 4.0;

/// The camera frustum, widened by a few pixels on every side, that bounds
/// every fragment a view can shade.
Frustum shadowReceiverFrustum(Matrix4 viewProjection, ui.Size pixelSize) {
  final sx = 1.0 / (1.0 + 2.0 * _jitterPaddingPixels / pixelSize.width);
  final sy = 1.0 / (1.0 + 2.0 * _jitterPaddingPixels / pixelSize.height);
  return Frustum.matrix(
    Matrix4.diagonal3Values(sx, sy, 1.0).multiplied(viewProjection),
  );
}

/// How far, in world units, a cascade's shadow lookups can reach from the
/// shaded point: the normal-offset bias, the filter kernel, and the soft
/// shadow blocker search. Mirrors `material_shadow_sampling.glsl`.
///
/// [maxSoftness] is the largest penumbra radius any receiver samples with,
/// which a material may raise above the light's own (see
/// `PreprocessedMaterial.adjustEngineLighting`).
double shadowReceiverMargin(
  DirectionalLight light,
  double boxSize,
  double maxSoftness,
) {
  final texel = boxSize / light.shadowMapResolution;
  final softness = maxSoftness.abs();
  // BiasDirectionalShadowPosition caps its slope term at 8.
  final normalOffset = light.shadowNormalBias.abs() + softness * 8.0;
  // The kernel radius floors at a texel; bilinear taps and texel rounding
  // add up to two more.
  final kernel = math.max(softness, texel) + 2.0 * texel;
  final blockerSearch = light.shadowFilter == DirectionalShadowFilter.pcss
      ? math.tan(light.angularRadius.abs()) * 7.0 * boxSize + texel
      : 0.0;
  return normalOffset + kernel + blockerSearch;
}

/// Planes that reject casters unable to shadow any receiver a cascade tile
/// serves, or null when they cannot be built.
///
/// The shader samples the first cascade whose tile contains a fragment, so a
/// tile's receivers are the fragments inside both [receiverFrustum] and the
/// tile's light-space prism (from [lightSpaceMatrix]). A caster matters only
/// if it lies in that volume swept toward the sun. The sweep is bounded by the
/// receiver volume's faces that point away from the sun plus planes through
/// its silhouette along the light direction. Every returned plane contains the
/// whole sweep, then is pushed out by [margin], so culling against them never
/// drops a caster the unculled map would have used.
///
/// Planes use the [Frustum] convention (inside where `n.p + c >= 0`) and skip
/// the tile's own lateral planes, which the light frustum already tests.
List<Plane>? shadowReceiverCullingPlanes({
  required Frustum receiverFrustum,
  required Matrix4 lightSpaceMatrix,
  required double margin,
}) {
  final m = lightSpaceMatrix.storage;
  // Orthographic rows 0 and 1 are the light's right and up axes over the box
  // half-width; row 2 is its travel direction over the depth range.
  final right = Vector3(m[0], m[4], m[8]);
  final up = Vector3(m[1], m[5], m[9]);
  final travel = Vector3(m[2], m[6], m[10]);
  final rightScale = right.length;
  final upScale = up.length;
  if (rightScale == 0.0 || upScale == 0.0 || travel.length == 0.0) {
    return null;
  }
  right.scale(1.0 / rightScale);
  up.scale(1.0 / upScale);
  travel.normalize();

  final frustumPlanes = <Plane>[
    receiverFrustum.plane0,
    receiverFrustum.plane1,
    receiverFrustum.plane2,
    receiverFrustum.plane3,
    receiverFrustum.plane4,
    receiverFrustum.plane5,
  ];
  // The prism's lateral sides: -1 <= row.p + w <= 1, normalized.
  final halfSpaces = <Plane>[
    for (final plane in frustumPlanes) _normalized(plane),
    Plane.normalconstant(right.clone(), (m[12] + 1.0) / rightScale),
    Plane.normalconstant(-right, (1.0 - m[12]) / rightScale),
    Plane.normalconstant(up.clone(), (m[13] + 1.0) / upScale),
    Plane.normalconstant(-up, (1.0 - m[13]) / upScale),
  ];

  // The receiver volume's vertices, projected onto the light plane.
  final points = <_Point2>[];
  final count = halfSpaces.length;
  for (var i = 0; i < count - 2; i++) {
    for (var j = i + 1; j < count - 1; j++) {
      for (var k = j + 1; k < count; k++) {
        final p = _intersect(halfSpaces[i], halfSpaces[j], halfSpaces[k]);
        if (p == null || !_insideAll(halfSpaces, p)) continue;
        points.add(_Point2(right.dot(p), up.dot(p)));
      }
    }
  }
  final hull = _convexHull(points);
  if (hull.length < 3) return null;

  final planes = <Plane>[];
  // Receiver faces that point away from the sun still bound the sweep.
  for (var i = 0; i < 6; i++) {
    final plane = halfSpaces[i];
    if (plane.normal.dot(travel) < -1e-9) {
      planes.add(Plane.normalconstant(plane.normal, plane.constant + margin));
    }
  }
  // The tile's sides in light-plane coordinates. A hull edge lying on one is
  // looser than the light frustum's own side plane, so it is skipped.
  final minX = (-1.0 - m[12]) / rightScale;
  final maxX = (1.0 - m[12]) / rightScale;
  final minY = (-1.0 - m[13]) / upScale;
  final maxY = (1.0 - m[13]) / upScale;
  final sideTolerance = 1e-5 / math.min(rightScale, upScale);
  bool onSide(double a, double b, double side) =>
      (a - side).abs() < sideTolerance && (b - side).abs() < sideTolerance;
  // Silhouette planes run along the light, through each hull edge.
  for (var i = 0; i < hull.length; i++) {
    final a = hull[i];
    final b = hull[(i + 1) % hull.length];
    if (onSide(a.x, b.x, minX) ||
        onSide(a.x, b.x, maxX) ||
        onSide(a.y, b.y, minY) ||
        onSide(a.y, b.y, maxY)) {
      continue;
    }
    final nx = -(b.y - a.y);
    final ny = b.x - a.x;
    final length = math.sqrt(nx * nx + ny * ny);
    if (length < 1e-12) continue;
    final ux = nx / length;
    final uy = ny / length;
    final normal = right * ux + up * uy;
    planes.add(Plane.normalconstant(normal, -(ux * a.x + uy * a.y) + margin));
  }
  return planes;
}

Plane _normalized(Plane plane) {
  final length = plane.normal.length;
  return Plane.normalconstant(plane.normal / length, plane.constant / length);
}

Vector3? _intersect(Plane a, Plane b, Plane c) {
  final bc = b.normal.cross(c.normal);
  final det = a.normal.dot(bc);
  if (det.abs() < 1e-9) return null;
  final ca = c.normal.cross(a.normal);
  final ab = a.normal.cross(b.normal);
  return (bc * -a.constant + ca * -b.constant + ab * -c.constant) / det;
}

// Tolerant, so roundoff never drops a real vertex (which would shrink the
// hull); a stray near-vertex only enlarges it.
bool _insideAll(List<Plane> planes, Vector3 p) {
  final tolerance =
      1e-6 * math.max(1.0, math.max(p.x.abs(), math.max(p.y.abs(), p.z.abs())));
  for (final plane in planes) {
    if (plane.normal.dot(p) + plane.constant < -tolerance) return false;
  }
  return true;
}

class _Point2 {
  _Point2(this.x, this.y);
  final double x;
  final double y;
}

double _cross(_Point2 o, _Point2 a, _Point2 b) =>
    (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x);

/// Counter-clockwise convex hull (monotone chain).
List<_Point2> _convexHull(List<_Point2> points) {
  if (points.length < 3) return points;
  points.sort((a, b) => a.x != b.x ? a.x.compareTo(b.x) : a.y.compareTo(b.y));
  final hull = <_Point2>[];
  for (final p in points) {
    while (hull.length >= 2 &&
        _cross(hull[hull.length - 2], hull.last, p) <= 0) {
      hull.removeLast();
    }
    hull.add(p);
  }
  final lowerLength = hull.length + 1;
  for (var i = points.length - 2; i >= 0; i--) {
    final p = points[i];
    while (hull.length >= lowerLength &&
        _cross(hull[hull.length - 2], hull.last, p) <= 0) {
      hull.removeLast();
    }
    hull.add(p);
  }
  hull.removeLast();
  return hull;
}
