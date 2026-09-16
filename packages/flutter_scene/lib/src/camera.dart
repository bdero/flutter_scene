import 'dart:math';
import 'dart:ui' as ui;

import 'package:vector_math/vector_math.dart';

/// A lens projection that maps view-space coordinates into clip space.
///
/// The projection is the half of a camera that does not depend on where the
/// camera is or what it looks at, only on the lens (field of view, clip
/// planes) and the render target's aspect ratio. Pair one with a view (a
/// [Camera]'s [Camera.getViewMatrix]) to form a full view-projection
/// transform. [PerspectiveProjection] and [OrthographicProjection] are built
/// in; applications can implement [CameraProjection] for others.
///
/// The renderer reads the projection's kind from its matrix, not its type, so
/// a custom pinhole or parallel projection (including an off-center one) gets
/// the same depth-based effects as the built-ins.
/// {@category Scene graph}
abstract class CameraProjection {
  /// Returns the projection matrix for a render target of the given
  /// [aspectRatio] (width / height).
  Matrix4 getProjectionMatrix(double aspectRatio, {Vector2? jitter});

  /// Returns the projection matrix for a view [viewportSize] in logical pixels.
  ///
  /// The engine renders and picks through this, always passing the view's
  /// logical size (never the render target's physical size), so a projection
  /// whose volume follows the view's size renders what picking hits at any
  /// device pixel ratio or render scale. The default uses only the aspect
  /// ratio.
  Matrix4 getProjectionMatrixForViewport(
    ui.Size viewportSize, {
    Vector2? jitter,
  }) => getProjectionMatrix(
    viewportSize.width / viewportSize.height,
    jitter: jitter,
  );
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
    final uv = projectToScreenUv(worldPoint, viewSize);
    if (uv == null) {
      return null;
    }
    return ui.Offset(uv.x * viewSize.width, uv.y * viewSize.height);
  }

  /// Maps a world-space point to screen UV (origin top-left, `0..1` across
  /// [viewport]). The projection [worldToScreen] scales to pixels, so the two
  /// cannot disagree. Returns null when [worldPoint] is at or behind the
  /// camera plane. Values outside `0..1` are a point off screen; callers
  /// decide whether to clamp or cull.
  Vector2? projectToScreenUv(Vector3 worldPoint, ui.Size viewport) {
    final clip = getViewTransform(
      viewport,
    ).transform(Vector4(worldPoint.x, worldPoint.y, worldPoint.z, 1));
    if (clip.w <= 0) {
      return null;
    }
    return Vector2((clip.x / clip.w + 1) / 2, (1 - clip.y / clip.w) / 2);
  }

  /// Returns the combined projection-and-view transform for a view of the
  /// given [dimensions], in logical pixels (see
  /// [CameraProjection.getProjectionMatrixForViewport]).
  ///
  /// Called once per [Scene.render] call.
  Matrix4 getViewTransform(ui.Size dimensions, {Vector2? jitter}) =>
      projection.getProjectionMatrixForViewport(dimensions, jitter: jitter) *
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

/// How an [OrthographicProjection] sizes its view volume against the render
/// target's aspect ratio. Sizes are full world-unit extents, not half extents.
/// {@category Scene graph}
sealed class OrthographicSize {
  const OrthographicSize();

  /// Shows [height] world units vertically; the width follows the aspect ratio.
  const factory OrthographicSize.height(double height) = OrthographicHeight;

  /// Shows [width] world units horizontally; the height follows the aspect
  /// ratio.
  const factory OrthographicSize.width(double width) = OrthographicWidth;

  /// Shows at least [width] by [height] world units, growing one axis to match
  /// the aspect ratio so the whole area stays visible.
  const factory OrthographicSize.contain(double width, double height) =
      OrthographicContain;

  /// Shows at most [width] by [height] world units, cropping one axis to match
  /// the aspect ratio so the view is filled.
  const factory OrthographicSize.cover(double width, double height) =
      OrthographicCover;

