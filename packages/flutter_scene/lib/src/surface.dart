import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_gpu/gpu.dart' as gpu;

/// Manages a small ring of [gpu.RenderTarget]s used to draw a [Scene].
///
/// Each [Scene] owns one `Surface`. On every frame the renderer asks the
/// surface for a render target via [getNextRenderTarget]; the surface
/// either reuses an existing target from its ring or creates a new one
/// (along with an MSAA resolve attachment if requested). The ring resets
/// whenever the requested size changes.
///
/// Applications typically don't interact with `Surface` directly — it is
/// driven internally by [Scene.render].
class Surface {
  // TODO(bdero): There should be a method on the Flutter GPU context to pull
  //              this information.
  final int _maxFramesInFlight = 2;
  // TODO(bdero): There's no need to track whole RenderTargets in a rotating
  //              list. Only the color texture needs to be swapped out for
  //              properly synchronizing with the canvas.
  final List<gpu.RenderTarget> _renderTargets = [];
  int _cursor = 0;
  Size _previousSize = const Size(0, 0);

  /// Returns the next [gpu.RenderTarget] in the rotating ring.
  ///
  /// Allocates a fresh target (color + depth attachments, plus a 4x MSAA
  /// resolve attachment when [enableMsaa] is `true`) when the ring is not
  /// yet full. The ring is dropped and rebuilt whenever [size] changes
  /// from the previous call.
  gpu.RenderTarget getNextRenderTarget(Size size, bool enableMsaa) {
    if (size != _previousSize) {
      _cursor = 0;
      _renderTargets.clear();
      _previousSize = size;
    }
    if (_cursor == _renderTargets.length) {
      final gpu.Texture colorTexture = gpu.gpuContext.createTexture(
        gpu.StorageMode.devicePrivate,
        size.width.toInt(),
        size.height.toInt(),
        enableRenderTargetUsage: true,
        enableShaderReadUsage: true,
        coordinateSystem: gpu.TextureCoordinateSystem.renderToTexture,
      );
      final colorAttachment = gpu.ColorAttachment(texture: colorTexture);
      if (enableMsaa) {
        final gpu.Texture msaaColorTexture = gpu.gpuContext.createTexture(
          gpu.StorageMode.deviceTransient,
          size.width.toInt(),
          size.height.toInt(),
          sampleCount: 4,
          enableRenderTargetUsage: true,
          coordinateSystem: gpu.TextureCoordinateSystem.renderToTexture,
        );
        colorAttachment.resolveTexture = colorAttachment.texture;
        colorAttachment.texture = msaaColorTexture;
        colorAttachment.storeAction = gpu.StoreAction.multisampleResolve;
      }
      final gpu.Texture depthTexture = gpu.gpuContext.createTexture(
        gpu.StorageMode.deviceTransient,
        size.width.toInt(),
        size.height.toInt(),
        sampleCount: enableMsaa ? 4 : 1,
        format: gpu.gpuContext.defaultDepthStencilFormat,
        enableRenderTargetUsage: true,
        coordinateSystem: gpu.TextureCoordinateSystem.renderToTexture,
      );
      final renderTarget = gpu.RenderTarget.singleColor(
        colorAttachment,
        depthStencilAttachment: gpu.DepthStencilAttachment(
          texture: depthTexture,
          depthClearValue: 1.0,
        ),
      );
      _renderTargets.add(renderTarget);
    }
    gpu.RenderTarget result = _renderTargets[_cursor];
    _cursor = (_cursor + 1) % _maxFramesInFlight;
    return result;
  }
}
