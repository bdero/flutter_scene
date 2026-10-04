part of '_gpu.dart';

// The web shim's API as backend-neutral interfaces, and the switch that picks
// which backend implements them. The members are exactly what flutter_scene
// calls (the stub's surface), so a backend is complete when these are.

/// Builds against the WebGPU backend instead of WebGL2.
///
/// Const, so the backend left out is tree-shaken. A conditional import cannot
/// make this choice: the web compilers ignore environment tests in import
/// conditions.
// TODO(webgpu-runtime-selection): add the `auto` probe that picks WebGPU at
// startup when the device supports it, falling back to WebGL2.
const bool useWebGpuBackend = bool.fromEnvironment('flutter_scene.webgpu');

/// Everything a web backend provides beyond its resource classes.
abstract base class WebBackend {
  /// Readies the backend; WebGPU acquires its device here. Must complete
  /// before [context] is read.
  Future<void> initialize();

  GpuContext get context;
  GpuHost get host;

  Texture textureFromImage(GpuContext gpuContext, ui.Image image);

  Future<ShaderLibrary?> loadShaderLibraryAsync(String assetName);
  Future<ShaderLibrary?> loadShaderLibraryFromBytesAsync(ByteData bytes);
  Future<void> reinitializeShaderLibraryAsync(String assetKey);
  Future<String?> reinitializeShaderLibraryFromBytesAsync(
    ShaderLibrary library,
    ByteData bytes,
  );
  ShaderLibrary compileShaderLibraryInline(
    Map<String, ({String source, ShaderStage stage})> shaders,
  );

  Future<Texture?> createTextureFromEncodedImage(
    Uint8List encoded, {
    MipContent content = MipContent.color,
    bool mipmaps = true,
    int? maxMipLevels,
    int? maxSize,
  });

  Future<ui.Image> presentTextureAsImage(
    Texture texture, {
    bool transferOwnership = false,
  });
  PixelFormat get reversedDepthStencilFormat;
  ({DeviceBuffer vertex, DeviceBuffer index, int indexBaseOffset})
  createGeometryBuffers(int vertexBytes, int indexBytes);
  bool writeGeometryData(
    DeviceBuffer buffer,
    TypedData source, {
    required int destinationOffsetInBytes,
  });

  Surface createSurface({required int width, required int height});
}

final WebBackend _backend = useWebGpuBackend
    ? createWebGpuBackend()
    : createWebGlBackend();

/// Readies the selected backend. `Scene.initializeStaticResources` awaits it
/// before anything touches [gpuContext].
Future<void> initializeGpuBackend() => _backend.initialize();

/// The active backend's context.
GpuContext get gpuContext => _backend.context;

/// The active backend's host integration.
GpuHost get gpuHost => _backend.host;

abstract base class GpuContext {
  PixelFormat get defaultColorFormat;
  PixelFormat get defaultStencilFormat;
  PixelFormat get defaultDepthStencilFormat;
  int get minimumUniformByteAlignment;
  bool get doesSupportOffscreenMSAA;
  bool get doesSupportFramebufferRenderMipmap;
  bool get doesSupportManuallyMippedTextures;
  DeviceBuffer createDeviceBuffer(StorageMode storageMode, int sizeInBytes);
  DeviceBuffer createDeviceBufferWithCopy(ByteData data);
  HostBuffer createHostBuffer({
    int blockLengthInBytes = HostBuffer.kDefaultBlockLengthInBytes,
  });
  Texture createTexture(
    StorageMode storageMode,
    int width,
    int height, {
    PixelFormat format = PixelFormat.r8g8b8a8UNormInt,
    int sampleCount = 1,
    TextureType? textureType,
    bool enableRenderTargetUsage = true,
    bool enableShaderReadUsage = true,
    bool enableShaderWriteUsage = false,
    int mipLevelCount = 1,
  });
  bool supportsTextureCompression(TextureCompressionFamily family);
  CommandBuffer createCommandBuffer();
  RenderPipeline createRenderPipeline(
    Shader vertexShader,
    Shader fragmentShader, {
    VertexLayout? vertexLayout,
  });
}

abstract base class DeviceBuffer {
  StorageMode get storageMode;
  int get sizeInBytes;
  bool get isValid;
  bool overwrite(ByteData sourceBytes, {int destinationOffsetInBytes = 0});
  void flush({int offsetInBytes = 0, int lengthInBytes = -1});
}

abstract base class HostBuffer {
  static const int kDefaultBlockLengthInBytes = 1024000;
  int get blockLengthInBytes;
  int get frameCount;
  BufferView emplace(ByteData bytes);
  void reset();
}

abstract base class Texture {
  Texture();

  factory Texture.fromImage(GpuContext gpuContext, ui.Image image) =>
      _backend.textureFromImage(gpuContext, image);

  /// The mip count the engine requests for a full chain.
  static int fullMipCount(int width, int height) {
    if (width < 1 || height < 1) return 1;
    final smallest = width < height ? width : height;
    final count = smallest.bitLength - 1;
    return count > 0 ? count : 1;
  }

  StorageMode get storageMode;
  PixelFormat get format;
  int get width;
  int get height;
  int get sampleCount;
  TextureType get textureType;
  bool get enableRenderTargetUsage;
  bool get enableShaderReadUsage;
  bool get enableShaderWriteUsage;
  int get mipLevelCount;
  bool get isValid;
  int get sliceCount;
  int get bytesPerTexel;
  int getMipLevelSizeInBytes(int mipLevel);
  int getBaseMipLevelSizeInBytes();
  void overwrite(ByteData sourceBytes, {int mipLevel = 0, int slice = 0});
  ui.Image asImage();
}

