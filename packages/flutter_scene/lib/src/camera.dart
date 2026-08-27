import 'dart:math';
import 'dart:ui' as ui;

import 'package:vector_math/vector_math.dart';

/// A lens projection that maps view-space coordinates into clip space.
///
/// The projection is the half of a camera that does not depend on where the
/// camera is or what it looks at, only on the lens (field of view, clip
/// planes) and the render target's aspect ratio. Pair one with a view (a
/// [Camera]'s [Camera.getViewMatrix]) to form a full view-projection
/// transform. [PerspectiveProjection] is the built-in option; applications
/// can implement [CameraProjection] for orthographic or other projections.
/// {@category Scene graph}
abstract class CameraProjection {
  /// Returns the projection matrix for a render target of the given
  /// [aspectRatio] (width / height).
  Matrix4 getProjectionMatrix(double aspectRatio, {Vector2? jitter});

  /// Interpolates this lens toward [to] by [weight] in `[0, 1]`, for a
  /// [CameraDirector] blending between two shots that each specify a lens.
  ///
  /// The default snaps at the halfway point, which is the only meaningful
  /// answer between two projections that do not share a parameterization
  /// (a perspective lens and an orthographic one describe different things,
  /// and the matrices between them are not a lens). Projections of the same
  /// kind override this to interpolate their parameters, so a perspective
  /// pair gives a smooth focal-length change and an orthographic pair gives
  /// a smooth zoom.
  CameraProjection lerpTo(CameraProjection to, double weight) =>
      weight < 0.5 ? this : to;
}

/// A standard pinhole perspective projection.
/// {@category Scene graph}
class PerspectiveProjection extends CameraProjection {
  /// Creates a [PerspectiveProjection] with a vertical field of view
  /// [fovRadiansY] and a [near]/[far] clip range.
  PerspectiveProjection({
    this.fovRadiansY = 45 * degrees2Radians,
    this.near = 0.1,
    this.far = 1000.0,
  });

  /// Vertical field of view, in radians. The horizontal field of view is
  /// derived from the render target's aspect ratio at draw time.
  double fovRadiansY;

  /// Distance to the near clipping plane. Geometry closer is clipped away.
  double near;

  /// Distance to the far clipping plane. Must be greater than [near].
  double far;

  @override
  Matrix4 getProjectionMatrix(double aspectRatio, {Vector2? jitter}) =>
      _matrix4Perspective(fovRadiansY, aspectRatio, near, far, jitter: jitter);

  /// Interpolates the field of view and the clip range toward another
  /// perspective lens, producing the focal-length ramp behind a dolly zoom.
  /// Falls back to the snapping default against any other kind of lens.
  @override
  CameraProjection lerpTo(CameraProjection to, double weight) {
    if (to is! PerspectiveProjection) return super.lerpTo(to, weight);
    double mix(double a, double b) => a + (b - a) * weight;
    return PerspectiveProjection(
      fovRadiansY: mix(fovRadiansY, to.fovRadiansY),
      near: mix(near, to.near),
      far: mix(far, to.far),
    );
  }
}

/// A parallel projection: geometry keeps its size regardless of distance and
/// parallel lines stay parallel.
///
/// This is the lens for strategy, isometric, top-down, and 2.5D games, and
/// for CAD-style technical views. Unlike a perspective lens it has no field
/// of view; the view is a box, and [height] (the vertical extent in world
/// units) is what "zooming" changes. The horizontal extent follows from the
/// render target's aspect ratio.
///
/// **Effects that reconstruct a view ray from depth do not run under an
/// orthographic lens**: shadows, GTAO, screen-space reflections, screen-space
/// global illumination, depth of field, god rays, TAA, and planar
/// reflections all require a perspective projection and are skipped rather
/// than rendered wrongly. Bloom, tone mapping, LUT color grading, fog, FXAA,
/// and SMAA are unaffected, as is everything in the forward pass, so an
/// orthographic scene still lights and shades normally.
///
/// Unlike a perspective lens, [near] may be zero or negative: there is no
/// division by view-space depth, so pulling the near plane behind the eye
/// simply widens the depth range instead of degenerating it.
/// {@category Scene graph}
class OrthographicProjection extends CameraProjection {
  /// Creates an orthographic lens showing [height] world units vertically
  /// over a [near]..[far] depth range.
  OrthographicProjection({
    this.height = 10.0,
    this.near = 0.1,
    this.far = 1000.0,
  });

