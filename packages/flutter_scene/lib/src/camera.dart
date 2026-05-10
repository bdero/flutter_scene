import 'dart:math';
import 'dart:ui' as ui;

import 'package:vector_math/vector_math.dart';

/// Base class for camera implementations passed to [Scene.render].
///
/// A camera owns the transform that converts world-space coordinates into
/// clip-space coordinates for a given render target size. Subclasses
/// configure projection and view conventions; [PerspectiveCamera] is the
/// built-in option, but applications can subclass [Camera] to implement
/// orthographic or other custom projections.
abstract class Camera {
  /// The world-space position of the camera. Used by materials for
  /// view-dependent shading (e.g. specular reflections).
  Vector3 get position;

  /// Returns the combined projection-and-view transform for a render target
  /// of the given [dimensions].
  ///
  /// Called once per [Scene.render] call. Implementations may read
  /// [dimensions] (typically to compute aspect ratio) and any subclass
  /// configuration to build the matrix.
  Matrix4 getViewTransform(ui.Size dimensions);

  /// Returns the view frustum (six normalized clip planes) for a render
  /// target of the given [dimensions].
  ///
  /// Built from [getViewTransform] using the standard Gribb-Hartmann
  /// extraction. Useful for [Node.isVisibleTo] queries and any other
  /// caller-driven culling.
  Frustum getFrustum(ui.Size dimensions) =>
      Frustum.matrix(getViewTransform(dimensions));
}

Matrix4 _matrix4LookAt(Vector3 position, Vector3 target, Vector3 up) {
  Vector3 forward = (target - position).normalized();
  Vector3 right = up.cross(forward).normalized();
  up = forward.cross(right).normalized();

  return Matrix4(
    right.x,
    up.x,
    forward.x,
    0.0, //
    right.y,
    up.y,
    forward.y,
    0.0, //
    right.z,
    up.z,
    forward.z,
    0.0, //
    -right.dot(position),
    -up.dot(position),
    -forward.dot(position),
    1.0, //
  );
}

Matrix4 _matrix4Perspective(
  double fovRadiansY,
  double aspectRatio,
  double zNear,
  double zFar,
) {
  double height = tan(fovRadiansY * 0.5);
  double width = height * aspectRatio;

  return Matrix4(
    1.0 / width,
    0.0,
    0.0,
    0.0,
    0.0,
    1.0 / height,
    0.0,
    0.0,
    0.0,
    0.0,
    zFar / (zFar - zNear),
    1.0,
    0.0,
    0.0,
    -(zFar * zNear) / (zFar - zNear),
    0.0,
  );
}

/// A standard pinhole-style perspective camera.
///
/// Defined by an eye [position], a look-at [target], an [up] direction, a
/// vertical field-of-view ([fovRadiansY]), and a near/far frustum
/// ([fovNear]/[fovFar]). The horizontal field of view is derived from the
/// render target's aspect ratio at draw time.
///
/// Default placement is at `(0, 0, -5)` looking at the origin with `+Y`
/// up, suitable for inspecting a model that fits within a unit cube
/// centered on the origin.
class PerspectiveCamera extends Camera {
  /// Creates a [PerspectiveCamera].
  ///
  /// All parameters are optional; omitting them yields the default
  /// placement (eye at `(0, 0, -5)`, looking at the origin, `+Y` up) and
  /// a 45° vertical field of view with a `0.1`–`1000.0` clip range.
  PerspectiveCamera({
    this.fovRadiansY = 45 * degrees2Radians,
    Vector3? position,
    Vector3? target,
    Vector3? up,
    this.fovNear = 0.1,
    this.fovFar = 1000.0,
  }) : position = position ?? Vector3(0, 0, -5),
       target = target ?? Vector3(0, 0, 0),
       up = up ?? Vector3(0, 1, 0);

  /// Vertical field of view, in radians.
  ///
  /// The horizontal field of view is computed at render time from this
  /// value and the render target's aspect ratio.
  double fovRadiansY;

  /// World-space position of the camera (the eye point).
  @override
  Vector3 position = Vector3(0, 0, -5);

  /// World-space point the camera is looking at.
  Vector3 target;

  /// World-space "up" direction used to orient the camera around the
  /// view vector. Typically `Vector3(0, 1, 0)`.
  Vector3 up;

  /// Distance to the near clipping plane. Geometry closer than this is
  /// clipped away.
  double fovNear;

  /// Distance to the far clipping plane. Geometry beyond this is clipped
  /// away. Must be greater than [fovNear].
  double fovFar;

  @override
  Matrix4 getViewTransform(ui.Size dimensions) {
    return _matrix4Perspective(
          fovRadiansY,
          dimensions.width / dimensions.height,
          fovNear,
          fovFar,
        ) *
        _matrix4LookAt(position, target, up);
  }
}
