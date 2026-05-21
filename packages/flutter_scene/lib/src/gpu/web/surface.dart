part of '_gpu.dart';

/// A WebGL2-backed offscreen render target that can be snapshotted into a
/// `ui.Image` for display by Flutter.
///
/// Only exists to validate the WebGL2 -> ui.Image bridge on CanvasKit and
/// Skwasm. The surface API will likely change once that's confirmed.
class Surface {
  Surface({required int width, required int height})
    : _width = width,
      _height = height {
    _canvas = web.OffscreenCanvas(width, height);
    final gl = _canvas.getContext('webgl2') as web.WebGL2RenderingContext?;
    if (gl == null) {
      throw StateError(
        'WebGL2 is not available. Cannot create a flutter_gpu_shim Surface.',
      );
    }
    _gl = gl;
    // Cache the lose-context extension at construction time. After a context
    // loss some browsers return null from `getExtension`, so resolving the
    // ref later would break `forceContextRestore`.
    _loseContextExt =
        _gl.getExtension('WEBGL_lose_context') as _WebGLLoseContext?;
    _canvas.addEventListener('webglcontextlost', _onLost.toJS);
    _canvas.addEventListener('webglcontextrestored', _onRestored.toJS);
  }

  final int _width;
  final int _height;
  late final web.OffscreenCanvas _canvas;
  late final web.WebGL2RenderingContext _gl;
  late final _WebGLLoseContext? _loseContextExt;

  /// True once the underlying WebGL2 context has been lost.
  bool isLost = false;

  /// Fired when the WebGL2 context is lost. The surface should be considered
  /// unusable until [onContextRestored] fires.
  void Function()? onContextLost;

  /// Fired when the WebGL2 context is restored. All GPU resources owned by
  /// the surface are gone and must be re-created by the caller.
  void Function()? onContextRestored;

  void _onLost(web.Event event) {
    event.preventDefault();
    isLost = true;
    onContextLost?.call();
  }

  void _onRestored(web.Event event) {
    isLost = false;
    onContextRestored?.call();
  }

  int get width => _width;
  int get height => _height;
  web.WebGL2RenderingContext get gl => _gl;

  void clearToColor(double r, double g, double b, double a) {
    _gl.clearColor(r, g, b, a);
    _gl.clear(web.WebGL2RenderingContext.COLOR_BUFFER_BIT);
  }

  /// Snapshot the current contents of the offscreen canvas into a `ui.Image`.
  ///
  /// When [transferOwnership] is true, the engine takes ownership of the
  /// underlying texture and can avoid an intermediate copy. The surface
  /// becomes unusable afterwards.
  FutureOr<ui.Image> snapshot({bool transferOwnership = false}) {
    return ui_web.createImageFromTextureSource(
      _canvas as JSAny,
      width: _width,
      height: _height,
      transferOwnership: transferOwnership,
    );
  }

  /// Force a WebGL context loss for testing purposes. Returns true if the
  /// `WEBGL_lose_context` extension was available and the loss was triggered.
  bool forceContextLoss() {
    final ext = _loseContextExt;
    if (ext == null) return false;
    ext.loseContext();
    return true;
  }

  /// Request that a previously-lost context be restored. Returns true if the
  /// extension was available and the request was issued. The browser is free
  /// to ignore the request — wait for the `onContextRestored` callback before
  /// assuming recovery; for guaranteed recovery, dispose this Surface and
  /// create a new one.
  bool forceContextRestore() {
    final ext = _loseContextExt;
    if (ext == null) return false;
    ext.restoreContext();
    return true;
  }

  void dispose() {
    // OffscreenCanvas + GL context are GC'd. Listeners are unowned and will
    // be cleaned up when the canvas is collected.
  }
}

extension type _WebGLLoseContext._(JSObject _) implements JSObject {
  external void loseContext();
  external void restoreContext();
}