  /// The vertical extent of the view, in world units. Halving this doubles
  /// the apparent size of everything, the orthographic equivalent of zoom.
  double height;

  /// Distance to the near clipping plane. May be zero or negative.
  double near;

  /// Distance to the far clipping plane. Must be greater than [near].
  double far;

  /// The horizontal extent of the view in world units, for a target of the
  /// given [aspectRatio] (width / height).
  double widthFor(double aspectRatio) => height * aspectRatio;

  @override
  Matrix4 getProjectionMatrix(double aspectRatio, {Vector2? jitter}) =>
      _matrix4Orthographic(
        height * aspectRatio,
        height,
        near,
        far,
        jitter: jitter,
      );

  /// Interpolates the view size and the clip range toward another
  /// orthographic lens, producing a smooth zoom. Falls back to the snapping
  /// default against any other kind of lens.
  @override
  CameraProjection lerpTo(CameraProjection to, double weight) {
    if (to is! OrthographicProjection) return super.lerpTo(to, weight);
    double mix(double a, double b) => a + (b - a) * weight;
    return OrthographicProjection(
      height: mix(height, to.height),
      near: mix(near, to.near),
      far: mix(far, to.far),
    );
  }
}

/// A view onto a scene: a world-space eye [position] and orientation paired
/// with a lens [projection], used by [Scene.render] to map the scene into
/// clip space.
///
/// A camera separates its *view* (where it is and which way it looks, from
/// [getViewMatrix]) from its *projection* (the lens, a [CameraProjection]).
/// [PerspectiveCamera] is the built-in free camera, positioned by
/// eye/target/up. Attach a [CameraComponent] to a [Node] to drive the view
/// from that node's transform instead.
/// {@category Scene graph}
abstract class Camera {
  /// The world-space position of the camera (the eye point). Used by
  /// materials for view-dependent shading (e.g. specular reflections).
  Vector3 get position;

  /// The world-space direction the camera looks along (unit length).
  Vector3 get forward;

  /// The world-space up direction used to orient the camera around
  /// [forward].
  Vector3 get up;

  /// The lens projection paired with this camera's view.
  CameraProjection get projection;

  /// Returns the world-to-view transform (the view matrix), independent of
  /// the render target size.
  Matrix4 getViewMatrix();

  /// Maps a position inside a view (logical pixels, origin top-left) to the
  /// world-space ray leaving the camera through that point, for picking
  /// (`Scene.raycast`) and pointer input. [viewSize] is the view's logical
  /// size (the constraints `SceneView` renders into).
  Ray screenPointToRay(ui.Offset screenPosition, ui.Size viewSize) {
    final viewProjection = getViewTransform(viewSize);
    final inverse = Matrix4.zero();
    if (inverse.copyInverse(viewProjection) == 0.0) {
      return Ray.originDirection(position.clone(), forward.clone());
    }
    final ndcX = screenPosition.dx / viewSize.width * 2 - 1;
    final ndcY = 1 - screenPosition.dy / viewSize.height * 2;
    Vector3 unproject(double z) {
      final v = inverse * Vector4(ndcX, ndcY, z, 1) as Vector4;
      return v.xyz / v.w;
    }

    final near = unproject(0.0);
    return Ray.originDirection(near, unproject(1.0) - near);
  }

  /// Maps a world-space point to its position inside a view (logical
  /// pixels, origin top-left), the forward counterpart of
  /// [screenPointToRay].
  ///
  /// Returns null when [worldPoint] is at or behind the camera plane, where
  /// it has no on-screen projection. Points outside the view bounds still
  /// return a position (negative, or beyond [viewSize]); callers decide
  /// whether to clamp or cull. [viewSize] is the view's logical size (the
  /// constraints `SceneView` renders into).
  ui.Offset? worldToScreen(Vector3 worldPoint, ui.Size viewSize) {
    final clip = getViewTransform(
      viewSize,
    ).transform(Vector4(worldPoint.x, worldPoint.y, worldPoint.z, 1));
    if (clip.w <= 0) {
      return null;
    }
    return ui.Offset(
      (clip.x / clip.w + 1) / 2 * viewSize.width,
      (1 - clip.y / clip.w) / 2 * viewSize.height,
    );
  }

