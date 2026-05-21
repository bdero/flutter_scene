part of '_gpu.dart';

/// CommandBuffer is a thin convenience wrapper. WebGL2 doesn't batch like
/// Vulkan or Metal - GL calls execute immediately - so `submit` is a
/// no-op and `createRenderPass` returns a pass that drives the GL context
/// in place.
base class CommandBuffer {
  CommandBuffer._(this._gpuContext);

  final GpuContext _gpuContext;

  RenderPass createRenderPass(RenderTarget renderTarget) {
    return RenderPass._(_gpuContext, renderTarget);
  }

  void submit({CompletionCallback? completionCallback}) {
    // WebGL2 commands are already submitted; `gl.flush()` is implicit at
    // tab/raster boundaries. Fire the callback synchronously for API parity.
    completionCallback?.call(CompletionStatus.successful);
  }
}

enum CompletionStatus { successful, error }

typedef CompletionCallback = void Function(CompletionStatus status);
