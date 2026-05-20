part of '_gpu.dart';

class Surface {
  Surface({required int width, required int height}) {
    throw UnimplementedError(
      'flutter_gpu_shim is not implemented for this platform.',
    );
  }

  int get width => throw UnimplementedError();
  int get height => throw UnimplementedError();

  bool isLost = false;
  void Function()? onContextLost;
  void Function()? onContextRestored;

  void clearToColor(double r, double g, double b, double a) =>
      throw UnimplementedError();

  Future<ui.Image> snapshot({bool transferOwnership = false}) =>
      throw UnimplementedError();

  bool forceContextLoss() => throw UnimplementedError();
  bool forceContextRestore() => throw UnimplementedError();

  void dispose() {}
}
