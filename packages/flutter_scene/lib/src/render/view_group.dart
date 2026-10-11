import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:vector_math/vector_math.dart';

import 'package:flutter_scene/src/camera.dart';
import 'package:flutter_scene/src/render/projection_params.dart';
import 'package:flutter_scene/src/render/viewport_camera.dart';

/// How far apart two views' forward axes may point (as a cosine) and still
/// count as parallel for a combined camera. About two degrees.
const double _kParallelCosine = 0.9994;

/// The far distance frusta with an infinite far plane are closed at while
/// their corners are measured.
const double _kCornerFar = 1.0e4;

/// A frustum containing every one of [cameras]' view frusta, for culling a
/// group of views once.
///
/// Each of the six planes is taken from whichever camera's matching plane
/// keeps every camera's frustum corners on its visible side (the left eye's
/// left plane, the right eye's right plane). A slot no candidate satisfies,
/// which happens when the views' orientations differ a lot, culls nothing on
/// that side, so the result is always conservative.
Frustum combinedCullingFrustum(List<Camera> cameras, List<ui.Size> sizes) {
  assert(cameras.length == sizes.length && cameras.isNotEmpty);
  if (cameras.length == 1) return cullingFrustumOf(cameras[0], sizes[0]);

  final candidates = <Frustum>[
    for (var i = 0; i < cameras.length; i++)
      cullingFrustumOf(cameras[i], sizes[i]),
  ];
  // Corners come from a finite version of each frustum, since an infinite
  // far plane has none.
  final corners = <Vector3>[];
  final c = List<Vector3>.generate(8, (_) => Vector3.zero());
  for (var i = 0; i < cameras.length; i++) {
    Frustum.matrix(
      finiteViewTransformOf(cameras[i], sizes[i], _kCornerFar),
    ).calculateCorners(c[0], c[1], c[2], c[3], c[4], c[5], c[6], c[7]);
    for (final corner in c) {
      if (corner.x.isFinite && corner.y.isFinite && corner.z.isFinite) {
        corners.add(corner.clone());
      }
    }
  }

  bool containsAll(Plane plane) {
    for (final corner in corners) {
      // Float error on a corner ten kilometres out is a few millimetres.
      final tolerance = 1e-6 * (1.0 + corner.length);
      if (plane.distanceToVector3(corner) < -tolerance) return false;
    }
    return true;
  }

  final result = Frustum();
  final slots = <Plane>[
    result.plane0,
    result.plane1,
    result.plane2,
    result.plane3,
    result.plane4,
    result.plane5,
  ];
  for (var slot = 0; slot < 6; slot++) {
    Plane? chosen;
    for (final candidate in candidates) {
      final plane = switch (slot) {
        0 => candidate.plane0,
        1 => candidate.plane1,
        2 => candidate.plane2,
        3 => candidate.plane3,
        4 => candidate.plane4,
        _ => candidate.plane5,
      };
      if (containsAll(plane)) {
        chosen = plane;
        break;
      }
    }
    if (chosen == null) {
      // Nothing on this side is rejected.
      slots[slot].setFromComponents(0.0, 0.0, 0.0, 1.0);
    } else {
      slots[slot].copyFrom(chosen);
    }
  }
  return result;
}