  /// Shows exactly [width] by [height] world units, stretching the image when
  /// the aspect ratio differs.
  const factory OrthographicSize.stretch(double width, double height) =
      OrthographicStretch;

  /// Shows one world unit per [pixelsPerUnit] logical pixels of the view, so
  /// on-screen size stays constant as the view resizes (more of the world
  /// shows in a bigger view).
  ///
  /// For crisp pixel art with `N` screen pixels per art texel, pair it with a
  /// render scale that makes the render target `1/N` of the view's physical
  /// size (`Scene.renderScale = 1 / (N * devicePixelRatio)`) and
  /// `FilterQuality.none`.
  const factory OrthographicSize.pixelsPerUnit(double pixelsPerUnit) =
      OrthographicPixelsPerUnit;

  /// The visible (width, height) in world units for a view of [viewportSize]
  /// logical pixels.
  Vector2 visibleSize(ui.Size viewportSize);
}

double _aspectOf(ui.Size viewportSize) =>
    viewportSize.height > 0 ? viewportSize.width / viewportSize.height : 1.0;

/// [OrthographicSize.height]: a fixed visible height.
/// {@category Scene graph}
final class OrthographicHeight extends OrthographicSize {
  /// Creates a size showing [height] world units vertically.
  const OrthographicHeight(this.height);

  /// The visible height in world units.
  final double height;

  @override
  Vector2 visibleSize(ui.Size viewportSize) =>
      Vector2(height * _aspectOf(viewportSize), height);
}

/// [OrthographicSize.width]: a fixed visible width.
/// {@category Scene graph}
final class OrthographicWidth extends OrthographicSize {
  /// Creates a size showing [width] world units horizontally.
  const OrthographicWidth(this.width);

  /// The visible width in world units.
  final double width;

  @override
  Vector2 visibleSize(ui.Size viewportSize) =>
      Vector2(width, width / _aspectOf(viewportSize));
}

/// [OrthographicSize.contain]: a minimum visible area.
/// {@category Scene graph}
final class OrthographicContain extends OrthographicSize {
  /// Creates a size that keeps [width] by [height] world units visible.
  const OrthographicContain(this.width, this.height);

  /// The minimum visible width in world units.
  final double width;

  /// The minimum visible height in world units.
  final double height;

  @override
  Vector2 visibleSize(ui.Size viewportSize) {
    final aspectRatio = _aspectOf(viewportSize);
    return aspectRatio * height >= width
        ? Vector2(height * aspectRatio, height)
        : Vector2(width, width / aspectRatio);
  }
}

/// [OrthographicSize.cover]: a maximum visible area.
/// {@category Scene graph}
final class OrthographicCover extends OrthographicSize {
  /// Creates a size that fills the view from [width] by [height] world units.
  const OrthographicCover(this.width, this.height);

  /// The maximum visible width in world units.
  final double width;

  /// The maximum visible height in world units.
  final double height;

  @override
  Vector2 visibleSize(ui.Size viewportSize) {
    final aspectRatio = _aspectOf(viewportSize);
    return aspectRatio * height <= width
        ? Vector2(height * aspectRatio, height)
        : Vector2(width, width / aspectRatio);
  }
}

/// [OrthographicSize.stretch]: an exact visible area.
/// {@category Scene graph}
final class OrthographicStretch extends OrthographicSize {
  /// Creates a size showing exactly [width] by [height] world units.
  const OrthographicStretch(this.width, this.height);

  /// The visible width in world units.
  final double width;

  /// The visible height in world units.
  final double height;

  @override
  Vector2 visibleSize(ui.Size viewportSize) => Vector2(width, height);
}

/// [OrthographicSize.pixelsPerUnit]: a fixed scale in logical pixels.
/// {@category Scene graph}
final class OrthographicPixelsPerUnit extends OrthographicSize {
  /// Creates a size showing one world unit per [pixelsPerUnit] logical pixels.
  const OrthographicPixelsPerUnit(this.pixelsPerUnit);

