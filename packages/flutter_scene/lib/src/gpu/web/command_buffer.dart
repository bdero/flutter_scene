part of '_gpu.dart';

/// CommandBuffer is a thin convenience wrapper. WebGL2 doesn't batch like
/// Vulkan or Metal - GL calls execute immediately - so `submit` is a
/// no-op and `createRenderPass` returns a pass that drives the GL context
/// in place.
base class CommandBuffer {
  CommandBuffer._(this._gpuContext);

  final GpuContext _gpuContext;
  RenderPass? _activePass;

  RenderPass createRenderPass(RenderTarget renderTarget) {
    // Starting a new pass ends the previous one (triggers its MSAA resolve),
    // so a subsequent pass that samples the resolve texture sees finished
    // contents.
    _activePass?._finish();
    final pass = RenderPass._(_gpuContext, renderTarget);
    _activePass = pass;
    return pass;
  }

  void submit({CompletionCallback? completionCallback}) {
    // WebGL2 commands are already submitted; finishing the last pass runs
    // its MSAA resolve. `gl.flush()` is implicit at raster boundaries.
    _activePass?._finish();
    _activePass = null;
    completionCallback?.call(CompletionStatus.successful);
  }
}

enum CompletionStatus { successful, error }

typedef CompletionCallback = void Function(CompletionStatus status);
