part of '_gpu.dart';

// `Surface` is a web-only concept: it bridges a WebGL2 OffscreenCanvas into a
// `ui.Image` so the result can be displayed in a Flutter widget. On native
// (Impeller) platforms, the equivalent is a flutter_gpu Texture displayed via
// the Texture widget; the shim does not abstract that here.
//
// This stub exists only so the unified `package:flutter_gpu_shim/gpu.dart`
// entry point compiles on native targets. Calling any method throws.
class Surface {
  Surface({required int width, required int height}) {
    throw UnimplementedError(
      'Surface is only implemented on web. On native targets, use '
      'flutter_gpu directly with a Texture widget.',
    );
  }

  int get width => throw UnimplementedError();
  int get height => throw UnimplementedError();

  void clearToColor(double r, double g, double b, double a) =>
      throw UnimplementedError();

  Future<ui.Image> snapshot({bool transferOwnership = false}) =>
      throw UnimplementedError();

  void dispose() {}
}