/// A camera whose single pinhole frustum contains every one of [cameras]'
/// frusta, for fitting work that wants one camera (directional shadow
/// cascades), or null when the cameras are not parallel or not all pinhole.
///
/// The combined frustum's apex sits where the outermost side planes meet,
/// behind the eyes, and its clip planes move back by the same amount. Each
/// vertical edge takes the steepest slope any eye's far corner needs from
/// that apex, so nothing an eye sees falls outside it.
Camera? combinedViewCamera(List<Camera> cameras, List<ui.Size> sizes) {
  assert(cameras.length == sizes.length && cameras.isNotEmpty);
  if (cameras.length == 1) return cameras[0];
  final first = cameras[0];
  final forward = first.forward.normalized();
  final right = first.up.cross(forward)..normalize();
  final up = forward.cross(right)..normalize();
  final origin = first.position;

  var tanLeft = double.infinity;
  var tanRight = double.negativeInfinity;
  var tanDown = double.infinity;
  var tanUp = double.negativeInfinity;
  var near = double.infinity;
  var far = 0.0;
  // Lateral and depth offsets of each eye from the first, in its basis.
  final offsets = <Vector3>[];
  final params = <ProjectionParams>[];
  for (var i = 0; i < cameras.length; i++) {
    final camera = cameras[i];
    if (camera.forward.normalized().dot(forward) < _kParallelCosine) {
      return null;
    }
    final projection = ProjectionParams.of(camera.projection, sizes[i]);
    if (projection.orthographic || projection.scaleX <= 0.0) return null;
    final d = camera.position - origin;
    offsets.add(Vector3(d.dot(right), d.dot(up), d.dot(forward)));
    params.add(projection);
    near = math.min(near, projection.near);
    far = math.max(far, projection.far);
  }

  // Each eye's side planes in the first eye's basis, as x = ox + t * (z - oz)
  // lines in the xz plane (and likewise y). The combined apex is where the
  // leftmost eye's left plane meets the rightmost eye's right plane.
  double edge(int i, double ndc, bool horizontal) {
    final p = params[i];
    return horizontal
        ? (ndc - p.offsetX) * p.scaleX
        : (ndc - p.offsetY) * p.scaleY;
  }

  // Candidate apex depth from the horizontal outer planes. A plane through
  // (ox, oz) with slope t crosses the axis where x = 0.
  var apexZ = 0.0;
  var apexX = 0.0;
  var apexY = 0.0;
  {
    var leftI = 0, rightI = 0;
    for (var i = 1; i < cameras.length; i++) {
      if (offsets[i].x < offsets[leftI].x) leftI = i;
      if (offsets[i].x > offsets[rightI].x) rightI = i;
    }
    final tl = edge(leftI, -1.0, true);
    final tr = edge(rightI, 1.0, true);
    final ol = offsets[leftI];
    final or = offsets[rightI];
    // x = ol.x + tl (z - ol.z) and x = or.x + tr (z - or.z) meet at:
    final denominator = tl - tr;
    if (denominator.abs() < 1e-9) return null;
    apexZ = (or.x - ol.x + tl * ol.z - tr * or.z) / denominator;
    apexX = ol.x + tl * (apexZ - ol.z);
    tanLeft = tl;
    tanRight = tr;
  }
  // The vertical apex offset only matters when eyes sit at different heights;
  // keep the apex on the first eye's vertical axis and widen instead.
  apexY = 0.0;

  // Every eye's far corners must lie inside the combined frustum, so each
  // vertical edge takes the steepest slope needed from the apex. The near
  // and far planes are measured from the apex too.
  var combinedNear = double.infinity;
  var combinedFar = 0.0;
  for (var i = 0; i < cameras.length; i++) {
    final o = offsets[i];
    final p = params[i];
    for (final depth in [p.near, p.far.isFinite ? p.far : _kCornerFar]) {
      final z = o.z + depth;
      final dz = z - apexZ;
      if (dz <= 0.0) return null;
      final yDown = o.y + edge(i, -1.0, false) * depth - apexY;
      final yUp = o.y + edge(i, 1.0, false) * depth - apexY;
      tanDown = math.min(tanDown, yDown / dz);
      tanUp = math.max(tanUp, yUp / dz);
      final xLeft = o.x + edge(i, -1.0, true) * depth - apexX;
      final xRight = o.x + edge(i, 1.0, true) * depth - apexX;
      tanLeft = math.min(tanLeft, xLeft / dz);
      tanRight = math.max(tanRight, xRight / dz);
      combinedNear = math.min(combinedNear, dz);
      combinedFar = math.max(combinedFar, dz);
    }
  }
  if (!(tanRight > tanLeft) || !(tanUp > tanDown) || combinedNear <= 0.0) {
    return null;
  }
  final anyInfinite = params.any((p) => !p.far.isFinite);
  return _CombinedCamera(
    position: origin + right * apexX + up * apexY + forward * apexZ,
    forward: forward,
    up: up,
    projection: OffAxisProjection(
      tanLeft: tanLeft,
      tanRight: tanRight,
      tanDown: tanDown,
      tanUp: tanUp,
      near: combinedNear,
      far: anyInfinite ? double.infinity : combinedFar,
    ),
  );
}

class _CombinedCamera extends Camera {
  _CombinedCamera({
    required this.position,
    required this.forward,
    required this.up,
    required this.projection,
  });

  @override
  final Vector3 position;
  @override
  final Vector3 forward;
  @override
  final Vector3 up;
  @override
  final OffAxisProjection projection;

  @override
  Matrix4 getViewMatrix() => lookAtViewMatrix(position, position + forward, up);
}
