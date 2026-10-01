import 'dart:ui' as ui;

import 'package:vector_math/vector_math.dart';

import 'package:flutter_scene/src/camera.dart';
import 'package:flutter_scene/src/render/depth_raster.dart';

/// A [CameraProjection] resolved against one view's logical size, whatever
/// size a render pass later asks for.
///
/// Passes size their targets in physical, render-scaled pixels, while picking
/// measures the view in logical pixels. Binding the projection to the logical
/// size keeps a size-dependent projection (an orthographic pixels-per-unit
/// size) rendering the same volume picking hits.
class ViewportBoundProjection extends CameraProjection {
  ViewportBoundProjection(this.inner, this.viewportSize);

  /// The projection being resolved.
  final CameraProjection inner;

  /// The view's logical size.
  final ui.Size viewportSize;

  @override
  Matrix4 getProjectionMatrix(double aspectRatio, {Vector2? jitter}) =>
      inner.getProjectionMatrixForViewport(viewportSize, jitter: jitter);

  @override
  Matrix4 getProjectionMatrixForViewport(
    ui.Size viewportSize, {
    Vector2? jitter,
  }) => inner.getProjectionMatrixForViewport(this.viewportSize, jitter: jitter);
}

/// [camera] with its projection bound to [viewportSize] logical pixels (see
/// [ViewportBoundProjection]), plus the [raster] its passes draw with.
///
/// [getViewTransform] stays the standard mapping, which CPU culling, picking,
/// and temporal reprojection read. Passes that rasterize into the view's depth
/// buffers draw with [rasterViewTransform] instead.
class ViewportBoundCamera extends Camera {
  ViewportBoundCamera(
    this.inner,
    ui.Size viewportSize, {
    this.raster = DepthRaster.standard,
  }) : projection = ViewportBoundProjection(inner.projection, viewportSize);

  /// The camera being rendered.
  final Camera inner;

  /// How this view's camera passes rasterize depth.
  final DepthRaster raster;

  @override
  final ViewportBoundProjection projection;

  @override
  Vector3 get position => inner.position;

  @override
  Vector3 get forward => inner.forward;

  @override
  Vector3 get up => inner.up;

  @override
  Matrix4 getViewMatrix() => inner.getViewMatrix();

  /// The view-projection the view's camera passes rasterize with, under
  /// [raster].
  Matrix4 rasterViewTransform({Vector2? jitter}) =>
      rasterProjectionMatrix(
        projection.inner,
        projection.viewportSize,
        raster,
        jitter: jitter,
      ) *
      getViewMatrix();
}

/// How passes drawing for [camera] rasterize depth (the standard mapping for
/// a camera that is not a view's [ViewportBoundCamera]).
DepthRaster depthRasterOf(Camera camera) =>
    camera is ViewportBoundCamera ? camera.raster : DepthRaster.standard;

/// The view-projection a pass drawing for [camera] into a [dimensions] target
/// rasterizes with.
Matrix4 rasterViewTransformOf(
  Camera camera,
  ui.Size dimensions, {
  Vector2? jitter,
}) => camera is ViewportBoundCamera
    ? camera.rasterViewTransform(jitter: jitter)
    : camera.getViewTransform(dimensions, jitter: jitter);

/// [camera]'s standard view-projection with an infinite far plane pulled in
/// to [far], for volumes that must stay bounded (shadow receiver culling).
Matrix4 finiteViewTransformOf(Camera camera, ui.Size dimensions, double far) {
  final projection = camera.projection;
  final inner = projection is ViewportBoundProjection
      ? projection.inner
      : projection;
  if (inner.runtimeType == PerspectiveProjection) {
    final perspective = inner as PerspectiveProjection;
    if (!perspective.far.isFinite) {
      final viewport = projection is ViewportBoundProjection
          ? projection.viewportSize
          : dimensions;
      final finite = PerspectiveProjection(
        fovRadiansY: perspective.fovRadiansY,
        near: perspective.near,
        far: far > perspective.near * 2 ? far : perspective.near * 2,
      );
      return finite.getProjectionMatrixForViewport(viewport) *
          camera.getViewMatrix();
    }
  }
  return camera.getViewTransform(dimensions);
}

/// The frustum CPU culling tests against for [camera], from the standard
/// view-projection (a reversed or infinite projection loses its far plane in
/// Gribb-Hartmann extraction).
Frustum cullingFrustumOf(Camera camera, ui.Size dimensions) =>
    cullingFrustum(camera.getViewTransform(dimensions));

/// The six clip planes of [viewProjection], with a far plane that an infinite
/// projection leaves degenerate replaced by one that culls nothing.
Frustum cullingFrustum(Matrix4 viewProjection) {
  final frustum = Frustum.matrix(viewProjection);
  for (final plane in [
    frustum.plane0,
    frustum.plane1,
    frustum.plane2,
    frustum.plane3,
    frustum.plane4,
    frustum.plane5,
  ]) {
    final n = plane.normal;
    if (!(n.x.isFinite && n.y.isFinite && n.z.isFinite) ||
        !plane.constant.isFinite) {
      plane.setFromComponents(0.0, 0.0, 0.0, 1.0);
    }
  }
  return frustum;
}
