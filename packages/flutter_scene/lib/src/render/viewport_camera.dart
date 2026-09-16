import 'dart:ui' as ui;

import 'package:vector_math/vector_math.dart';

import 'package:flutter_scene/src/camera.dart';

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
/// [ViewportBoundProjection]).
class ViewportBoundCamera extends Camera {
  ViewportBoundCamera(this.inner, ui.Size viewportSize)
    : projection = ViewportBoundProjection(inner.projection, viewportSize);

  /// The camera being rendered.
  final Camera inner;

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
}
