import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;

import 'package:flutter_scene/src/render/render_graph.dart';

/// Manages the swapchain color textures a [Scene] composites onto the
/// Flutter canvas, plus the pools of transient render-graph attachments.
///
/// Each [Scene] owns one `Surface`. A scene may render several views per
/// frame (split-screen, picture-in-picture); each view gets its own
/// swapchain ring and its own transient texture pool, so simultaneous views
/// never share a render target within a frame. View 0 is the single-view
/// default.
///
/// Every view, every frame, the renderer asks the surface for that view's
/// next swapchain color texture via [getNextSwapchainColorTexture]; the
/// surface rotates through a small ring per view so the GPU isn't asked to
/// overwrite one the compositor is still reading. The tone-mapping pass
/// renders the final image into this texture, which is then drawn to the
/// canvas via `Texture.asImage`. Each ring (and the view's transient pool)
/// is dropped and rebuilt whenever that view's requested size changes.
///
/// Applications typically don't interact with `Surface` directly; it is
/// driven internally by [Scene.render] / [Scene.renderViews].
class Surface {
  // TODO(bdero): There should be a method on the Flutter GPU context to pull
  //              this information.
  static const int _maxFramesInFlight = 2;

  final List<_ViewSurface> _views = [];

  _ViewSurface _view(int index) {
    while (_views.length <= index) {
      _views.add(_ViewSurface());
    }
    return _views[index];
  }

  /// The transient texture pool for view [viewIndex] (the intermediate
  /// render-graph attachments: HDR scene color, depth, shadow maps,
  /// post-process buffers). Each view has its own pool so simultaneous
  /// views in a frame never share an attachment.
  TransientTexturePool transientTexturePool([int viewIndex = 0]) =>
      _view(viewIndex).pool;

  /// Returns the next 8-bit swapchain color texture for view [viewIndex] at
  /// [size], advancing that view's frame. The ring (and the view's
  /// transient pool) are dropped and rebuilt whenever [size] changes from
  /// the view's previous call.
  gpu.Texture getNextSwapchainColorTexture(Size size, [int viewIndex = 0]) =>
      _view(viewIndex).nextSwapchainColor(size);
}

/// One view's swapchain color ring plus its transient texture pool. View 0
/// reproduces the historical single-view behavior exactly.
class _ViewSurface {
  final TransientTexturePool pool = TransientTexturePool(
    framesInFlight: Surface._maxFramesInFlight,
  );

  final List<gpu.Texture> _swapchainColors = [];
  int _cursor = 0;
  Size _previousSize = const Size(0, 0);

  gpu.Texture nextSwapchainColor(Size size) {
    pool.beginFrame();
    if (size != _previousSize) {
      _cursor = 0;
      _swapchainColors.clear();
      pool.clear();
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
        ),
      );
    }
    final result = _swapchainColors[_cursor];
    _cursor = (_cursor + 1) % Surface._maxFramesInFlight;
    return result;
  }
}
