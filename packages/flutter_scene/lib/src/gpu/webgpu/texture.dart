part of 'webgpu_backend.dart';

/// Destroys a texture's GPU allocation once its Dart wrapper is collected.
final Finalizer<GPUTexture> _textureFinalizer = Finalizer(
  (texture) => texture.destroy(),
);

/// A [Texture] over a `GPUTexture`.
final class _WebGpuTexture extends Texture {
  _WebGpuTexture._(
    this._context,
    this.storageMode,
    this.width,
    this.height, {
    required this.format,
    required this.sampleCount,
    required this.textureType,
    required this.enableRenderTargetUsage,
    required this.enableShaderReadUsage,
    required this.enableShaderWriteUsage,
    required this.mipLevelCount,
    this.layerCount = 1,
    this.depth = 1,
  }) : _format = _gpuFormatFor(format, _context.device) {
    if (layerCount < 1 ||
        (layerCount > 1 && textureType != TextureType.texture2DArray)) {
      throw ArgumentError(
        'layerCount ($layerCount) must be 1 for textures of type $textureType',
      );
    }
    if (depth < 1 || (depth > 1 && textureType != TextureType.texture3D)) {
      throw ArgumentError(
        'depth ($depth) must be 1 for textures of type $textureType',
      );
    }
    if (textureType == TextureType.textureExternalOES) {
      throw UnsupportedError('External OES textures do not exist on WebGPU.');
    }
    if (sampleCount != 1 && sampleCount != 4) {
      throw UnsupportedError(
        'WebGPU supports sample counts 1 and 4, not $sampleCount.',
      );
    }
    final block = _format.blockSize;
    if (width % block != 0 || height % block != 0) {
      // TODO(webgpu-compressed-sizes): pad the base level up to the block
      // size (and crop at sample time) instead of refusing.
      throw UnsupportedError(
        'WebGPU needs a ${_format.name} texture to be a multiple of its '
        '$block-texel block; $width x $height is not.',
      );
    }
    var usage = 0;
    final copyable = sampleCount == 1 && !_format.depth;
    if (copyable) usage |= GPUTextureUsage.copyDst | GPUTextureUsage.copySrc;
    if (enableShaderReadUsage) usage |= GPUTextureUsage.textureBinding;
    if (enableShaderWriteUsage) usage |= GPUTextureUsage.storageBinding;
    if (enableRenderTargetUsage && !_format.compressed) {
      usage |= GPUTextureUsage.renderAttachment;
    }
    texture = _context.device.device.createTexture(
      _obj({
        'size': [width, height, sliceCount],
        'mipLevelCount': mipLevelCount,
        'sampleCount': sampleCount,
        'dimension': textureType == TextureType.texture3D ? '3d' : '2d',
        'format': _format.name,
        'usage': usage,
      }),
    );
    _textureFinalizer.attach(this, texture, detach: this);
  }

  final _WebGpuContext _context;
  final _GpuFormat _format;
  late final GPUTexture texture;

  @override
  final StorageMode storageMode;
  @override
  final PixelFormat format;
  @override
  final int width;
  @override
  final int height;
  @override
  final int sampleCount;
  @override
  final TextureType textureType;
  @override
  final bool enableRenderTargetUsage;
  @override
  final bool enableShaderReadUsage;
  @override
  final bool enableShaderWriteUsage;
  @override
  final int mipLevelCount;
  @override
  final int layerCount;
  @override
  final int depth;

  @override
  bool get isValid => true;

  @override
  int get sliceCount => switch (textureType) {
    TextureType.textureCube => 6,
    TextureType.texture2DArray => layerCount,
    TextureType.texture3D => depth,
    _ => 1,
  };

  @override
  int get bytesPerTexel => _format.compressed ? 0 : _format.bytesPerBlock;

