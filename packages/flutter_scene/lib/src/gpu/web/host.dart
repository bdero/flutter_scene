part of '_gpu.dart';

/// The WebGL2 backend's integration with the Flutter host.
///
/// Rendered output reaches Flutter through `OffscreenCanvas`, but the framework
/// rasterizes with its own WebGL context and browsers do not share textures
/// across contexts, so nothing crosses back the other way.
class GpuHost {
  const GpuHost._();

  /// See [GpuCapabilities].
  GpuCapabilities get capabilities => const GpuCapabilities(
    textureToImage: true,
    // Browsers do not share textures across WebGL contexts.
    imageToTexture: false,
    presentAsImage: true,
    // WebGL2 has no compute shaders and never will.
    compute: false,
  );

  /// Hands [texture] to Flutter as a `ui.Image`.
  ui.Image textureToImage(Texture texture) => texture.asImage();

  /// Always null here. See [capabilities].
  Texture? imageToTexture(ui.Image image) => null;

  /// Presents [texture] through the backend's own offscreen canvas path.
  Future<ui.Image> present(Texture texture, {bool transferOwnership = false}) =>
      presentTextureAsImage(texture, transferOwnership: transferOwnership);
}

/// The active backend's host integration.
const GpuHost gpuHost = GpuHost._();
