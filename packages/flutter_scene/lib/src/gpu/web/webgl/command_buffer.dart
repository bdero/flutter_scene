part of '_webgl.dart';

/// Issues draws while encoding and tracks GPU completion with fences.
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

  // TODO(webgl-buffer-copy): upload through a PIXEL_UNPACK_BUFFER binding
  // once something on WebGL2 needs it. Only compute output uses it, and
  // WebGL2 has no compute.
  @override
  void copyBufferToTexture(BufferView source, TextureRegion destination) =>
      throw UnsupportedError('copyBufferToTexture is not supported on WebGL2.');

  @override
  void submit({CompletionCallback? completionCallback}) {
    _activePass?._finish();
    _activePass = null;
    if (completionCallback != null) {
      _gpuContext._enqueueCompletion(completionCallback);
    }
  }
}

final class _WebGlCompletion {
  _WebGlCompletion(this.sync, this.callbacks);

  final web.WebGLSync sync;
  final List<CompletionCallback> callbacks;
}
