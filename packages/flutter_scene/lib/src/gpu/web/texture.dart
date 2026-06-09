part of '_gpu.dart';

class _GlFormat {
  const _GlFormat(
    this.internalFormat,
    this.format,
    this.type,
    this.bytesPerTexel,
  );
  final int internalFormat;
  final int format;
  final int type;
  final int bytesPerTexel;
}

const Map<PixelFormat, _GlFormat> _formatTable = <PixelFormat, _GlFormat>{
  PixelFormat.r8g8b8a8UNormInt: _GlFormat(
    web.WebGL2RenderingContext.RGBA8,
    web.WebGL2RenderingContext.RGBA,
    web.WebGL2RenderingContext.UNSIGNED_BYTE,
    4,
  ),
  PixelFormat.r8g8b8a8UNormIntSRGB: _GlFormat(
    web.WebGL2RenderingContext.SRGB8_ALPHA8,
    web.WebGL2RenderingContext.RGBA,
    web.WebGL2RenderingContext.UNSIGNED_BYTE,
    4,
  ),
  PixelFormat.r16g16b16a16Float: _GlFormat(
    web.WebGL2RenderingContext.RGBA16F,
    web.WebGL2RenderingContext.RGBA,
    web.WebGL2RenderingContext.HALF_FLOAT,
    8,
  ),
  PixelFormat.r32g32b32a32Float: _GlFormat(
    web.WebGL2RenderingContext.RGBA32F,
    web.WebGL2RenderingContext.RGBA,
    web.WebGL2RenderingContext.FLOAT,
    16,
  ),
  PixelFormat.r8UNormInt: _GlFormat(
    web.WebGL2RenderingContext.R8,
    web.WebGL2RenderingContext.RED,
    web.WebGL2RenderingContext.UNSIGNED_BYTE,
    1,
  ),
  PixelFormat.r8g8UNormInt: _GlFormat(
    web.WebGL2RenderingContext.RG8,
    web.WebGL2RenderingContext.RG,
    web.WebGL2RenderingContext.UNSIGNED_BYTE,
    2,
  ),
  PixelFormat.d24UnormS8Uint: _GlFormat(
    web.WebGL2RenderingContext.DEPTH24_STENCIL8,
    web.WebGL2RenderingContext.DEPTH_STENCIL,
    web.WebGL2RenderingContext.UNSIGNED_INT_24_8,
    4,
  ),
  // Block-compressed formats. The internal format is an extension constant
  // (the matching extension must be enabled, see supportsTextureCompression);
  // format/type/bytesPerTexel are unused (size comes from _compressedBlockBytes).
  PixelFormat.bc1RGBAUNormInt: _GlFormat(0x83F1, 0, 0, 0), // S3TC DXT1
  PixelFormat.etc2RGB8UNormInt: _GlFormat(0x9274, 0, 0, 0), // ETC2 RGB8
  PixelFormat.astc4x4LDR: _GlFormat(0x93B0, 0, 0, 0), // ASTC 4x4
};

/// Bytes per 4x4 block for the compressed formats the upload path supports.
const Map<PixelFormat, int> _compressedBlockBytes = <PixelFormat, int>{
  PixelFormat.bc1RGBAUNormInt: 8,
  PixelFormat.etc2RGB8UNormInt: 8,
  PixelFormat.astc4x4LDR: 16,
};

bool _isCompressedFormat(PixelFormat format) =>
    _compressedBlockBytes.containsKey(format);

bool _isDepthOrStencilFormat(PixelFormat format) {
  switch (format) {
    case PixelFormat.s8UInt:
    case PixelFormat.d24UnormS8Uint:
    case PixelFormat.d32FloatS8UInt:
      return true;
    default:
      return false;
  }
}

