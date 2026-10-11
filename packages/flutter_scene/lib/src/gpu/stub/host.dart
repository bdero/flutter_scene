part of '_gpu.dart';

/// The analyzer fallback's host integration.
///
/// Mirrors the real backends' surface so `flutter analyze` resolves against it
/// on platforms with no implementation. Every method throws.
class GpuHost {
  const GpuHost._();

  /// See [GpuCapabilities].
  GpuCapabilities get capabilities => const GpuCapabilities(
    textureToImage: false,
    imageToTexture: false,
    presentAsImage: false,
    compute: false,
  );

  ui.Image textureToImage(Texture texture) => _stub();

  Texture? imageToTexture(ui.Image image) => null;

  Future<ui.Image> present(Texture texture, {bool transferOwnership = false}) =>
      _stub();

  Object? get nativeGraphicsContext => null;

  Object? textureToPlatformImage(Texture texture) => null;

  Texture wrapExternalColorTarget(
    Object handle, {
    required int width,
    required int height,
    required ExternalTargetHandleKind kind,
    PixelFormat format = PixelFormat.r8g8b8a8UNormInt,
  }) => _stub();
}

/// The active backend's host integration.
const GpuHost gpuHost = GpuHost._();

/// Readies the GPU backend; web acquires its device here.
Future<void> initializeGpuBackend() async {}
