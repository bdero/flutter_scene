part of '_gpu.dart';

/// Global graphics context. Lazily creates a shared `OffscreenCanvas` +
/// `WebGL2RenderingContext` the first time it's accessed; all resources
/// (buffers, textures, pipelines) live in this context.
///
/// Mirrors `package:flutter_gpu`'s `GpuContext`. The shim's web GpuContext
/// is `base class`-shaped for API parity but doesn't extend any
/// platform-specific native wrapper.
base class GpuContext {
  GpuContext._createDefault() {
    _canvas = web.OffscreenCanvas(1, 1);
    // antialias:false makes the default framebuffer single-sampled, so we
    // can blitFramebuffer single-sample render targets onto it for present.
    // preserveDrawingBuffer:true keeps the rendered contents available for
    // createImageFromTextureSource after the GL calls return.
    final attrs = web.WebGLContextAttributes(
      antialias: false,
      alpha: true,
      depth: false,
      stencil: false,
      preserveDrawingBuffer: true,
    );
    final gl =
        _canvas.getContext('webgl2', attrs) as web.WebGL2RenderingContext?;
    if (gl == null) {
      throw StateError(
        'WebGL2 is not available. Cannot initialize flutter_gpu_shim.',
      );
    }
    _gl = gl;
    // Cache extensions we rely on for later phases.
    _gl.getExtension('EXT_color_buffer_float');
    _gl.getExtension('OES_texture_float_linear');
    // Anisotropic filtering. MAX_TEXTURE_MAX_ANISOTROPY_EXT = 0x84FF.
    if (_gl.getExtension('EXT_texture_filter_anisotropic') != null) {
      final Object? max = _gl.getParameter(0x84FF);
      _maxSupportedAnisotropy = max is num ? max.toInt() : 1;
    }
  }

  late final web.OffscreenCanvas _canvas;
  late final web.WebGL2RenderingContext _gl;

  /// Cached vertex-array objects keyed by (pipeline, vertex streams, index
  /// buffer), in least-recently-used order; see RenderPass._applyVertexState.
  static const int _kMaxCachedVaos = 512;
  final Map<String, web.WebGLVertexArrayObject> _vaoCache =
      <String, web.WebGLVertexArrayObject>{};

  int _maxSupportedAnisotropy = 1;

  /// The device's maximum supported anisotropy (1 when the extension is
  /// unavailable, which disables anisotropic filtering).
  int get maxSupportedAnisotropy => _maxSupportedAnisotropy;

  /// The underlying `OffscreenCanvas`. Resized on demand by `snapshot`.
  web.OffscreenCanvas get canvas => _canvas;

  /// The underlying WebGL2 context. Exposed for advanced consumers and the
  /// shim's own internal tests.
  web.WebGL2RenderingContext get gl => _gl;

  PixelFormat get defaultColorFormat => PixelFormat.r8g8b8a8UNormInt;

  PixelFormat get defaultStencilFormat => PixelFormat.s8UInt;

  PixelFormat get defaultDepthStencilFormat => PixelFormat.d24UnormS8Uint;

  int get minimumUniformByteAlignment => 256;

  bool get doesSupportOffscreenMSAA => true;

  // WebGL2 framebufferTexture2D accepts any allocated mip level.
  bool get doesSupportFramebufferRenderMipmap => true;

  // texStorage2D allocates complete mip chains; per-level overwrite plus
  // mipmap min filters sample correctly.
  bool get doesSupportManuallyMippedTextures => true;

  final Map<TextureCompressionFamily, bool> _compressionSupport = {};

  /// Reports block-compression support by probing (and enabling) the matching
  /// WebGL2 compressed-texture extension. Enabling it here makes the compressed
  /// internal formats valid for the `createTexture` / `overwrite` upload path.
  bool supportsTextureCompression(TextureCompressionFamily family) {
    return _compressionSupport.putIfAbsent(family, () {
      final name = switch (family) {
        TextureCompressionFamily.bc => 'WEBGL_compressed_texture_s3tc',
        TextureCompressionFamily.etc2 => 'WEBGL_compressed_texture_etc',
        TextureCompressionFamily.astc => 'WEBGL_compressed_texture_astc',
        // No WebGL extension exposes the ASTC HDR profile.
        TextureCompressionFamily.astcHdr => null,
      };
      return name != null && _gl.getExtension(name) != null;
    });
  }

  DeviceBuffer createDeviceBuffer(StorageMode storageMode, int sizeInBytes) {
    if (storageMode == StorageMode.deviceTransient) {
      throw Exception(
        'DeviceBuffers cannot be set to StorageMode.deviceTransient',
      );
    }
    return DeviceBuffer._initialize(this, storageMode, sizeInBytes);
  }

  DeviceBuffer createDeviceBufferWithCopy(ByteData data) {
    final buffer = DeviceBuffer._initialize(
      this,
      StorageMode.hostVisible,
      data.lengthInBytes,
    );
    buffer.overwrite(data);
    return buffer;
  }

  HostBuffer createHostBuffer({
    int blockLengthInBytes = HostBuffer.kDefaultBlockLengthInBytes,
  }) {
    return HostBuffer._initialize(this, blockLengthInBytes: blockLengthInBytes);
  }

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
  }) {
    final resolvedType =
        textureType ??
        (sampleCount == 1
            ? TextureType.texture2D
            : TextureType.texture2DMultisample);
    return Texture._initialize(
      this,
      storageMode,
      format,
      width,
      height,
      sampleCount,
      resolvedType,
      enableRenderTargetUsage,
      enableShaderReadUsage,
      enableShaderWriteUsage,
      mipLevelCount,
    );
  }

  CommandBuffer createCommandBuffer() => CommandBuffer._(this);

  // Linked-program cache. Program linking is expensive and some callers
  // create a pipeline per draw per frame; native flutter_gpu absorbs that,
  // so the shim must too. Keyed by shader identity plus compile generation,
  // so a hot-reloaded shader relinks while untouched pairs stay cached.
  final Map<(Shader, Shader, int, int), RenderPipeline> _pipelineCache = {};

  RenderPipeline createRenderPipeline(
    Shader vertexShader,
    Shader fragmentShader, {
    VertexLayout? vertexLayout,
  }) {
    if (vertexLayout != null) {
      // Custom layouts are rare (inline smoke pipelines); don't cache.
      return RenderPipeline._(
        this,
        vertexShader,
        fragmentShader,
        vertexLayout: vertexLayout,
      );
    }
    final key = (
      vertexShader,
      fragmentShader,
      vertexShader._generation,
      fragmentShader._generation,
    );
    final cached = _pipelineCache[key];
    if (cached != null) return cached;
    if (_pipelineCache.length >= 512) {
      // Far above any realistic working set; clearing keeps stale
      // hot-reload generations from accumulating without bookkeeping.
      for (final pipeline in _pipelineCache.values) {
        _gl.deleteProgram(pipeline._program);
      }
      _pipelineCache.clear();
    }
    return _pipelineCache[key] = RenderPipeline._(
      this,
      vertexShader,
      fragmentShader,
    );
  }

  // Framebuffer cache, keyed by the attachment textures. A pass previously
  // created (and leaked) a framebuffer and ran the synchronous
  // checkFramebufferStatus round trip every time; render targets recur every
  // frame, so both now happen once per attachment combination.
  final Map<(Texture, int, int, Texture?), web.WebGLFramebuffer>
  _framebufferCache = {};

  web.WebGLFramebuffer _framebufferFor(
    Texture color,
    int mipLevel,
    int slice,
    Texture? depth,
    web.WebGLFramebuffer Function() create,
  ) {
    final key = (color, mipLevel, slice, depth);
    final cached = _framebufferCache[key];
    if (cached != null) return cached;
    if (_framebufferCache.length >= 64) {
      for (final fbo in _framebufferCache.values) {
        _gl.deleteFramebuffer(fbo);
      }
      _framebufferCache.clear();
    }
    return _framebufferCache[key] = create();
  }

  /// Snapshot the underlying `OffscreenCanvas` into a `ui.Image` for display
  /// in a Flutter widget. The canvas is resized if [width] / [height] differ
  /// from its current dimensions. Web-specific addition; not in flutter_gpu.
  Future<ui.Image> snapshot({
    required int width,
    required int height,
    bool transferOwnership = false,
  }) async {
    if (_canvas.width != width) _canvas.width = width;
    if (_canvas.height != height) _canvas.height = height;
    return await ui_web.createImageFromTextureSource(
      _canvas as JSAny,
      width: width,
      height: height,
      transferOwnership: transferOwnership,
    );
  }

  /// Blit a single-sample [texture]'s contents onto the underlying
  /// `OffscreenCanvas`, resizing it to match. Shared by the present paths.
  void _blitTextureToCanvas(Texture texture) {
    if (texture.sampleCount != 1) {
      throw UnimplementedError(
        'Cannot present an MSAA texture directly; use its resolve texture.',
      );
    }
    if (_canvas.width != texture.width) _canvas.width = texture.width;
    if (_canvas.height != texture.height) _canvas.height = texture.height;

    final readFbo = _gl.createFramebuffer();
    if (readFbo == null) {
      throw StateError('Failed to create framebuffer for present blit');
    }
    _gl.bindFramebuffer(web.WebGL2RenderingContext.READ_FRAMEBUFFER, readFbo);
    _gl.framebufferTexture2D(
      web.WebGL2RenderingContext.READ_FRAMEBUFFER,
      web.WebGL2RenderingContext.COLOR_ATTACHMENT0,
      web.WebGL2RenderingContext.TEXTURE_2D,
      texture.glTexture,
      0,
    );
    _gl.bindFramebuffer(web.WebGL2RenderingContext.DRAW_FRAMEBUFFER, null);
    // Flip vertically during the blit (dst Y runs height -> 0). WebGL2
    // rasterizes into FBO textures bottom-up, so the swapchain texture is
    // stored bottom-up; this flip presents it upright on the canvas. (The
    // engine's own backends store render-to-texture top-down, so flutter_scene
    // applies no Y compensation; this present-time flip is the shim absorbing
    // WebGL2's bottom-up FBO convention, equivalent to what Impeller's GLES
    // backend does in-engine.)
    _gl.blitFramebuffer(
      0,
      0,
      texture.width,
      texture.height,
      0,
      texture.height,
      texture.width,
      0,
      web.WebGL2RenderingContext.COLOR_BUFFER_BIT,
      web.WebGL2RenderingContext.NEAREST,
    );
    _gl.bindFramebuffer(web.WebGL2RenderingContext.FRAMEBUFFER, null);
    _gl.deleteFramebuffer(readFbo);
  }

  /// Synchronously snapshot [texture] into a `ui.Image`. Blits to the
  /// OffscreenCanvas, transfers the canvas content out as an ImageBitmap,
  /// and wraps it. `transferToImageBitmap` and `createImageFromImageBitmap`
  /// are both synchronous on CanvasKit and Skwasm, so this works inside a
  /// synchronous paint callback - which is what flutter_scene's
  /// `Texture.asImage()` -> `canvas.drawImageRect` path needs.
  ui.Image snapshotTextureSync(Texture texture) {
    _blitTextureToCanvas(texture);
    final bitmap = _canvas.transferToImageBitmap();
    final result = ui_web.createImageFromImageBitmap(bitmap as JSAny);
    if (result is ui.Image) return result;
    throw StateError(
      'createImageFromImageBitmap returned a Future; expected a synchronous '
      'ui.Image on this renderer.',
    );
  }

  /// Blit [texture] onto the OffscreenCanvas and return it as a `ui.Image`
  /// via `createImageFromTextureSource` (async copy path).
  Future<ui.Image> _presentTextureAsImage(
    Texture texture, {
    bool transferOwnership = false,
  }) async {
    _blitTextureToCanvas(texture);
    return ui_web.createImageFromTextureSource(
      _canvas as JSAny,
      width: texture.width,
      height: texture.height,
      transferOwnership: transferOwnership,
    );
  }
}

/// The default graphics context. Lazily initialized.
final GpuContext gpuContext = GpuContext._createDefault();

/// Blit [texture]'s contents onto the GpuContext's `OffscreenCanvas` and
/// return it as a `ui.Image` for display in a Flutter widget. Web-only;
/// throws on native backends.
///
/// Bridge helper between offscreen-rendered Textures and Flutter widgets
/// until the swapchain / on-screen presentation story lands in Phase 5.
Future<ui.Image> presentTextureAsImage(
  Texture texture, {
  bool transferOwnership = false,
}) => gpuContext._presentTextureAsImage(
  texture,
  transferOwnership: transferOwnership,
);
