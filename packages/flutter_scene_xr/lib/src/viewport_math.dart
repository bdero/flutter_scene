import 'dart:ui' show Rect;

/// Converts a pixel viewport stated in OpenGL's bottom-left convention
/// (what `XRWebGLLayer.getViewport` and `XRWebGLSubImage.viewport` give)
/// into the normalized, top-left [Rect] a `RenderView.viewport` takes.
Rect normalizedViewportFromGl({
  required int x,
  required int y,
  required int width,
  required int height,
  required int targetWidth,
  required int targetHeight,
}) {
  if (targetWidth <= 0 || targetHeight <= 0) {
    return const Rect.fromLTWH(0, 0, 1, 1);
  }
  return Rect.fromLTWH(
    x / targetWidth,
    1.0 - (y + height) / targetHeight,
    width / targetWidth,
    height / targetHeight,
  );
}
