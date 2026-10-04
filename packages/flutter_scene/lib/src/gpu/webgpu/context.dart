part of 'webgpu_backend.dart';

/// The WebGPU [GpuContext], over an acquired [WebGpuDevice].
final class _WebGpuContext extends GpuContext {
  _WebGpuContext(this.device);

  final WebGpuDevice device;

  late final _SamplerCache samplers = _SamplerCache(device);
  late final _MipGenerator mipGenerator = _MipGenerator(device);
  late final WebGpuPresenter presenter = WebGpuPresenter(device);

  /// Whether 32-bit float targets blend, and filter when sampled.
  late final bool float32Blendable = device.hasFeature('float32-blendable');
  late final bool float32Filterable = device.hasFeature('float32-filterable');

  /// Scratch for `setBindGroup`'s dynamic offsets, JS-backed so passing it
  /// costs no copy.
  final JSUint32Array dynamicOffsetsJs = JSUint32Array.withLength(64);
  late final Uint32List dynamicOffsets = dynamicOffsetsJs.toDart;

  _WebGpuDeviceBuffer? _zeroUniforms;

  /// A zeroed buffer of at least [size] bytes, bound to a uniform block the
  /// renderer never binds, which reads zeros as on WebGL2.
  _WebGpuDeviceBuffer zeroUniformBuffer(int size) {
    final current = _zeroUniforms;
    if (current != null && current.sizeInBytes >= size) return current;
    return _zeroUniforms = _WebGpuDeviceBuffer.geometry(
      this,
      size < 4096 ? 4096 : size,
    );
  }

  final Map<String, _WebGpuTexture> _blankTextures = {};

  /// An opaque black texture of [viewDimension], bound to a texture the
  /// renderer never binds; GL samples an unbound unit the same way.
  _WebGpuTexture blankTexture(String viewDimension) =>
      _blankTextures[viewDimension] ??= () {
        final cube = viewDimension == 'cube';
        final texture = createTexture(
          StorageMode.hostVisible,
          1,
          1,
          textureType: cube ? TextureType.textureCube : TextureType.texture2D,
          enableRenderTargetUsage: false,
        );
        for (var slice = 0; slice < texture.sliceCount; slice++) {
          texture.overwrite(ByteData(4)..setUint8(3, 255), slice: slice);
        }
        return texture as _WebGpuTexture;
      }();

  /// Bind group layouts by their canonical entries.
  final Map<String, _BindingLayout> bindingLayouts = {};

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

  /// The bind group layout for [entries], shared by every pipeline whose
  /// entries match, so their bind groups are interchangeable.
  _BindingLayout _bindingLayoutFor(List<Map<String, Object?>> entries) {
    final key = jsonEncode(entries);
    final cached = bindingLayouts[key];
    if (cached != null) return cached;
    final layout = device.device.createBindGroupLayout(
      _obj({'entries': entries}),
    );
    final pipelineLayout = device.device.createPipelineLayout(
      _obj({
        'bindGroupLayouts': [layout],
      }),
    );
    return bindingLayouts[key] = _BindingLayout(key, layout, pipelineLayout, [
      for (final e in entries)
        (
          binding: e['binding']! as int,
          kind: e.containsKey('buffer')
              ? _EntryKind.uniform
              : e.containsKey('texture')
              ? _EntryKind.texture
              : _EntryKind.sampler,
          dynamic: (e['buffer'] as Map?)?['hasDynamicOffset'] == true,
          nonFiltering: (e['sampler'] as Map?)?['type'] == 'non-filtering',
          viewDimension: (e['texture'] as Map?)?['viewDimension'] as String?,
        ),
    ]);
  }

  @override
  CommandBuffer createCommandBuffer() => _WebGpuCommandBuffer(this);

  @override
  RenderPipeline createRenderPipeline(
    Shader vertexShader,
    Shader fragmentShader, {
    VertexLayout? vertexLayout,
  }) => _WebGpuRenderPipeline(
    this,
    vertexShader as _WebGpuShader,
    fragmentShader as _WebGpuShader,
    vertexLayout,
  );
}
