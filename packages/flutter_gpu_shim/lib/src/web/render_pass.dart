part of '_gpu.dart';

// ---------------------------------------------------------------------------
// Render-target value types (mirroring flutter_gpu).
// ---------------------------------------------------------------------------

base class ColorAttachment {
  ColorAttachment({
    this.loadAction = LoadAction.clear,
    this.storeAction = StoreAction.store,
    vm.Vector4? clearValue,
    required this.texture,
    this.resolveTexture,
  }) : clearValue = clearValue ?? vm.Vector4.zero();

  LoadAction loadAction;
  StoreAction storeAction;
  vm.Vector4 clearValue;
  Texture texture;
  Texture? resolveTexture;
}

base class DepthStencilAttachment {
  DepthStencilAttachment({
    this.depthLoadAction = LoadAction.clear,
    this.depthStoreAction = StoreAction.dontCare,
    this.depthClearValue = 1.0,
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

enum StencilFace { both, front, back }

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

base class Viewport {
  const Viewport({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    this.minDepth = 0.0,
    this.maxDepth = 1.0,
  });

  final double x;
  final double y;
  final double width;
  final double height;
  final double minDepth;
  final double maxDepth;
}

base class RenderTarget {
  const RenderTarget({
    this.colorAttachments = const <ColorAttachment>[],
    this.depthStencilAttachment,
  });

  RenderTarget.singleColor(
    ColorAttachment colorAttachment, {
    DepthStencilAttachment? depthStencilAttachment,
  }) : this(
         colorAttachments: [colorAttachment],
         depthStencilAttachment: depthStencilAttachment,
       );

  final List<ColorAttachment> colorAttachments;
  final DepthStencilAttachment? depthStencilAttachment;
}

// ---------------------------------------------------------------------------
// RenderPass: records bind / state / draw calls and immediately issues them
// against the GpuContext's GL2 context. Phase 1 is "draw a triangle" so most
// state setters are stubbed.
// ---------------------------------------------------------------------------

base class RenderPass {
  RenderPass._(this._gpuContext, this._target) {
    _bindFramebuffer();
    _applyLoadActions();
  }

  final GpuContext _gpuContext;
  final RenderTarget _target;

  RenderPipeline? _boundPipeline;
  web.WebGLVertexArrayObject? _vao;
  int _drawVertexCount = 0;
  PrimitiveType _primitiveType = PrimitiveType.triangle;

  BufferView? _indexBufferView;
  IndexType _indexType = IndexType.int32;
  int _indexCount = 0;

  void _ensureVao() {
    final gl = _gpuContext._gl;
    _vao ??= gl.createVertexArray();
    gl.bindVertexArray(_vao);
  }

  // ---- framebuffer setup ---------------------------------------------------

  void _bindFramebuffer() {
    final gl = _gpuContext._gl;

    if (_target.colorAttachments.isEmpty) {
      throw Exception('RenderTarget must have at least one color attachment');
    }
    final color = _target.colorAttachments.first.texture;

    final fbo = gl.createFramebuffer();
    if (fbo == null) {
      throw StateError('Failed to create WebGL framebuffer');
    }
    gl.bindFramebuffer(web.WebGL2RenderingContext.FRAMEBUFFER, fbo);

    if (color.sampleCount == 1) {
      gl.framebufferTexture2D(
        web.WebGL2RenderingContext.FRAMEBUFFER,
        web.WebGL2RenderingContext.COLOR_ATTACHMENT0,
        web.WebGL2RenderingContext.TEXTURE_2D,
        color.glTexture,
        0,
      );
    } else {
      gl.framebufferRenderbuffer(
        web.WebGL2RenderingContext.FRAMEBUFFER,
        web.WebGL2RenderingContext.COLOR_ATTACHMENT0,
        web.WebGL2RenderingContext.RENDERBUFFER,
        color.glRenderbuffer,
      );
    }

    final depth = _target.depthStencilAttachment?.texture;
    if (depth != null) {
      if (depth.sampleCount == 1) {
        gl.framebufferTexture2D(
          web.WebGL2RenderingContext.FRAMEBUFFER,
          web.WebGL2RenderingContext.DEPTH_STENCIL_ATTACHMENT,
          web.WebGL2RenderingContext.TEXTURE_2D,
          depth.glTexture,
          0,
        );
      } else {
        gl.framebufferRenderbuffer(
          web.WebGL2RenderingContext.FRAMEBUFFER,
          web.WebGL2RenderingContext.DEPTH_STENCIL_ATTACHMENT,
          web.WebGL2RenderingContext.RENDERBUFFER,
          depth.glRenderbuffer,
        );
      }
    }

    final status = gl.checkFramebufferStatus(
      web.WebGL2RenderingContext.FRAMEBUFFER,
    );
    if (status != web.WebGL2RenderingContext.FRAMEBUFFER_COMPLETE) {
      throw Exception(
        'Framebuffer incomplete (status 0x${status.toRadixString(16)})',
      );
    }
    gl.viewport(0, 0, color.width, color.height);
  }

  void _applyLoadActions() {
    final gl = _gpuContext._gl;
    int clearMask = 0;

    final color = _target.colorAttachments.first;
    if (color.loadAction == LoadAction.clear) {
      gl.clearColor(
        color.clearValue.x,
        color.clearValue.y,
        color.clearValue.z,
        color.clearValue.w,
      );
      clearMask |= web.WebGL2RenderingContext.COLOR_BUFFER_BIT;
    }
    final depth = _target.depthStencilAttachment;
    if (depth != null) {
      if (depth.depthLoadAction == LoadAction.clear) {
        gl.clearDepth(depth.depthClearValue);
        clearMask |= web.WebGL2RenderingContext.DEPTH_BUFFER_BIT;
      }
      if (depth.stencilLoadAction == LoadAction.clear) {
        gl.clearStencil(depth.stencilClearValue);
        clearMask |= web.WebGL2RenderingContext.STENCIL_BUFFER_BIT;
      }
    }
    if (clearMask != 0) {
      gl.clear(clearMask);
    }
  }

  // ---- public API ----------------------------------------------------------

  void bindPipeline(RenderPipeline pipeline) {
    final gl = _gpuContext._gl;
    _boundPipeline = pipeline;
    gl.useProgram(pipeline._program);
  }

  void bindVertexBuffer(BufferView bufferView, int vertexCount) {
    final gl = _gpuContext._gl;
    final pipeline = _boundPipeline;
    if (pipeline == null) {
      throw StateError('bindVertexBuffer called before bindPipeline');
    }

    _ensureVao();
    bufferView.buffer._bindForTarget(web.WebGL2RenderingContext.ARRAY_BUFFER);

    final inputs = pipeline.vertexShader.vertexInputs;
    if (inputs.isEmpty) {
      // Inline pipelines without reflection: assume a single vec2 / vec3 /
      // vec4 attribute named "position" or whatever the linker assigned to
      // location 0, packed tightly. Caller is responsible for matching
      // the shader source's input declaration.
      final location = gl.getAttribLocation(pipeline._program, 'position');
      if (location < 0) {
        throw Exception(
          'RenderPipeline has no `position` attribute and no reflected '
          'vertex inputs. Use a ShaderLibrary built from a bundle for '
          'pipelines with non-trivial vertex layouts.',
        );
      }
      // Infer component count from vertexCount + buffer size.
      final perVertex = bufferView.lengthInBytes ~/ vertexCount;
      final components = perVertex ~/ 4;
      gl.enableVertexAttribArray(location);
      gl.vertexAttribPointer(
        location,
        components,
        web.WebGL2RenderingContext.FLOAT,
        false,
        perVertex,
        bufferView.offsetInBytes,
      );
    } else {
      final stride = pipeline.vertexShader.vertexStride;
      for (final input in inputs) {
        gl.enableVertexAttribArray(input.location);
        gl.vertexAttribPointer(
          input.location,
          input.componentCount,
          web.WebGL2RenderingContext.FLOAT,
          false,
          stride,
          bufferView.offsetInBytes + input.offsetInBytes,
        );
      }
    }

    _drawVertexCount = vertexCount;
  }

  void bindIndexBuffer(
    BufferView bufferView,
    IndexType indexType,
    int indexCount,
  ) {
    // ELEMENT_ARRAY_BUFFER binding is captured in VAO state, so the VAO must
    // be bound first.
    _ensureVao();
    bufferView.buffer._bindForTarget(
      web.WebGL2RenderingContext.ELEMENT_ARRAY_BUFFER,
    );
    _indexBufferView = bufferView;
    _indexType = indexType;
    _indexCount = indexCount;
  }

  void bindUniform(UniformSlot slot, BufferView bufferView) {
    final pipeline = _boundPipeline;
    if (pipeline == null) {
      throw StateError('bindUniform called before bindPipeline');
    }
    final struct = slot.shader._uniformStructs[slot.uniformName];
    if (struct == null) return;

    final gl = _gpuContext._gl;
    final staging = bufferView.buffer._staging;
    final base = bufferView.offsetInBytes;
    for (final member in struct.members) {
      final loc = pipeline._memberLocations['${struct.name}.${member.name}'];
      if (loc == null) continue; // optimized out by the linker
      _setUniformMember(gl, loc, member, staging, base + member.offsetInBytes);
    }
  }

  void _setUniformMember(
    web.WebGL2RenderingContext gl,
    web.WebGLUniformLocation loc,
    _UniformMember member,
    Uint8List staging,
    int byteOffset,
  ) {
    final floatCount = member.vecSize * member.columns * member.elementCount;
    // View the staged bytes as floats. Uniform members are 4-byte aligned.
    final floats = staging.buffer.asFloat32List(
      staging.offsetInBytes + byteOffset,
      floatCount,
    );
    if (member.columns == 1) {
      switch (member.vecSize) {
        case 1:
          gl.uniform1fv(loc, floats.toJS);
        case 2:
          gl.uniform2fv(loc, floats.toJS);
        case 3:
          gl.uniform3fv(loc, floats.toJS);
        case 4:
          gl.uniform4fv(loc, floats.toJS);
      }
    } else {
      // Matrix. NB: mat2/mat3 stored with std140 column padding would need
      // repacking; mat4 is tightly packed and matches GL. flutter_scene's
      // mesh shaders use mat4, so mat4 is the path that's exercised today.
      switch (member.columns) {
        case 2:
          gl.uniformMatrix2fv(loc, false, floats.toJS);
        case 3:
          gl.uniformMatrix3fv(loc, false, floats.toJS);
        case 4:
          gl.uniformMatrix4fv(loc, false, floats.toJS);
      }
    }
  }

  void bindTexture(
    UniformSlot slot,
    Texture texture, {
    SamplerOptions? sampler,
  }) {
    final pipeline = _boundPipeline;
    if (pipeline == null) {
      throw StateError('bindTexture called before bindPipeline');
    }
    final unit = pipeline._samplerUnits[slot.uniformName];
    if (unit == null) return;

    final gl = _gpuContext._gl;
    gl.activeTexture(web.WebGL2RenderingContext.TEXTURE0 + unit);
    gl.bindTexture(web.WebGL2RenderingContext.TEXTURE_2D, texture.glTexture);
    if (sampler != null) {
      gl.texParameteri(
        web.WebGL2RenderingContext.TEXTURE_2D,
        web.WebGL2RenderingContext.TEXTURE_MIN_FILTER,
        sampler.minFilter == MinMagFilter.nearest
            ? web.WebGL2RenderingContext.NEAREST
            : web.WebGL2RenderingContext.LINEAR,
      );
      gl.texParameteri(
        web.WebGL2RenderingContext.TEXTURE_2D,
        web.WebGL2RenderingContext.TEXTURE_MAG_FILTER,
        sampler.magFilter == MinMagFilter.nearest
            ? web.WebGL2RenderingContext.NEAREST
            : web.WebGL2RenderingContext.LINEAR,
      );
      gl.texParameteri(
        web.WebGL2RenderingContext.TEXTURE_2D,
        web.WebGL2RenderingContext.TEXTURE_WRAP_S,
        _glAddressMode(sampler.widthAddressMode),
      );
      gl.texParameteri(
        web.WebGL2RenderingContext.TEXTURE_2D,
        web.WebGL2RenderingContext.TEXTURE_WRAP_T,
        _glAddressMode(sampler.heightAddressMode),
      );
    }
  }

  static int _glAddressMode(SamplerAddressMode mode) {
    switch (mode) {
      case SamplerAddressMode.clampToEdge:
        return web.WebGL2RenderingContext.CLAMP_TO_EDGE;
      case SamplerAddressMode.repeat:
        return web.WebGL2RenderingContext.REPEAT;
      case SamplerAddressMode.mirror:
        return web.WebGL2RenderingContext.MIRRORED_REPEAT;
    }
  }

  void clearBindings() {
    final gl = _gpuContext._gl;
    if (_vao != null) {
      gl.bindVertexArray(null);
    }
    _boundPipeline = null;
    _drawVertexCount = 0;
    _indexBufferView = null;
    _indexCount = 0;
  }

  void setColorBlendEnable(bool enable, {int colorAttachmentIndex = 0}) {
    /* Phase 3 */
  }
  void setColorBlendEquation(
    ColorBlendEquation equation, {
    int colorAttachmentIndex = 0,
  }) {
    /* Phase 3 */
  }
  void setDepthWriteEnable(bool enable) {
    /* Phase 3 */
  }
  void setDepthCompareOperation(CompareFunction compareFunction) {
    /* Phase 3 */
  }
  void setStencilReference(int referenceValue) {
    /* not implemented */
  }
  void setStencilConfig(
    StencilConfig configuration, {
    StencilFace targetFace = StencilFace.both,
  }) {
    /* not implemented */
  }
  void setCullMode(CullMode cullMode) {
    /* Phase 3 */
  }
  void setPolygonMode(PolygonMode polygonMode) {
    /* not implemented */
  }
  void setPrimitiveType(PrimitiveType primitiveType) {
    _primitiveType = primitiveType;
  }

  void setWindingOrder(WindingOrder windingOrder) {
    /* Phase 3 */
  }

  void setViewport(Viewport viewport) {
    final gl = _gpuContext._gl;
    gl.viewport(
      viewport.x.toInt(),
      viewport.y.toInt(),
      viewport.width.toInt(),
      viewport.height.toInt(),
    );
  }

  void draw() {
    final gl = _gpuContext._gl;
    if (_boundPipeline == null) {
      throw StateError('draw called before bindPipeline');
    }
    final indexView = _indexBufferView;
    if (indexView != null) {
      gl.drawElements(
        _glPrimitiveType(_primitiveType),
        _indexCount,
        _indexType == IndexType.int16
            ? web.WebGL2RenderingContext.UNSIGNED_SHORT
            : web.WebGL2RenderingContext.UNSIGNED_INT,
        indexView.offsetInBytes,
      );
    } else {
      gl.drawArrays(_glPrimitiveType(_primitiveType), 0, _drawVertexCount);
    }
  }

  static int _glPrimitiveType(PrimitiveType p) {
    switch (p) {
      case PrimitiveType.triangle:
        return web.WebGL2RenderingContext.TRIANGLES;
      case PrimitiveType.triangleStrip:
        return web.WebGL2RenderingContext.TRIANGLE_STRIP;
      case PrimitiveType.line:
        return web.WebGL2RenderingContext.LINES;
      case PrimitiveType.lineStrip:
        return web.WebGL2RenderingContext.LINE_STRIP;
      case PrimitiveType.point:
        return web.WebGL2RenderingContext.POINTS;
    }
  }
}
