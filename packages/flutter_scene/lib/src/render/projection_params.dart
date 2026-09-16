import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:vector_math/vector_math.dart';

import 'package:flutter_scene/src/camera.dart';
import 'package:flutter_scene/src/render/planar_reflection.dart'
    show ObliqueNearClipProjection;
import 'package:flutter_scene/src/render/viewport_camera.dart';

/// The terms screen-space passes need to move between planar view depth and
/// view-space position, derived from a projection matrix so perspective,
/// orthographic, off-center, and custom projections all reconstruct the same
/// way.
///
/// With `ndc` the normalized device coordinate and `z` the planar view depth,
/// the view-space offset from the eye is
/// `xy = (ndc - offset) * scale * (orthographic ? 1 : z)`.
class ProjectionParams {
  const ProjectionParams({
    required this.scaleX,
    required this.scaleY,
    required this.offsetX,
    required this.offsetY,
    required this.orthographic,
    required this.near,
    required this.far,
  });

  /// Reads the terms from [projection] rendered into a view of [viewportSize]
  /// (only its aspect ratio matters unless the projection depends on size).
  ///
  /// The built-in projections read their fields in double precision, which
  /// keeps shadow cascade fitting exact. Any other projection is read from its
  /// matrix, assuming it maps view x and y independently of each other (true of
  /// every pinhole and parallel projection); a matrix whose w row is neither
  /// view depth nor constant is treated as perspective.
  factory ProjectionParams.of(
    CameraProjection projection,
    ui.Size viewportSize,
  ) {
    switch (projection) {
      case ViewportBoundProjection():
        return ProjectionParams.of(projection.inner, projection.viewportSize);
      case ObliqueNearClipProjection():
        // The oblique clip rewrites only the depth row, so the base projection
        // still describes the lateral mapping and the planar depth range.
        return ProjectionParams.of(projection.base, viewportSize);
      case PerspectiveProjection():
        final tanY = math.tan(projection.fovRadiansY * 0.5);
        final aspectRatio = viewportSize.height > 0
            ? viewportSize.width / viewportSize.height
            : 1.0;
        return ProjectionParams(
          scaleX: tanY * aspectRatio,
          scaleY: tanY,
          offsetX: 0.0,
          offsetY: 0.0,
          orthographic: false,
          near: projection.near,
          far: projection.far,
        );
      case OrthographicProjection():
        final extent = projection.visibleSize(viewportSize);
        final halfWidth = extent.x * 0.5;
        final halfHeight = extent.y * 0.5;
        return ProjectionParams(
          scaleX: halfWidth,
          scaleY: halfHeight,
          offsetX: halfWidth == 0.0 ? 0.0 : -projection.offset.x / halfWidth,
          offsetY: halfHeight == 0.0 ? 0.0 : -projection.offset.y / halfHeight,
          orthographic: true,
          near: projection.near,
          far: projection.far,
        );
      default:
        return ProjectionParams.fromMatrix(
          projection.getProjectionMatrixForViewport(viewportSize),
        );
    }
  }

  /// Reads the terms from a projection [matrix] (depth range `[0, 1]`).
  factory ProjectionParams.fromMatrix(Matrix4 matrix) {
    final m = matrix;
    final orthographic = m.entry(3, 2).abs() < 1e-9;
    final sx = m.entry(0, 0);
    final sy = m.entry(1, 1);
    // Clip z is `a * z + b` over w, and the depth range is [0, 1], so the
    // planes are where that reaches 0 and 1.
    final a = m.entry(2, 2);
    final b = m.entry(2, 3);
    final double near;
    final double far;
    if (a == 0.0) {
      near = 0.0;
      far = 0.0;
    } else if (orthographic) {
      near = -b / a;
      far = (1.0 - b) / a;
    } else {
      near = -b / a;
      far = a == 1.0 ? double.infinity : b / (1.0 - a);
    }
    return ProjectionParams(
      scaleX: sx == 0.0 ? 0.0 : 1.0 / sx,
      scaleY: sy == 0.0 ? 0.0 : 1.0 / sy,
      offsetX: orthographic ? m.entry(0, 3) : m.entry(0, 2),
      offsetY: orthographic ? m.entry(1, 3) : m.entry(1, 2),
      orthographic: orthographic,
      near: near,
      far: far,
    );
  }

  /// View-space x extent per unit of NDC: the half-fov tangent for a
  /// perspective projection (at unit depth), the half width for an
  /// orthographic one.
  final double scaleX;

  /// View-space y extent per unit of NDC, as [scaleX].
  final double scaleY;

  /// The NDC position of the view axis (zero for a centered projection).
  final double offsetX;

  /// The NDC position of the view axis, as [offsetX].
  final double offsetY;

  /// Whether view rays are parallel (no divide by depth).
  final bool orthographic;

  /// The near plane's planar view depth. Negative for an orthographic volume
  /// that starts behind the eye.
  final double near;

  /// The far plane's planar view depth.
  final double far;

  /// World units covered by one pixel at planar depth [depth], vertically,
  /// for a render target [heightPixels] tall.
  double worldUnitsPerPixel(double depth, double heightPixels) =>
      2.0 * scaleY * (orthographic ? 1.0 : depth) / heightPixels;

  /// 1.0 for an orthographic projection, else 0.0, as packed for shaders.
  double get orthographicFlag => orthographic ? 1.0 : 0.0;

  @override
  bool operator ==(Object other) =>
      other is ProjectionParams &&
      other.scaleX == scaleX &&
      other.scaleY == scaleY &&
      other.offsetX == offsetX &&
      other.offsetY == offsetY &&
      other.orthographic == orthographic &&
      other.near == near &&
      other.far == far;

  @override
  int get hashCode =>
      Object.hash(scaleX, scaleY, offsetX, offsetY, orthographic, near, far);
}

/// Whether [viewProjection] is orthographic: its w row, the view depth under
/// perspective, is constant.
bool isOrthographicTransform(Matrix4 viewProjection) {
  final s = viewProjection.storage;
  return s[3] * s[3] + s[7] * s[7] + s[11] * s[11] < 1e-12;
}

/// The world-space forward axis of an orthographic [viewProjection] (or of
/// [viewProjection] times a model transform, in that model's space), from the
/// cross product of its x and y rows.
///
/// Those rows are the camera's right and up axes, which neither an oblique
/// near-plane clip (it rewrites the z row) nor subpixel jitter (it moves the
/// translation) touches, unlike the z row.
Vector3 orthographicForward(Matrix4 viewProjection) {
  final s = viewProjection.storage;
  final xRow = Vector3(s[0], s[4], s[8]);
  final yRow = Vector3(s[1], s[5], s[9]);
  return xRow.cross(yRow)..normalize();
}
