part of 'webgpu_backend.dart';

/// The WebGPU [GpuContext], over an acquired [WebGpuDevice].
final class _WebGpuContext extends GpuContext {
  _WebGpuContext(this.device);

  final WebGpuDevice device;

  late final _SamplerCache samplers = _SamplerCache(device);
  late final _MipGenerator mipGenerator = _MipGenerator(device);

  @override
  PixelFormat get defaultColorFormat => PixelFormat.r8g8b8a8UNormInt;

  @override
  PixelFormat get defaultStencilFormat => PixelFormat.s8UInt;

  @override
  PixelFormat get defaultDepthStencilFormat => PixelFormat.d24UnormS8Uint;

  /// Float depth where the device has it. WebGPU clip depth is already
  /// `[0, 1]`, so reversed depth keeps its precision with no extension.
  PixelFormat get reversedDepthStencilFormat =>
      device.hasFeature('depth32float-stencil8')
      ? PixelFormat.d32FloatS8UInt
      : PixelFormat.d24UnormS8Uint;

  @override
  int get minimumUniformByteAlignment =>
      device.device.limits.minUniformBufferOffsetAlignment;

  @override
  bool get doesSupportOffscreenMSAA => true;

  @override
  bool get doesSupportFramebufferRenderMipmap => true;

  @override
  bool get doesSupportManuallyMippedTextures => true;

  int get maxTextureSize => device.device.limits.maxTextureDimension2D;

  @override
  DeviceBuffer createDeviceBuffer(StorageMode storageMode, int sizeInBytes) =>
      _WebGpuDeviceBuffer._(
        this,
        storageMode,
        sizeInBytes,
        shadowed: storageMode == StorageMode.hostVisible,
      );

  @override
  DeviceBuffer createDeviceBufferWithCopy(ByteData data) {
    final buffer = createDeviceBuffer(
      StorageMode.hostVisible,
      data.lengthInBytes,
    );
    buffer.overwrite(data);
    return buffer;
  }

  @override
  HostBuffer createHostBuffer({
    int blockLengthInBytes = HostBuffer.kDefaultBlockLengthInBytes,
  }) => BumpHostBuffer(this, blockLengthInBytes: blockLengthInBytes);

  @override
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
  }) => _WebGpuTexture._(
    this,
    storageMode,
    width,
    height,
    format: format,
    sampleCount: sampleCount,
    textureType:
        textureType ??
        (sampleCount == 1
            ? TextureType.texture2D
            : TextureType.texture2DMultisample),
    enableRenderTargetUsage: enableRenderTargetUsage,
    enableShaderReadUsage: enableShaderReadUsage,
    enableShaderWriteUsage: enableShaderWriteUsage,
    mipLevelCount: mipLevelCount,
  );

  @override
  bool supportsTextureCompression(TextureCompressionFamily family) =>
      switch (family) {
        TextureCompressionFamily.bc => device.hasFeature(_bc),
        TextureCompressionFamily.etc2 => device.hasFeature(_etc2),
        TextureCompressionFamily.astc => device.hasFeature(_astc),
        // WebGPU exposes no HDR ASTC profile.
        TextureCompressionFamily.astcHdr => false,
      };

  @override
  CommandBuffer createCommandBuffer() => _unimplemented('CommandBuffer');

  @override
  RenderPipeline createRenderPipeline(
    Shader vertexShader,
    Shader fragmentShader, {
    VertexLayout? vertexLayout,
  }) => _unimplemented('RenderPipeline');
}
