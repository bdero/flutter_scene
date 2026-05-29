part of '_gpu.dart';

// Throwing stub declarations for the rest of the flutter_gpu API surface.
// Used when the analyzer can't resolve `dart.library.io` (impeller path)
// or `dart.library.js_interop` (web path) - e.g. when analyzing in a
// platform-neutral context.

Never _stub() => throw UnimplementedError(
  'flutter_gpu_shim is not implemented for this platform.',
);

base class GpuContext {
  GpuContext._() {
    _stub();
  }
  PixelFormat get defaultColorFormat => _stub();
  PixelFormat get defaultStencilFormat => _stub();
  PixelFormat get defaultDepthStencilFormat => _stub();
  int get minimumUniformByteAlignment => _stub();
  bool get doesSupportOffscreenMSAA => _stub();
  DeviceBuffer createDeviceBuffer(StorageMode storageMode, int sizeInBytes) =>
      _stub();
  DeviceBuffer createDeviceBufferWithCopy(ByteData data) => _stub();
  HostBuffer createHostBuffer({
    int blockLengthInBytes = HostBuffer.kDefaultBlockLengthInBytes,
  }) => _stub();
  Texture createTexture(
    StorageMode storageMode,
    int width,
    int height, {
    PixelFormat format = PixelFormat.r8g8b8a8UNormInt,
    int sampleCount = 1,
    TextureCoordinateSystem coordinateSystem =
        TextureCoordinateSystem.renderToTexture,
    TextureType? textureType,
    bool enableRenderTargetUsage = true,
    bool enableShaderReadUsage = true,
    bool enableShaderWriteUsage = false,
    int mipLevelCount = 1,
  }) => _stub();
  CommandBuffer createCommandBuffer() => _stub();
  RenderPipeline createRenderPipeline(
    Shader vertexShader,
    Shader fragmentShader, {
    VertexLayout? vertexLayout,
  }) => _stub();
}

final GpuContext gpuContext = throw UnimplementedError(
  'flutter_gpu_shim is not implemented for this platform.',
);

class BufferView {
  const BufferView(
    this.buffer, {
    required this.offsetInBytes,
    required this.lengthInBytes,
  });
  final DeviceBuffer buffer;
  final int offsetInBytes;
  final int lengthInBytes;
}

base class DeviceBuffer {
  DeviceBuffer._() {
    _stub();
  }
  StorageMode get storageMode => _stub();
  int get sizeInBytes => _stub();
  bool get isValid => _stub();
  bool overwrite(ByteData sourceBytes, {int destinationOffsetInBytes = 0}) =>
      _stub();
  void flush({int offsetInBytes = 0, int lengthInBytes = -1}) => _stub();
}

base class HostBuffer {
  HostBuffer._() {
    _stub();
  }
  static const int kDefaultBlockLengthInBytes = 1024000;
  int get blockLengthInBytes => _stub();
  int get frameCount => _stub();
  BufferView emplace(ByteData bytes) => _stub();
  void reset() => _stub();
}

base class Texture {
  Texture._() {
    _stub();
  }
  StorageMode get storageMode => _stub();
  PixelFormat get format => _stub();
  int get width => _stub();
  int get height => _stub();
  int get sampleCount => _stub();
  TextureType get textureType => _stub();
  bool get enableRenderTargetUsage => _stub();
  bool get enableShaderReadUsage => _stub();
  bool get enableShaderWriteUsage => _stub();
  int get mipLevelCount => _stub();
  TextureCoordinateSystem get coordinateSystem => _stub();
  set coordinateSystem(TextureCoordinateSystem value) => _stub();
  bool get isValid => _stub();
  int get sliceCount => _stub();
  int get bytesPerTexel => _stub();
  static int fullMipCount(int width, int height) => _stub();
  int getMipLevelSizeInBytes(int mipLevel) => _stub();
  int getBaseMipLevelSizeInBytes() => _stub();
  void overwrite(ByteData sourceBytes, {int mipLevel = 0, int slice = 0}) =>
      _stub();
  ui.Image asImage() => _stub();
}

base class UniformSlot {
  UniformSlot._() {
    _stub();
  }
  Shader get shader => _stub();
  String get uniformName => _stub();
  int? get sizeInBytes => _stub();
  int? getMemberOffsetInBytes(String memberName) => _stub();
}

base class Shader {
  Shader._() {
    _stub();
  }
  ShaderStage get stage => _stub();
  UniformSlot getUniformSlot(String uniformName) => _stub();
}

base class RenderPipeline {
  RenderPipeline._() {
    _stub();
  }
  Shader get vertexShader => _stub();
  Shader get fragmentShader => _stub();
}

class VertexLayout {
  const VertexLayout({this.strideInBytes = 0});
  final int strideInBytes;
}

base class ColorAttachment {
  ColorAttachment({
    this.loadAction = LoadAction.clear,
    this.storeAction = StoreAction.store,
    Object? clearValue,
    required this.texture,
    this.resolveTexture,
  });
  LoadAction loadAction;
  StoreAction storeAction;
  Texture texture;
  Texture? resolveTexture;
}