  /// The view a shader samples: the whole chain, cube shaped for a cube map,
  /// and depth only for a depth-stencil target sampled as a float.
  late final GPUTextureView sampledView = texture.createView(
    _obj({
      'dimension': switch (textureType) {
        TextureType.textureCube => 'cube',
        TextureType.texture2DArray => '2d-array',
        TextureType.texture3D => '3d',
        _ => '2d',
      },
      if (_format.depth) 'aspect': 'depth-only',
    }),
  );

  final Map<int, GPUTextureView> _attachmentViews = {};

  /// [levelView], cached, for a pass attachment.
  GPUTextureView attachmentView(int mipLevel, int slice) =>
      _attachmentViews[mipLevel | slice << 8] ??= levelView(
        mipLevel,
        slice: slice,
      );

  /// A single-level, single-slice view, for a render attachment or a mip
  /// generation source.
  ///
  /// A 3D texture has no 2D view of one depth slice, so it cannot be a render
  /// attachment here.
  GPUTextureView levelView(int mipLevel, {int slice = 0}) {
    if (textureType == TextureType.texture3D) {
      throw UnsupportedError(
        'A 3D texture cannot be rendered into on the WebGPU backend.',
      );
    }
    return texture.createView(
      _obj({
        'dimension': '2d',
        'baseMipLevel': mipLevel,
        'mipLevelCount': 1,
        'baseArrayLayer': slice,
        'arrayLayerCount': 1,
      }),
    );
  }

  int _mipExtent(int base, int mipLevel) {
    final size = base >> mipLevel;
    return size < 1 ? 1 : size;
  }

  @override
  int getMipLevelSizeInBytes(int mipLevel) {
    final mipWidth = _mipExtent(width, mipLevel);
    final mipHeight = _mipExtent(height, mipLevel);
    final block = _format.blockSize;
    final blocksX = (mipWidth + block - 1) ~/ block;
    final blocksY = (mipHeight + block - 1) ~/ block;
    return blocksX * blocksY * _format.bytesPerBlock;
  }

  @override
  int getBaseMipLevelSizeInBytes() => getMipLevelSizeInBytes(0);

  @override
  void overwrite(ByteData sourceBytes, {int mipLevel = 0, int slice = 0}) {
    if (sampleCount != 1) {
      throw Exception('Cannot overwrite a multisample texture');
    }
    if (_format.depthOrStencil) {
      throw UnsupportedError('Depth and stencil textures cannot be written.');
    }
    if (mipLevel < 0 || mipLevel >= mipLevelCount) {
      throw Exception(
        'mipLevel ($mipLevel) must be in the range [0, $mipLevelCount)',
      );
    }
    // A 3D texture's depth halves per level like its width and height.
    final slices = textureType == TextureType.texture3D
        ? _mipExtent(depth, mipLevel)
        : sliceCount;
    if (slice < 0 || slice >= slices) {
      throw Exception('slice ($slice) must be in [0, $slices)');
    }
    final expectedSize = getMipLevelSizeInBytes(mipLevel);
    if (sourceBytes.lengthInBytes != expectedSize) {
      throw Exception(
        'sourceBytes length (${sourceBytes.lengthInBytes}) must equal expected '
        'size for mip $mipLevel ($expectedSize)',
      );
    }
    final block = _format.blockSize;
    final blocksX = (_mipExtent(width, mipLevel) + block - 1) ~/ block;
    final blocksY = (_mipExtent(height, mipLevel) + block - 1) ~/ block;
    _context.device.device.queue.writeTexture(
      _obj({
        'texture': texture,
        'mipLevel': mipLevel,
        'origin': [0, 0, slice],
      }),
      _WebGpuDeviceBuffer._jsViewOf(sourceBytes),
      _obj({
        'offset': 0,
        'bytesPerRow': blocksX * _format.bytesPerBlock,
        'rowsPerImage': blocksY,
      }),
      // Compressed copies cover whole blocks, past a small mip's edge.
      _arr([blocksX * block, blocksY * block, 1]),
    );
  }

  @override
  ui.Image asImage() => _textureToImageSync(this);
}