  /// Logical pixels of the view per world unit.
  final double pixelsPerUnit;

  @override
  Vector2 visibleSize(ui.Size viewportSize) => Vector2(
    viewportSize.width / pixelsPerUnit,
    viewportSize.height / pixelsPerUnit,
  );
}

/// A parallel projection: objects keep their size at any distance, for
/// isometric, top-down, pixel-art, CAD, and 2.5D views.
///
/// The view volume is a box along the camera's forward axis from [near] to
/// [far], sized by [size] and divided by [zoom]. Unlike a perspective
/// projection, [near] may be negative, which puts the volume's front behind
/// the eye so an isometric camera does not clip what sits close to it.
///
/// ```dart
/// final camera = OrthographicCamera(
///   position: Vector3(10, 10, 10),
///   target: Vector3.zero(),
///   projection: OrthographicProjection(size: OrthographicSize.height(12)),
/// );
/// ```
/// {@category Scene graph}
class OrthographicProjection extends CameraProjection {
  /// Creates an [OrthographicProjection] showing [size] world units, divided
  /// by [zoom] and shifted by [offset], between [near] and [far].
  OrthographicProjection({
    this.size = const OrthographicSize.height(10.0),
    this.zoom = 1.0,
    Vector2? offset,
    this.near = 0.0,
    this.far = 1000.0,
  }) : offset = offset ?? Vector2.zero();

  /// An explicit view volume in view-space world units, independent of the
  /// render target's aspect ratio (it stretches to fit).
  factory OrthographicProjection.bounds({
    required double left,
    required double right,
    required double bottom,
    required double top,
    double near = 0.0,
    double far = 1000.0,
  }) => OrthographicProjection(
    size: OrthographicSize.stretch(right - left, top - bottom),
    offset: Vector2((left + right) * 0.5, (bottom + top) * 0.5),
    near: near,
    far: far,
  );

  /// The orthographic projection that frames the plane [distance] in front of
  /// the camera the same way a perspective projection with [fovRadiansY] does,
  /// for switching projections without the view jumping.
  factory OrthographicProjection.matchingPerspective({
    required double fovRadiansY,
    required double distance,
    double near = 0.0,
    double far = 1000.0,
  }) => OrthographicProjection(
    size: OrthographicSize.height(2.0 * distance * tan(fovRadiansY * 0.5)),
    near: near,
    far: far,
  );

  /// How the view volume is sized against the render target's aspect ratio.
  OrthographicSize size;

  /// Magnification. The visible extent is [size] divided by this, so 2 shows
  /// half as much, twice as large.
  double zoom;

  /// Shifts the view volume across the view plane, in world units along the
  /// camera's right (x) and up (y) axes, without moving the camera.
  Vector2 offset;

  /// Signed distance along the view direction to the near clipping plane.
  /// Negative values extend the volume behind the eye.
  double near;

  /// Signed distance along the view direction to the far clipping plane. Must
  /// be greater than [near].
  double far;

  /// The visible (width, height) in world units for a view of [viewportSize]
  /// logical pixels, after [zoom].
  Vector2 visibleSize(ui.Size viewportSize) =>
      size.visibleSize(viewportSize) / zoom;

  /// Resolves [size] against a unit-height view of [aspectRatio]. An
  /// [OrthographicSize.pixelsPerUnit] size needs the view's real size, which
  /// the engine supplies through [getProjectionMatrixForViewport].
  @override
  Matrix4 getProjectionMatrix(double aspectRatio, {Vector2? jitter}) =>
      getProjectionMatrixForViewport(ui.Size(aspectRatio, 1.0), jitter: jitter);

