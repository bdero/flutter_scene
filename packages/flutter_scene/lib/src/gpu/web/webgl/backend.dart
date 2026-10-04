part of '_webgl.dart';

/// The WebGL2 backend, the default on web.
WebBackend createWebGlBackend() => _WebGlBackend();

final class _WebGlBackend extends WebBackend {
  @override
  Future<void> initialize() async {}

  @override
  GpuContext get context => webGlContext;

  @override
  GpuHost get host => webGlHost;

  @override
  Texture textureFromImage(GpuContext gpuContext, ui.Image image) =>
      WebGlTexture.fromImage();

  @override
  Future<ShaderLibrary?> loadShaderLibraryAsync(String assetName) =>
      _loadShaderLibraryAsync(assetName);

  @override
  Future<ShaderLibrary?> loadShaderLibraryFromBytesAsync(ByteData bytes) =>
      _loadShaderLibraryFromBytesAsync(bytes);

  @override
  Future<void> reinitializeShaderLibraryAsync(String assetKey) =>
      _reinitializeShaderLibraryAsync(assetKey);

  @override
  Future<String?> reinitializeShaderLibraryFromBytesAsync(
    ShaderLibrary library,
    ByteData bytes,
  ) => _reinitializeShaderLibraryFromBytesAsync(library, bytes);

  @override
  ShaderLibrary compileShaderLibraryInline(
    Map<String, ({String source, ShaderStage stage})> shaders,
  ) => _compileShaderLibraryInline(shaders);

  @override
  Future<Texture?> createTextureFromEncodedImage(
    Uint8List encoded, {
    MipContent content = MipContent.color,
    bool mipmaps = true,
    int? maxMipLevels,
    int? maxSize,
  }) => _createTextureFromEncodedImage(
    encoded,
    content: content,
    mipmaps: mipmaps,
    maxMipLevels: maxMipLevels,
    maxSize: maxSize,
  );

  @override
  Future<ui.Image> presentTextureAsImage(
    Texture texture, {
    bool transferOwnership = false,
  }) => _presentTextureAsImage(texture, transferOwnership: transferOwnership);

  @override
  PixelFormat get reversedDepthStencilFormat => _reversedDepthStencilFormat;

  @override
  ({DeviceBuffer vertex, DeviceBuffer index, int indexBaseOffset})
  createGeometryBuffers(int vertexBytes, int indexBytes) =>
      _createGeometryBuffers(vertexBytes, indexBytes);

  @override
  bool writeGeometryData(
    DeviceBuffer buffer,
    TypedData source, {
    required int destinationOffsetInBytes,
  }) => _writeGeometryData(
    buffer,
    source,
    destinationOffsetInBytes: destinationOffsetInBytes,
  );

  @override
  Surface createSurface({required int width, required int height}) =>
      WebGlSurface(width: width, height: height);
}

// Downcasts for values that cross the facade typed as the neutral interfaces.
// Every one is a WebGL object in a build that selected this backend.

extension _WebGlDeviceBufferCast on DeviceBuffer {
  WebGlDeviceBuffer get webGl => this as WebGlDeviceBuffer;
}

extension _WebGlTextureCast on Texture {
  WebGlTexture get webGl => this as WebGlTexture;
}

extension _WebGlShaderCast on Shader {
  WebGlShader get webGl => this as WebGlShader;
}

extension _WebGlRenderPipelineCast on RenderPipeline {
  WebGlRenderPipeline get webGl => this as WebGlRenderPipeline;
}

extension _WebGlShaderLibraryCast on ShaderLibrary {
  WebGlShaderLibrary get webGl => this as WebGlShaderLibrary;
}
