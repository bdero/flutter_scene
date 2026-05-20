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
  }

  final int _width;
  final int _height;
  late final web.OffscreenCanvas _canvas;
  late final web.WebGL2RenderingContext _gl;

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

  void dispose() {
    // OffscreenCanvas and its GL context are garbage-collected; nothing to do
    // explicitly. Method exists so callers don't have to special-case the API
    // surface across backends.
  }
}
