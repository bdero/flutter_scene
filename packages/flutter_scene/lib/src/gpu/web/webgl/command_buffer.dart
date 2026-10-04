part of '_webgl.dart';

/// CommandBuffer is a thin convenience wrapper. WebGL2 doesn't batch like
/// Vulkan or Metal - GL calls execute immediately - so `submit` is a
/// no-op and `createRenderPass` returns a pass that drives the GL context
/// in place.
final class WebGlCommandBuffer extends CommandBuffer {
  WebGlCommandBuffer._(this._gpuContext);

  final WebGlContext _gpuContext;
  WebGlRenderPass? _activePass;

  @override
  RenderPass createRenderPass(RenderTarget renderTarget) {
    // Starting a new pass ends the previous one (triggers its MSAA resolve),
    // so a subsequent pass that samples the resolve texture sees finished
    // contents.
    _activePass?._finish();
    final pass = WebGlRenderPass._(_gpuContext, renderTarget);
    _activePass = pass;
    return pass;
  }

  @override
  void submit({CompletionCallback? completionCallback}) {
    // WebGL2 commands are already submitted; finishing the last pass runs
    // its MSAA resolve. `gl.flush()` is implicit at raster boundaries.
    _activePass?._finish();
    _activePass = null;
    completionCallback?.call(CompletionStatus.successful);
  }
}
