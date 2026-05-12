import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_gpu/gpu.dart' as gpu;

import 'package:flutter_scene/src/render/render_graph.dart';

/// Manages the swapchain color textures a [Scene] composites onto the
/// Flutter canvas, plus the pool of transient render-graph attachments.
///
/// Each [Scene] owns one `Surface`. Every frame the renderer asks the
/// surface for the next swapchain color texture via
/// [getNextSwapchainColorTexture]; the surface rotates through a small
/// ring of textures so the GPU isn't asked to overwrite one the
/// compositor is still reading. The tone-mapping pass renders the final
/// image into this texture, which is then drawn to the canvas via
/// `Texture.asImage`. The ring (and the transient texture pool) are
/// dropped and rebuilt whenever the requested size changes.
///
/// Applications typically don't interact with `Surface` directly; it is
/// driven internally by [Scene.render].
class Surface {
  // TODO(bdero): There should be a method on the Flutter GPU context to pull
  //              this information.
  static const int _maxFramesInFlight = 2;

  /// Pool of transient textures used as intermediate render targets by
  /// the render graph (the HDR scene color, MSAA color, depth, shadow
  /// maps, post-process buffers, ...). Empty until a pass acquires one.
  final TransientTexturePool transientTexturePool = TransientTexturePool(
    framesInFlight: _maxFramesInFlight,
  );

  final List<gpu.Texture> _swapchainColors = [];
  int _cursor = 0;
  Size _previousSize = const Size(0, 0);

  /// Returns the next 8-bit color texture in the rotating swapchain ring,
  /// allocating one when the ring isn't yet full. The ring (and the
  /// transient texture pool) are dropped and rebuilt whenever [size]
  /// changes from the previous call.
  gpu.Texture getNextSwapchainColorTexture(Size size) {
    transientTexturePool.beginFrame();
    if (size != _previousSize) {
      _cursor = 0;
      _swapchainColors.clear();
      transientTexturePool.clear();
      _previousSize = size;
    }
    if (_cursor == _swapchainColors.length) {
      _swapchainColors.add(
        gpu.gpuContext.createTexture(
          gpu.StorageMode.devicePrivate,
          size.width.toInt(),
          size.height.toInt(),
          enableRenderTargetUsage: true,
          enableShaderReadUsage: true,
          coordinateSystem: gpu.TextureCoordinateSystem.renderToTexture,
        ),
      );
    }
    final result = _swapchainColors[_cursor];
    _cursor = (_cursor + 1) % _maxFramesInFlight;
    return result;
  }
}