abstract base class UniformSlot {
  Shader get shader;
  String get uniformName;
  int? get sizeInBytes;
  int? getMemberOffsetInBytes(String memberName);
}

abstract base class Shader {
  ShaderStage get stage;
  UniformSlot getUniformSlot(String uniformName);
}

abstract base class RenderPipeline {
  Shader get vertexShader;
  Shader get fragmentShader;
}

abstract base class CommandBuffer {
  RenderPass createRenderPass(RenderTarget renderTarget);
  void submit({CompletionCallback? completionCallback});
}

abstract base class RenderPass {
  void bindPipeline(RenderPipeline pipeline);
  void bindVertexBuffer(BufferView bufferView, {int slot = 0});
  void bindIndexBuffer(BufferView bufferView, IndexType indexType);
  void bindUniform(UniformSlot slot, BufferView bufferView);
  void bindTexture(
    UniformSlot slot,
    Texture texture, {
    SamplerOptions? sampler,
  });
  void clearBindings();
  void setColorBlendEnable(bool enable, {int colorAttachmentIndex = 0});
  void setColorBlendEquation(
    ColorBlendEquation equation, {
    int colorAttachmentIndex = 0,
  });
  void setDepthWriteEnable(bool enable);
  void setDepthCompareOperation(CompareFunction compareFunction);
  void setStencilReference(int referenceValue);
  void setStencilConfig(
    StencilConfig configuration, {
    StencilFace targetFace = StencilFace.both,
  });
  void setCullMode(CullMode cullMode);
  void setPolygonMode(PolygonMode polygonMode);
  void setPrimitiveType(PrimitiveType primitiveType);
  void setWindingOrder(WindingOrder windingOrder);
  void setScissor(Scissor scissor);
  void setViewport(Viewport viewport);
  void draw(int vertexCount, {int instanceCount = 1});
  void drawIndexed(int indexCount, {int instanceCount = 1});
}

abstract base class ShaderLibrary {
  /// Synchronous loading is unsupported on web; use [loadShaderLibraryAsync].
  static ShaderLibrary? fromAsset(String assetName) => throw UnimplementedError(
    'ShaderLibrary.fromAsset is synchronous and unsupported on web. '
    'Use loadShaderLibraryAsync(assetName) instead.',
  );

  /// Mirrors flutter_gpu's in-place hot reload. Fires the asynchronous
  /// recompile and returns; await [reinitializeShaderLibraryAsync] when
  /// ordering matters.
  static void reinitialize(String assetKey) {
    unawaited(reinitializeShaderLibraryAsync(assetKey));
  }

  Shader? operator [](String shaderName);
}

/// An offscreen drawing surface whose frames reach Flutter as images.
abstract base class Surface {
  Surface.base();

  factory Surface({required int width, required int height}) =>
      _backend.createSurface(width: width, height: height);

  int get width;
  int get height;
  abstract bool isLost;
  abstract void Function()? onContextLost;
  abstract void Function()? onContextRestored;
  void clearToColor(double r, double g, double b, double a);
  FutureOr<ui.Image> snapshot({bool transferOwnership = false});
  bool forceContextLoss();
  bool forceContextRestore();
  void dispose();
}

/// The active backend's integration with the Flutter host.
abstract base class GpuHost {
  const GpuHost();

  GpuCapabilities get capabilities;

  /// Hands [texture] to Flutter as a `ui.Image`.
  ui.Image textureToImage(Texture texture);

  /// Wraps a Flutter-rendered [image]'s backing texture, or null when this
  /// backend cannot adopt it.
  Texture? imageToTexture(ui.Image image);

  /// Presents [texture] through the backend's own offscreen canvas path.
  Future<ui.Image> present(Texture texture, {bool transferOwnership = false});
}

Future<ShaderLibrary?> loadShaderLibraryAsync(String assetName) =>
    _backend.loadShaderLibraryAsync(assetName);

Future<ShaderLibrary?> loadShaderLibraryFromBytesAsync(ByteData bytes) =>
    _backend.loadShaderLibraryFromBytesAsync(bytes);

Future<void> reinitializeShaderLibraryAsync(String assetKey) =>
    _backend.reinitializeShaderLibraryAsync(assetKey);

Future<String?> reinitializeShaderLibraryFromBytesAsync(
  ShaderLibrary library,
  ByteData bytes,
) => _backend.reinitializeShaderLibraryFromBytesAsync(library, bytes);

ShaderLibrary compileShaderLibraryInline(
  Map<String, ({String source, ShaderStage stage})> shaders,
) => _backend.compileShaderLibraryInline(shaders);

Future<Texture?> createTextureFromEncodedImage(
  Uint8List encoded, {
  MipContent content = MipContent.color,
  bool mipmaps = true,
  int? maxMipLevels,
  int? maxSize,
}) => _backend.createTextureFromEncodedImage(
  encoded,
  content: content,
  mipmaps: mipmaps,
  maxMipLevels: maxMipLevels,
  maxSize: maxSize,
);

Future<ui.Image> presentTextureAsImage(
  Texture texture, {
  bool transferOwnership = false,
}) => _backend.presentTextureAsImage(
  texture,
  transferOwnership: transferOwnership,
);

PixelFormat get reversedDepthStencilFormat =>
    _backend.reversedDepthStencilFormat;

({DeviceBuffer vertex, DeviceBuffer index, int indexBaseOffset})
createGeometryBuffers(int vertexBytes, int indexBytes) =>
    _backend.createGeometryBuffers(vertexBytes, indexBytes);

bool writeGeometryData(
  DeviceBuffer buffer,
  TypedData source, {
  required int destinationOffsetInBytes,
}) => _backend.writeGeometryData(
  buffer,
  source,
  destinationOffsetInBytes: destinationOffsetInBytes,
);
