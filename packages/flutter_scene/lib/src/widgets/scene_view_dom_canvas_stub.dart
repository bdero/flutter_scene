import 'package:flutter/widgets.dart';

import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;

/// Whether this platform can present a scene on a DOM canvas.
const bool sceneDomCanvasSupported = false;

/// Never attached here; see the web implementation.
class SceneDomCanvas {
  bool get isAttached => false;

  Widget build() => const SizedBox.shrink();

  void present(gpu.Texture texture) {}
}