base class Texture {
  Texture._initialize(
    this._gpuContext,
    this.storageMode,
    this.format,
    this.width,
    this.height,
    this.sampleCount,
    TextureCoordinateSystem coordinateSystem,
    this.textureType,
    this.enableRenderTargetUsage,
    this.enableShaderReadUsage,
    this.enableShaderWriteUsage,
    this.mipLevelCount,
  ) : _coordinateSystem = coordinateSystem {
    if (sampleCount != 1 && sampleCount != 4) {
      throw Exception('Only a sample count of 1 or 4 is currently supported');
    }
    final entry = _formatTable[format];
    if (entry == null) {
      throw Exception('Unsupported PixelFormat: $format');
    }
    _glFormat = entry;

    final gl = _gpuContext._gl;
    if (sampleCount == 1) {
      _texture = gl.createTexture();
      if (_texture == null) {
        throw StateError('Failed to create WebGL texture');
      }
      gl.bindTexture(web.WebGL2RenderingContext.TEXTURE_2D, _texture);
      gl.texStorage2D(
        web.WebGL2RenderingContext.TEXTURE_2D,
        mipLevelCount,
        entry.internalFormat,
        width,
        height,
      );
      // Sensible default sampler state for sampling. Pipelines override
      // these per `bindTexture` later via sampler objects.
      gl.texParameteri(
        web.WebGL2RenderingContext.TEXTURE_2D,
        web.WebGL2RenderingContext.TEXTURE_MIN_FILTER,
        mipLevelCount > 1
            ? web.WebGL2RenderingContext.LINEAR_MIPMAP_LINEAR
            : web.WebGL2RenderingContext.LINEAR,
      );
      gl.texParameteri(
        web.WebGL2RenderingContext.TEXTURE_2D,
        web.WebGL2RenderingContext.TEXTURE_MAG_FILTER,
        web.WebGL2RenderingContext.LINEAR,
      );
      gl.texParameteri(
        web.WebGL2RenderingContext.TEXTURE_2D,
        web.WebGL2RenderingContext.TEXTURE_WRAP_S,
        web.WebGL2RenderingContext.CLAMP_TO_EDGE,
      );
      gl.texParameteri(
        web.WebGL2RenderingContext.TEXTURE_2D,
        web.WebGL2RenderingContext.TEXTURE_WRAP_T,
        web.WebGL2RenderingContext.CLAMP_TO_EDGE,
      );
    } else {
      // MSAA. We use a renderbuffer for color storage; bindable as an FBO
      // attachment but not directly sampleable. Resolve to a sibling
      // single-sample texture for shader reads at end of pass.
      _renderbuffer = gl.createRenderbuffer();
      if (_renderbuffer == null) {
        throw StateError('Failed to create WebGL renderbuffer');
      }
      gl.bindRenderbuffer(
        web.WebGL2RenderingContext.RENDERBUFFER,
        _renderbuffer,
      );
      gl.renderbufferStorageMultisample(
        web.WebGL2RenderingContext.RENDERBUFFER,
        sampleCount,
        entry.internalFormat,
        width,
        height,
      );
    }
    _valid = true;
  }

  final GpuContext _gpuContext;
  final StorageMode storageMode;
  final PixelFormat format;
  final int width;
  final int height;
  final int sampleCount;
  final TextureType textureType;
  final bool enableRenderTargetUsage;
  final bool enableShaderReadUsage;
  final bool enableShaderWriteUsage;
  final int mipLevelCount;

  late final _GlFormat _glFormat;
  web.WebGLTexture? _texture;
  web.WebGLRenderbuffer? _renderbuffer;
  bool _valid = false;

  // Matches flutter_gpu's mutable getter/setter pair.
  // ignore: unnecessary_getters_setters
  TextureCoordinateSystem _coordinateSystem;
  // ignore: unnecessary_getters_setters
  TextureCoordinateSystem get coordinateSystem => _coordinateSystem;
  // ignore: unnecessary_getters_setters
  set coordinateSystem(TextureCoordinateSystem value) {
    _coordinateSystem = value;
  }

  bool get isValid => _valid;
  bool get isDepthOrStencil => _isDepthOrStencilFormat(format);

  /// Internal: GL texture object (single-sample) or null for MSAA.
  web.WebGLTexture? get glTexture => _texture;

  /// Internal: GL renderbuffer (MSAA) or null for single-sample.
  web.WebGLRenderbuffer? get glRenderbuffer => _renderbuffer;

  int get sliceCount => textureType == TextureType.textureCube ? 6 : 1;

  static int fullMipCount(int width, int height) {
    if (width < 1 || height < 1) return 1;
    final smallest = width < height ? width : height;
    final count = smallest.bitLength - 1;
    return count > 0 ? count : 1;
  }

  int get bytesPerTexel => _glFormat.bytesPerTexel;

  int getMipLevelSizeInBytes(int mipLevel) {
    final mipWidth = (width >> mipLevel).clamp(1, width).toInt();
    final mipHeight = (height >> mipLevel).clamp(1, height).toInt();
    final blockBytes = _compressedBlockBytes[format];
    if (blockBytes != null) {
      final blocksX = (mipWidth + 3) ~/ 4;
      final blocksY = (mipHeight + 3) ~/ 4;
      return blocksX * blocksY * blockBytes;
    }
    return bytesPerTexel * mipWidth * mipHeight;
  }

  int getBaseMipLevelSizeInBytes() => getMipLevelSizeInBytes(0);

  void overwrite(ByteData sourceBytes, {int mipLevel = 0, int slice = 0}) {
    if (sampleCount != 1) {
      throw Exception('Cannot overwrite a multisample texture');
    }
    if (mipLevel < 0 || mipLevel >= mipLevelCount) {
      throw Exception(
        'mipLevel ($mipLevel) must be in the range [0, $mipLevelCount)',
      );
    }
    if (slice != 0) {
      throw UnimplementedError('Cubemap slices not yet supported on web');
    }
    final expectedSize = getMipLevelSizeInBytes(mipLevel);
    if (sourceBytes.lengthInBytes != expectedSize) {
      throw Exception(
        'sourceBytes length (${sourceBytes.lengthInBytes}) must equal expected '
        'size for mip $mipLevel ($expectedSize)',
      );
    }
    final gl = _gpuContext._gl;
    final mipWidth = (width >> mipLevel).clamp(1, width).toInt();
    final mipHeight = (height >> mipLevel).clamp(1, height).toInt();
    gl.bindTexture(web.WebGL2RenderingContext.TEXTURE_2D, _texture);
    if (_isCompressedFormat(format)) {
      final blocks = sourceBytes.buffer
          .asUint8List(sourceBytes.offsetInBytes, sourceBytes.lengthInBytes)
          .toJS;
      gl.compressedTexSubImage2D(
        web.WebGL2RenderingContext.TEXTURE_2D,
        mipLevel,
        0,
        0,
        mipWidth,
        mipHeight,
        _glFormat.internalFormat,
        blocks,
      );
      return;
    }
    // texSubImage2D requires the JS typed-array view to match the GL pixel
    // type: FLOAT wants a Float32Array, HALF_FLOAT a Uint16Array, and the
    // integer formats a Uint8Array. (A Uint8Array for a FLOAT texture throws
    // "type FLOAT but ArrayBufferView not Float32Array".)
    final JSObject view;
    switch (_glFormat.type) {
      case web.WebGL2RenderingContext.FLOAT:
        view = sourceBytes.buffer
            .asFloat32List(
              sourceBytes.offsetInBytes,
              sourceBytes.lengthInBytes ~/ 4,
            )
            .toJS;
      case web.WebGL2RenderingContext.HALF_FLOAT:
        view = sourceBytes.buffer
            .asUint16List(
              sourceBytes.offsetInBytes,
              sourceBytes.lengthInBytes ~/ 2,
            )
            .toJS;
      default:
        view = sourceBytes.buffer
            .asUint8List(sourceBytes.offsetInBytes, sourceBytes.lengthInBytes)
            .toJS;
    }
    gl.texSubImage2D(
      web.WebGL2RenderingContext.TEXTURE_2D,
      mipLevel,
      0,
      0,
      mipWidth.toJS,
      mipHeight.toJS,
      _glFormat.format.toJS,
      _glFormat.type,
      view,
    );
  }

  /// Synchronously snapshot this texture into a `ui.Image` for display via
  /// `Canvas.drawImageRect`. Matches flutter_gpu's synchronous `asImage`,
  /// which is what flutter_scene's `Scene.render(camera, canvas)` paint
  /// path relies on.
  ui.Image asImage() {
    if (!enableShaderReadUsage) {
      throw Exception('Only shader-readable textures can be used as UI images');
    }
    return _gpuContext.snapshotTextureSync(this);
  }
}
