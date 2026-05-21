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
  }

  late final web.OffscreenCanvas _canvas;
  late final web.WebGL2RenderingContext _gl;

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
    TextureCoordinateSystem coordinateSystem =
        TextureCoordinateSystem.renderToTexture,
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
      coordinateSystem,
      resolvedType,
      enableRenderTargetUsage,
      enableShaderReadUsage,
      enableShaderWriteUsage,
      mipLevelCount,
    );
  }

  CommandBuffer createCommandBuffer() => CommandBuffer._(this);

  RenderPipeline createRenderPipeline(
    Shader vertexShader,
    Shader fragmentShader, {
    VertexLayout? vertexLayout,
  }) {
    return RenderPipeline._(
      this,
      vertexShader,
      fragmentShader,
      vertexLayout: vertexLayout,
    );
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

  /// Blit [texture]'s contents onto the underlying `OffscreenCanvas` and
  /// return it as a `ui.Image`. The bridge between offscreen-rendered
  /// Textures and Flutter widgets until a proper present/swapchain story
  /// lands in Phase 5. Web-specific; not in flutter_gpu. Prefer the
  /// top-level [presentTextureAsImage] which works through the unified
  /// shim API on every backend.
  Future<ui.Image> _presentTextureAsImage(
    Texture texture, {
    bool transferOwnership = false,
  }) async {
    if (texture.sampleCount != 1) {
      throw UnimplementedError(
        'presentTextureAsImage on MSAA textures requires a resolve pass; '
        'use the resolved single-sample texture instead.',
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
    // Straight 1:1 blit. The browser's createImageFromTextureSource handles
    // the GL-vs-canvas origin difference, so an explicit Y-flip here would
    // double-flip and render the image upside down.
    _gl.blitFramebuffer(
      0,
      0,
      texture.width,
      texture.height,
      0,
      0,
      texture.width,
      texture.height,
      web.WebGL2RenderingContext.COLOR_BUFFER_BIT,
      web.WebGL2RenderingContext.NEAREST,
    );
    _gl.bindFramebuffer(web.WebGL2RenderingContext.FRAMEBUFFER, null);
    _gl.deleteFramebuffer(readFbo);

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
