part of '_webgl.dart';

/// The WebGL2 backend's integration with the Flutter host.
///
/// Rendered output reaches Flutter through `OffscreenCanvas`, but the framework
/// rasterizes with its own WebGL context and browsers do not share textures
/// across contexts, so nothing crosses back the other way.
final class WebGlHost extends GpuHost {
  const WebGlHost._();

  /// See [GpuCapabilities].
  @override
  GpuCapabilities get capabilities => const GpuCapabilities(
    textureToImage: true,
    // Browsers do not share textures across WebGL contexts.
    imageToTexture: false,
    presentAsImage: true,
    // WebGL2 has no compute shaders and never will.
    compute: false,
  );

  /// Hands [texture] to Flutter as a `ui.Image`.
  @override
  ui.Image textureToImage(Texture texture) => texture.asImage();

  /// Always null here. See [capabilities].
  @override
  Texture? imageToTexture(ui.Image image) => null;

  /// Presents [texture] through the backend's own offscreen canvas path.
  @override
  Future<ui.Image> present(Texture texture, {bool transferOwnership = false}) =>
      _presentTextureAsImage(texture, transferOwnership: transferOwnership);
}

/// The WebGL2 backend's host integration.
const WebGlHost webGlHost = WebGlHost._();
