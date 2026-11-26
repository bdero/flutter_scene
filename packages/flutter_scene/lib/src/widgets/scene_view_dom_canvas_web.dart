import 'package:flutter/rendering.dart' show PlatformViewHitTestBehavior;
import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;

/// Whether this platform can present a scene on a DOM canvas.
const bool sceneDomCanvasSupported = true;

/// A `<canvas>` platform view a [SceneView] presents its frames to, in place
/// of drawing them into Flutter's canvas.
class SceneDomCanvas {
  web.HTMLCanvasElement? _canvas;

  /// Whether the canvas element exists yet. Until it does, frames draw into
  /// Flutter's canvas.
  bool get isAttached => _canvas != null;

  /// The platform view, filling its box. Pointers pass through it to the
  /// widgets and the page beneath, and it adds nothing to semantics.
  Widget build() => ExcludeSemantics(
    child: IgnorePointer(
      child: HtmlElementView.fromTagName(
        tagName: 'canvas',
        hitTestBehavior: PlatformViewHitTestBehavior.transparent,
        onElementCreated: (element) {
          final canvas = element as web.HTMLCanvasElement;
          canvas.style
            ..width = '100%'
            ..height = '100%'
            ..display = 'block'
            ..pointerEvents = 'none';
          _canvas = canvas;
        },
      ),
    ),
  );

  /// Shows [texture] on the canvas.
  void present(gpu.Texture texture) =>
      gpu.gpuHost.presentToCanvas(texture, _canvas!);
}
