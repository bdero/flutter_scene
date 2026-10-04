/// The WebGPU implementation of the web GPU shim, selected with
/// `--dart-define=flutter_scene.webgpu=true`.
///
/// Device acquisition works; resources, pipelines, and passes do not yet.
// TODO(webgpu-backend): implement the context, resources, shader libraries
// from WGSL sidecars, pipelines, passes, and present, in that order (see
// notes/web-backend/webgpu_web_backend_handoff.md in the development root).
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

import '../shared/encoded_image_types.dart';
import '../web/_gpu.dart';
import 'webgpu_device.dart';

/// The WebGPU backend.
WebBackend createWebGpuBackend() => _WebGpuBackend();

Never _unimplemented(String what) => throw UnimplementedError(
  'The WebGPU backend does not implement $what yet. Build without '
  '--dart-define=flutter_scene.webgpu=true to use WebGL2.',
);

final class _WebGpuBackend extends WebBackend {
  WebGpuDevice? _device;

  /// The acquired device, for the backend's own classes.
  WebGpuDevice get device =>
      _device ??
      (throw StateError(
        'The WebGPU backend was used before initializeGpuBackend completed.',
      ));

  @override
  Future<void> initialize() async {
    if (_device != null) return;
    // Forced, so a software adapter is accepted rather than silently
    // rendering nothing; the auto mode that prefers WebGL2 there is
    // TODO(webgpu-runtime-selection).
    final probe = await WebGpuDevice.request(allowFallbackAdapter: true);
    _device =
        probe.device ??
        (throw StateError(
          '$probe. Build without --dart-define=flutter_scene.webgpu=true to '
          'use WebGL2.',
        ));
  }

  @override
  GpuContext get context => _unimplemented('GpuContext');

  @override
  GpuHost get host => _unimplemented('GpuHost');

  @override
  Texture textureFromImage(GpuContext gpuContext, ui.Image image) =>
      _unimplemented('Texture.fromImage');

  @override
  Future<ShaderLibrary?> loadShaderLibraryAsync(String assetName) =>
      _unimplemented('loadShaderLibraryAsync');

  @override
  Future<ShaderLibrary?> loadShaderLibraryFromBytesAsync(ByteData bytes) =>
      _unimplemented('loadShaderLibraryFromBytesAsync');

  @override
  Future<void> reinitializeShaderLibraryAsync(String assetKey) =>
      _unimplemented('reinitializeShaderLibraryAsync');

  @override
  Future<String?> reinitializeShaderLibraryFromBytesAsync(
    ShaderLibrary library,
    ByteData bytes,
  ) => _unimplemented('reinitializeShaderLibraryFromBytesAsync');

  @override
  ShaderLibrary compileShaderLibraryInline(
    Map<String, ({String source, ShaderStage stage})> shaders,
  ) => _unimplemented('compileShaderLibraryInline');

  @override
  Future<Texture?> createTextureFromEncodedImage(
    Uint8List encoded, {
    MipContent content = MipContent.color,
    bool mipmaps = true,
    int? maxMipLevels,
    int? maxSize,
  }) => _unimplemented('createTextureFromEncodedImage');

  @override
  Future<ui.Image> presentTextureAsImage(
    Texture texture, {
    bool transferOwnership = false,
  }) => _unimplemented('presentTextureAsImage');

  @override
  PixelFormat get reversedDepthStencilFormat =>
      _unimplemented('reversedDepthStencilFormat');

  @override
  ({DeviceBuffer vertex, DeviceBuffer index, int indexBaseOffset})
  createGeometryBuffers(int vertexBytes, int indexBytes) =>
      _unimplemented('createGeometryBuffers');

  @override
  bool writeGeometryData(
    DeviceBuffer buffer,
    TypedData source, {
    required int destinationOffsetInBytes,
  }) => _unimplemented('writeGeometryData');

  @override
  Surface createSurface({required int width, required int height}) =>
      _unimplemented('Surface');
}
