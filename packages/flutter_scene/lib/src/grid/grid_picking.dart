import 'dart:ui' show Offset, Rect, Size;

import 'package:scene/grid.dart';
import 'package:vector_math/vector_math.dart';

import 'package:flutter_scene/src/camera.dart';

/// Turning pointer positions into grid cells: the half of a tile game that
/// needs a camera.
///
/// A [Grid] on its own maps between world positions and cells. These
/// extensions supply the missing step — projecting the pointer into the world
/// — so a click becomes a tile:
///
/// ```dart
/// final cell = grid.cellAtScreenPoint(
///   details.localPosition,
///   camera: scene.camera!,
///   viewSize: viewSize,
/// );
/// if (cell != null) placeBuilding(cell);
/// ```
///
/// The grid is treated as an infinite flat plane at [Grid.elevation]. That is
/// exactly right for a flat board and a good approximation for gently rolling
/// terrain; on genuinely hilly ground, raycast the terrain geometry with
/// `Scene.raycast` and pass the hit point to [Grid.cellAt] instead, which
/// accounts for the actual height.
/// {@category Picking and input}
extension GridPicking on Grid {
  /// Where [ray] crosses the grid plane, or null when it never does.
  ///
  /// Returns null for a ray parallel to the plane, and for one pointing away
  /// from it — a camera looking at the sky has no cell under its pointer, and
  /// that is a real answer rather than an error.
  Vector3? planePointOf(Ray ray) {
    final direction = ray.direction;
    // A near-zero Y component means the ray runs along the plane; there is no
    // single crossing point to report.
    if (direction.y.abs() < 1e-9) return null;
    final t = (elevation - ray.origin.y) / direction.y;
    if (t < 0) return null;
    return Vector3(
      ray.origin.x + direction.x * t,
      elevation,
      ray.origin.z + direction.z * t,
    );
  }

  /// The cell [ray] crosses, or null when it misses the plane.
  GridCoord? cellUnderRay(Ray ray) {
    final point = planePointOf(ray);
    return point == null ? null : cellAt(point);
  }

  /// The cell under [screenPosition] (logical pixels, origin top-left) in a
  /// view of [viewSize], as seen through [camera].
  GridCoord? cellAtScreenPoint(
    Offset screenPosition, {
    required Camera camera,
    required Size viewSize,
  }) => cellUnderRay(camera.screenPointToRay(screenPosition, viewSize));

  /// Where [screenPosition] lands on the grid plane in world space, the
  /// unrounded counterpart of [cellAtScreenPoint].
  ///
  /// Use it for a placement ghost that should slide smoothly rather than
  /// snapping, or as the input to a distance measurement.
  Vector3? planePointAtScreenPoint(
    Offset screenPosition, {
    required Camera camera,
    required Size viewSize,
  }) => planePointOf(camera.screenPointToRay(screenPosition, viewSize));

  /// The cells inside a screen-space rectangle: a drag-selection marquee.
  ///
  /// The rectangle's four corners are projected onto the grid plane and the
  /// cells covering their extent are returned. Because a perspective camera
  /// projects a screen rectangle to a trapezium on the ground, this is the
  /// trapezium's bounding block rather than its exact shape — a few extra
  /// cells at the near and far edges. It is exact under an orthographic
  /// camera, which is what most games that need a marquee are using anyway.
  ///
  /// Returns null when the rectangle does not meet the plane at all (a
  /// marquee dragged across the sky).
  GridRect? cellsInScreenRect(
    Rect rect, {
    required Camera camera,
    required Size viewSize,
  }) {
    double? minX;
    double? minZ;
    double? maxX;
    double? maxZ;
    for (final corner in <Offset>[
      rect.topLeft,
      rect.topRight,
      rect.bottomRight,
      rect.bottomLeft,
    ]) {
      final point = planePointAtScreenPoint(
        corner,
        camera: camera,
        viewSize: viewSize,
      );
      if (point == null) continue;
      minX = minX == null || point.x < minX ? point.x : minX;
      maxX = maxX == null || point.x > maxX ? point.x : maxX;
      minZ = minZ == null || point.z < minZ ? point.z : minZ;
      maxZ = maxZ == null || point.z > maxZ ? point.z : maxZ;
    }
    if (minX == null || minZ == null || maxX == null || maxZ == null) {
      return null;
    }
    return cellsInXZRect(minX, minZ, maxX, maxZ);
  }
}