base class DepthStencilAttachment {
  DepthStencilAttachment({
    this.depthLoadAction = LoadAction.clear,
    this.depthStoreAction = StoreAction.dontCare,
    this.depthClearValue = 0.0,
    this.stencilLoadAction = LoadAction.clear,
    this.stencilStoreAction = StoreAction.dontCare,
    this.stencilClearValue = 0,
    required this.texture,
  });
  LoadAction depthLoadAction;
  StoreAction depthStoreAction;
  double depthClearValue;
  LoadAction stencilLoadAction;
  StoreAction stencilStoreAction;
  int stencilClearValue;
  Texture texture;
}

base class StencilConfig {
  StencilConfig({
    this.compareFunction = CompareFunction.always,
    this.stencilFailureOperation = StencilOperation.keep,
    this.depthFailureOperation = StencilOperation.keep,
    this.depthStencilPassOperation = StencilOperation.keep,
    this.readMask = 0xFFFFFFFF,
    this.writeMask = 0xFFFFFFFF,
  });
  CompareFunction compareFunction;
  StencilOperation stencilFailureOperation;
  StencilOperation depthFailureOperation;
  StencilOperation depthStencilPassOperation;
  int readMask;
  int writeMask;
}

base class ColorBlendEquation {
  ColorBlendEquation({
    this.colorBlendOperation = BlendOperation.add,
    this.sourceColorBlendFactor = BlendFactor.one,
    this.destinationColorBlendFactor = BlendFactor.oneMinusSourceAlpha,
    this.alphaBlendOperation = BlendOperation.add,
    this.sourceAlphaBlendFactor = BlendFactor.one,
    this.destinationAlphaBlendFactor = BlendFactor.oneMinusSourceAlpha,
  });
  BlendOperation colorBlendOperation;
  BlendFactor sourceColorBlendFactor;
  BlendFactor destinationColorBlendFactor;
  BlendOperation alphaBlendOperation;
  BlendFactor sourceAlphaBlendFactor;
  BlendFactor destinationAlphaBlendFactor;
}

base class SamplerOptions {
  SamplerOptions({
    this.minFilter = MinMagFilter.nearest,
    this.magFilter = MinMagFilter.nearest,
    this.mipFilter = MipFilter.nearest,
    this.widthAddressMode = SamplerAddressMode.clampToEdge,
    this.heightAddressMode = SamplerAddressMode.clampToEdge,
  });
  MinMagFilter minFilter;
  MinMagFilter magFilter;
  MipFilter mipFilter;
  SamplerAddressMode widthAddressMode;
  SamplerAddressMode heightAddressMode;
}

base class DepthRange {
  DepthRange({this.zNear = 0.0, this.zFar = 1.0});
  double zNear;
  double zFar;
}

base class Scissor {
  Scissor({this.x = 0, this.y = 0, this.width = 0, this.height = 0});
  int x, y, width, height;
}

base class Viewport {
  Viewport({
    this.x = 0,
    this.y = 0,
    this.width = 0,
    this.height = 0,
    DepthRange? depthRange,
  }) : depthRange = depthRange ?? DepthRange();
  int x, y, width, height;
  DepthRange depthRange;
}

base class RenderTarget {
  const RenderTarget({
    this.colorAttachments = const <ColorAttachment>[],
    this.depthStencilAttachment,
  });

  RenderTarget.singleColor(
    ColorAttachment colorAttachment, {
    this.depthStencilAttachment,
  }) : colorAttachments = const <ColorAttachment>[];

  final List<ColorAttachment> colorAttachments;
  final DepthStencilAttachment? depthStencilAttachment;
}

base class CommandBuffer {
  CommandBuffer._() {
    _stub();
  }
  RenderPass createRenderPass(RenderTarget renderTarget) => _stub();
  void submit({CompletionCallback? completionCallback}) => _stub();
}

base class RenderPass {
  RenderPass._() {
    _stub();
  }
  void bindPipeline(RenderPipeline pipeline) => _stub();
  void bindVertexBuffer(BufferView bufferView, {int slot = 0}) => _stub();
  void bindIndexBuffer(BufferView bufferView, IndexType indexType) => _stub();
  void bindUniform(UniformSlot slot, BufferView bufferView) => _stub();
  void bindTexture(
    UniformSlot slot,
    Texture texture, {
    SamplerOptions? sampler,
  }) => _stub();
  void clearBindings() => _stub();
  void setColorBlendEnable(bool enable, {int colorAttachmentIndex = 0}) =>
      _stub();
  void setColorBlendEquation(
    ColorBlendEquation equation, {
    int colorAttachmentIndex = 0,
  }) => _stub();
  void setDepthWriteEnable(bool enable) => _stub();
  void setDepthCompareOperation(CompareFunction compareFunction) => _stub();
  void setStencilReference(int referenceValue) => _stub();
  void setStencilConfig(
    StencilConfig configuration, {
    StencilFace targetFace = StencilFace.both,
  }) => _stub();
  void setCullMode(CullMode cullMode) => _stub();
  void setPolygonMode(PolygonMode polygonMode) => _stub();
  void setPrimitiveType(PrimitiveType primitiveType) => _stub();
  void setWindingOrder(WindingOrder windingOrder) => _stub();
  void setViewport(Viewport viewport) => _stub();
  void draw(int vertexCount) => _stub();
  void drawIndexed(int indexCount) => _stub();
}
