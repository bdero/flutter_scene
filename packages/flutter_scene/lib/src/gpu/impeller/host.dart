part of '_gpu.dart';

/// Flutter GPU's integration with the Flutter host.
///
/// Flutter GPU is a handle on Impeller's own context rather than an external
/// renderer, so textures cross in both directions without a copy.
class GpuHost {
  const GpuHost._();

  /// See [GpuCapabilities].
  GpuCapabilities get capabilities => const GpuCapabilities(
    textureToImage: true,
    imageToTexture: true,
    // Native uses Texture.asImage directly; the present path is a web concept.
    presentAsImage: false,
    // Impeller has a compute HAL, but flutter_gpu exposes no Dart surface for
    // it yet. Tracked upstream as flutter/flutter#188474.
    compute: false,
    // Flutter GPU allocates every texture itself; wrapping a swapchain image
    // a runtime owns is proposed as flutter/flutter#192059.
    externalColorTargets: false,
  );

  /// The platform graphics context behind this backend, for a runtime that
  /// must bind it (a WebXR layer takes the WebGL context). Flutter GPU keeps
  /// Impeller's device private, so there is none here.
  Object? get nativeGraphicsContext => null;

  /// Not available on this backend; Impeller has no platform image object to
  /// hand to another context.
  Object? textureToPlatformImage(Texture texture) => null;

  /// Not supported on this backend; see [GpuCapabilities.externalColorTargets].
  Texture wrapExternalColorTarget(
    Object handle, {
    required int width,
    required int height,
    required ExternalTargetHandleKind kind,
    PixelFormat format = PixelFormat.r8g8b8a8UNormInt,
  }) {
    throw UnsupportedError(
      'Flutter GPU cannot render into a texture it did not allocate yet '
      '(flutter/flutter#192059). Render into a flutter_scene texture and copy '
      'it, or check GpuCapabilities.externalColorTargets first.',
    );
  }

  /// Hands [texture] to Flutter as a `ui.Image`, without a copy.
  ui.Image textureToImage(Texture texture) => texture.asImage();

  /// Wraps a Flutter-rendered [image]'s backing texture, or returns null when
  /// it is not backed by one this backend can adopt.
  ///
  /// Null rather than throwing, because "this image cannot be wrapped" is a
  /// routine answer callers are expected to handle by reading back instead.
  /// Resolving the context is part of that, since asking for one where Impeller
  /// is disabled throws.
  Texture? imageToTexture(ui.Image image) {
    try {
      return Texture.fromImage(gpuContext, image);
    } on Exception {
      // Deferred images from toImageSync have not rasterized yet, software
      // rendering produces no GPU texture at all, and a context is unavailable
      // entirely when Impeller is off.
      return null;
    }
  }

  /// Not supported here; native callers use [textureToImage].
  Future<ui.Image> present(Texture texture, {bool transferOwnership = false}) {
    throw UnimplementedError(
      'present is only implemented on web. On native, use '
      'gpuHost.textureToImage().',
    );
  }
}

/// Readies the GPU backend. Flutter GPU needs nothing beyond the engine.
Future<void> initializeGpuBackend() async {}

/// The active backend's host integration.
const GpuHost gpuHost = GpuHost._();
