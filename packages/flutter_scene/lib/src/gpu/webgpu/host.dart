part of 'webgpu_backend.dart';

/// The WebGPU backend's integration with the Flutter host.
///
/// Like WebGL2, rendered output reaches Flutter through an `OffscreenCanvas`,
/// and nothing crosses back, since the framework rasterizes on its own
/// context and browsers share no textures across contexts.
final class _WebGpuHost extends GpuHost {
  const _WebGpuHost(this._backend);

  final _WebGpuBackend _backend;

  @override
  GpuCapabilities get capabilities => const GpuCapabilities(
    textureToImage: true,
    imageToTexture: false,
    presentAsImage: true,
    // TODO(webgpu-compute): WebGPU has compute; report it once the shim has
    // a compute API.
    compute: false,
  );

  @override
  ui.Image textureToImage(Texture texture) => texture.asImage();

  @override
  Texture? imageToTexture(ui.Image image) => null;

  @override
  Future<ui.Image> present(Texture texture, {bool transferOwnership = false}) =>
      _backend.presentTextureAsImage(
        texture,
        transferOwnership: transferOwnership,
      );
}

/// Hands [texture] to Flutter as a `ui.Image`, synchronously, through the
/// context's presenter canvas.
ui.Image _textureToImageSync(_WebGpuTexture texture) {
  if (!texture.enableShaderReadUsage) {
    throw Exception('Only shader-readable textures can be used as UI images');
  }
  if (texture.sampleCount != 1) {
    throw UnimplementedError(
      'Cannot present an MSAA texture directly; use its resolve texture.',
    );
  }
  if (texture._format.depthOrStencil) {
    throw UnsupportedError('A depth or stencil texture cannot be an image.');
  }
  return texture._context.presenter.blitToImageSync(
    texture.attachmentView(0, 0),
    texture.width,
    texture.height,
    srgb: texture._format.name.endsWith('-srgb'),
  );
}

/// An offscreen WebGPU canvas whose frames reach Flutter as images. Exists
/// for the shim smoke app's handoff checks.
final class _WebGpuSurface extends Surface {
  _WebGpuSurface(this._presenter, this.width, this.height) : super.base();

  final WebGpuPresenter _presenter;
  (double, double, double, double) _clear = (0, 0, 0, 0);

  @override
  final int width;

  @override
  final int height;

  @override
  bool isLost = false;

  @override
  void Function()? onContextLost;

  @override
  void Function()? onContextRestored;

  @override
  void clearToColor(double r, double g, double b, double a) =>
      _clear = (r, g, b, a);

  @override
  FutureOr<ui.Image> snapshot({bool transferOwnership = false}) =>
      _presenter.clearToImageSync(
        width,
        height,
        r: _clear.$1,
        g: _clear.$2,
        b: _clear.$3,
        a: _clear.$4,
      );

  // TODO(webgpu-device-loss): drive these from GPUDevice.lost, and recreate
  // the device and its resources on restore.
  @override
  bool forceContextLoss() => false;

  @override
  bool forceContextRestore() => false;

  @override
  void dispose() => _presenter.dispose();
}