  @override
  Matrix4 getProjectionMatrixForViewport(
    ui.Size viewportSize, {
    Vector2? jitter,
  }) {
    final extent = visibleSize(viewportSize);
    return _matrix4Orthographic(
      extent.x,
      extent.y,
      offset.x,
      offset.y,
      near,
      far,
      jitter: jitter,
    );
  }
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

Matrix4 _matrix4Orthographic(
  double width,
  double height,
  double offsetX,
  double offsetY,
  double zNear,
  double zFar, {
  Vector2? jitter,
}) {
  assert(
    width > 0 && height > 0 && width.isFinite && height.isFinite,
    'The orthographic view volume is ${width}x$height world units. Both '
    'extents must be positive and finite; check the size and a zoom of zero.',
  );
  assert(
    zFar > zNear,
    'The orthographic view volume is degenerate (near $zNear, far $zFar). far '
    'must be greater than near, or the depth mapping collapses.',
  );
  final sx = 2.0 / width;
  final sy = 2.0 / height;
  final depthScale = 1.0 / (zFar - zNear);
  return Matrix4(
    sx,
    0.0,
    0.0,
    0.0,
    0.0,
    sy,
    0.0,
    0.0,
    0.0,
    0.0,
    depthScale,
    0.0,
    -offsetX * sx + (jitter?.x ?? 0.0),
    -offsetY * sy + (jitter?.y ?? 0.0),
    -zNear * depthScale,
    1.0,
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

/// A camera with a parallel [OrthographicProjection], placed by eye/target/up
/// like [PerspectiveCamera].
///
/// Because an orthographic view has no perspective, moving the eye along the
/// view direction does not change the image size; use
/// [OrthographicProjection.zoom] or [OrthographicProjection.size] to frame.
/// The eye still sets where the volume starts, since [OrthographicProjection]
/// clip distances are measured from it.
/// {@category Scene graph}
class OrthographicCamera extends Camera {
  /// Creates an [OrthographicCamera]. Defaults match [PerspectiveCamera] (eye
  /// at `(0, 0, -5)` looking at the origin, `+Y` up) with a default
  /// [OrthographicProjection].
  OrthographicCamera({
    OrthographicProjection? projection,
    Vector3? position,
    Vector3? target,
    Vector3? up,
  }) : projection = projection ?? OrthographicProjection(),
       position = position ?? Vector3(0, 0, -5),
       target = target ?? Vector3(0, 0, 0),
       up = up ?? Vector3(0, 1, 0);

  /// Places a camera to frame [bounds] (a model's world-space AABB, from
  /// [Node.combinedWorldBounds]) so it fills the view on any aspect ratio.
  ///
  /// The camera looks at the bounds' center from [direction] (defaults to
  /// `(0, 0, -1)`, as [PerspectiveCamera.framing]). The volume contains the
  /// bounds' bounding sphere, scaled by [margin], and its clip planes enclose
  /// it.
  factory OrthographicCamera.framing(
    Aabb3 bounds, {
    Vector3? direction,
    Vector3? up,
    double margin = 1.1,
  }) {
    final center = bounds.center;
    final radius = max((bounds.max - bounds.min).length * 0.5, 1e-4);
    final reach = radius * margin;
    final dir = (direction ?? Vector3(0, 0, -1)).normalized();
    return OrthographicCamera(
      projection: OrthographicProjection(
        size: OrthographicSize.contain(reach * 2.0, reach * 2.0),
        far: reach * 2.0,
      ),
      position: center + dir * reach,
      target: center,
      up: up,
    );
  }

  /// The lens. Mutate its fields, or assign a new one, to reframe.
  @override
  OrthographicProjection projection;

  /// World-space position of the eye, the origin the clip distances are
  /// measured from.
  @override
  Vector3 position;

  /// World-space point the camera is looking at.
  Vector3 target;

  /// World-space "up" direction used to orient the camera around the view
  /// vector.
  @override
  Vector3 up;

  @override
  Vector3 get forward => (target - position).normalized();

  @override
  Matrix4 getViewMatrix() => _matrix4LookAt(position, target, up);
}