  /// Returns the combined projection-and-view transform for a render target
  /// of the given [dimensions].
  ///
  /// Called once per [Scene.render] call.
  Matrix4 getViewTransform(ui.Size dimensions, {Vector2? jitter}) =>
      projection.getProjectionMatrix(
        dimensions.width / dimensions.height,
        jitter: jitter,
      ) *
      getViewMatrix();

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
  final Vector3 viewDirection = target - position;
  assert(
    viewDirection.length2 > 1e-12,
    'Camera target equals its position, so the view direction is undefined and '
    'the scene renders empty. Move target away from position.',
  );
  assert(
    up.cross(viewDirection).length2 > 1e-12,
    'Camera up is parallel to the view direction (position toward target), so '
    'the view basis is degenerate and the scene renders empty. Use an up vector '
    'that is not parallel to the view direction; for a top-down or bottom-up '
    'camera use Vector3(0, 0, 1) or Vector3(0, 0, -1) in place of '
    'Vector3(0, 1, 0).',
  );
  Vector3 forward = viewDirection.normalized();
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
  double zFar, {
  Vector2? jitter,
}) {
  assert(
    fovRadiansY > 0 && fovRadiansY < pi,
    'fovRadiansY is $fovRadiansY, which is not a valid vertical field of view '
    'in RADIANS (it must be between 0 and pi). A value like 60 is degrees; pass '
    '60 * degrees2Radians instead.',
  );
  assert(
    zNear > 0 && zFar > zNear,
    'The camera frustum is degenerate (near $zNear, far $zFar). near must be '
    'greater than 0 and far must be greater than near, or the depth mapping '
    'collapses and the scene renders empty or Z-fights.',
  );
  double height = tan(fovRadiansY * 0.5);
  double width = height * aspectRatio;
  final jx = jitter?.x ?? 0.0;
  final jy = jitter?.y ?? 0.0;

  return Matrix4(
    1.0 / width,
    0.0,
    0.0,
    0.0,
    0.0,
    1.0 / height,
    0.0,
    0.0,
    jx,
    jy,
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
/// {@category Scene graph}
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

  /// Places a camera to frame [bounds] (a model's world-space AABB, from
  /// [Node.combinedWorldBounds]) so it fills the view.
  ///
  /// The camera looks at the bounds' center from [direction] (the offset from
  /// the center toward the eye; defaults to `(0, 0, -1)`, matching the default
  /// placement and the direction glTF models face after import). The distance
  /// fits the bounds' bounding sphere within the vertical field of view, so it
  /// frames cleanly on a landscape view; [margin] above `1` pulls the camera
  /// back for padding (a portrait view, whose horizontal field of view is
  /// narrower, may want some). The near and far planes are set around the
  /// model so a tiny or a huge one both stay in range.
  factory PerspectiveCamera.framing(
    Aabb3 bounds, {
    Vector3? direction,
    double fovRadiansY = 45 * degrees2Radians,
    Vector3? up,
    double margin = 1.1,
  }) {
    final center = bounds.center;
    final radius = max((bounds.max - bounds.min).length * 0.5, 1e-4);
    final distance = radius / sin(fovRadiansY / 2) * margin;
    final dir = (direction ?? Vector3(0, 0, -1)).normalized();
    return PerspectiveCamera(
      fovRadiansY: fovRadiansY,
      position: center + dir * distance,
      target: center,
      up: up,
      fovNear: max(distance - radius, distance * 1e-3),
      fovFar: distance + radius * 2,
    );
  }

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
  @override
  Vector3 up;

  /// Distance to the near clipping plane. Geometry closer than this is
  /// clipped away.
  double fovNear;

  /// Distance to the far clipping plane. Geometry beyond this is clipped
  /// away. Must be greater than [fovNear].
  double fovFar;

  @override
  CameraProjection get projection => PerspectiveProjection(
    fovRadiansY: fovRadiansY,
    near: fovNear,
    far: fovFar,
  );

  @override
  Vector3 get forward => (target - position).normalized();

  @override
  Matrix4 getViewMatrix() => _matrix4LookAt(position, target, up);
}

Matrix4 _matrix4Orthographic(
  double width,
  double height,
  double zNear,
  double zFar, {
  Vector2? jitter,
}) {
  assert(
    width > 0 && height > 0,
    'The orthographic view box is degenerate (width $width, height $height). '
    'OrthographicProjection.height must be greater than 0, and the render '
    'target must have a positive aspect ratio.',
  );
  assert(
    zFar > zNear,
    'The camera clip range is degenerate (near $zNear, far $zFar). far must be '
    'greater than near, or the depth mapping collapses and the scene renders '
    'empty or Z-fights. Unlike a perspective lens, an orthographic near plane '
    'may be zero or negative.',
  );
  // Matches the engine's clip convention (the perspective path above): +Z is
  // the view direction and depth maps onto [0, 1]. With w fixed at 1, jitter
  // is already in NDC units and lands in the translation column.
  final depth = zFar - zNear;
  return Matrix4(
    2.0 / width,
    0.0,
    0.0,
    0.0, //
    0.0,
    2.0 / height,
    0.0,
    0.0, //
    0.0,
    0.0,
    1.0 / depth,
    0.0, //
    jitter?.x ?? 0.0,
    jitter?.y ?? 0.0,
    -zNear / depth,
    1.0, //
  );
}

/// A camera with a parallel ([OrthographicProjection]) lens, the orthographic
/// counterpart of [PerspectiveCamera].
///
/// Defined by an eye [position], a look-at [target], an [up] direction, the
/// vertical view [height] in world units, and a [near]/[far] clip range.
/// Zooming changes [height] rather than a field of view or the distance to
/// the subject.
///
/// For a classic isometric view, look along `(1, -1, 1)` from a distance:
///
/// ```dart
/// final camera = OrthographicCamera(
///   position: Vector3(20, 20, -20),
///   target: Vector3.zero(),
///   height: 12,
/// );
/// ```
///
/// See [OrthographicProjection] for the post-processing effects a parallel
/// lens cannot support.
/// {@category Scene graph}
class OrthographicCamera extends Camera {
  /// Creates an [OrthographicCamera]. Omitting everything yields an eye at
  /// `(0, 0, -5)` looking at the origin with `+Y` up, showing 10 world units
  /// vertically.
  OrthographicCamera({
    this.height = 10.0,
    Vector3? position,
    Vector3? target,
    Vector3? up,
    this.near = 0.1,
    this.far = 1000.0,
  }) : position = position ?? Vector3(0, 0, -5),
       target = target ?? Vector3(0, 0, 0),
       up = up ?? Vector3(0, 1, 0);

  /// Places a camera to frame [bounds] so it fills the view.
  ///
  /// The camera looks at the bounds' center from [direction] (the offset from
  /// the center toward the eye; defaults to `(0, 0, -1)`). Because a parallel
  /// lens does not shrink with distance, the fit comes entirely from
  /// [height]: it is set to the bounds' bounding-sphere diameter times
  /// [margin]. The eye is pulled back far enough that the whole model stays
  /// inside the clip range on any view direction.
  factory OrthographicCamera.framing(
    Aabb3 bounds, {
    Vector3? direction,
    Vector3? up,
    double margin = 1.1,
  }) {
    final center = bounds.center;
    final radius = max((bounds.max - bounds.min).length * 0.5, 1e-4);
    final distance = radius * 4;
    final dir = (direction ?? Vector3(0, 0, -1)).normalized();
    return OrthographicCamera(
      height: radius * 2 * margin,
      position: center + dir * distance,
      target: center,
      up: up,
      near: distance - radius * 2,
      far: distance + radius * 2,
    );
  }

  /// The vertical extent of the view, in world units.
  double height;

  /// World-space position of the camera (the eye point).
  @override
  Vector3 position;

  /// World-space point the camera is looking at.
  Vector3 target;

  /// World-space "up" direction used to orient the camera around the view
  /// vector. Typically `Vector3(0, 1, 0)`; for a straight top-down view use
  /// `Vector3(0, 0, 1)`, since up may not be parallel to the view direction.
  @override
  Vector3 up;

  /// Distance to the near clipping plane. May be zero or negative.
  double near;

  /// Distance to the far clipping plane. Must be greater than [near].
  double far;

  @override
  CameraProjection get projection =>
      OrthographicProjection(height: height, near: near, far: far);

  @override
  Vector3 get forward => (target - position).normalized();

  @override
  Matrix4 getViewMatrix() => _matrix4LookAt(position, target, up);
}
