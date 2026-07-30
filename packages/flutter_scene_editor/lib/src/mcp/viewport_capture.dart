import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_scene_mcp/flutter_scene_mcp.dart';

/// Builds a [ViewportScreenshot] that captures the viewport's
/// [RepaintBoundary] (identified by [boundaryKey]) as a PNG.
///
/// Pass the same key to `ViewportPanel.repaintBoundaryKey`, then hand the
/// returned callback to an [EditorToolSurface] so an agent's
/// `screenshot_viewport` tool sees exactly what the user sees. This uses
/// Flutter's own layer capture (the composited viewport, including the
/// flutter_scene render), so it is backend-agnostic and needs no engine
/// readback API.
///
/// [pixelRatio] scales the capture relative to logical pixels (use the view's
/// device pixel ratio for a 1:1 capture).
ViewportScreenshot viewportScreenshot(
  GlobalKey boundaryKey, {
  double pixelRatio = 1.0,
}) {
  return () async {
    // Capture after the next painted frame, so a mutation made just before
    // the screenshot (an agent moving the camera, then looking) is in the
    // image. The boundary otherwise serves whatever frame painted last.
    WidgetsBinding.instance.scheduleFrame();
    await WidgetsBinding.instance.endOfFrame;
    final boundary =
        boundaryKey.currentContext?.findRenderObject()
            as RenderRepaintBoundary?;
    if (boundary == null) {
      throw StateError('The viewport is not mounted; cannot capture it');
    }
    final image = await boundary.toImage(pixelRatio: pixelRatio);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) {
        throw StateError('Failed to encode the viewport as PNG');
      }
      return ScreenshotResult(
        pngBytes: data.buffer.asUint8List(),
        width: image.width,
        height: image.height,
      );
    } finally {
      image.dispose();
    }
  };
}
