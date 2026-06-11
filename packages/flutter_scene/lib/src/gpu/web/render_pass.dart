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
    // Reset the fixed-function state that GL holds globally but Impeller
    // scopes per pass. Cull mode and winding order otherwise leak from the
    // previous pass's last draw into a pass that doesn't set them (e.g. the
    // full-screen tonemap blit, which inherits whatever the scene pass left
    // bound). A mirrored (negative-determinant) node leaves the winding
    // flipped, which would then back-face cull the blit and blank the frame.
    // Mirrors Impeller's GLES backend, which re-initialises this state at the
    // start of every pass encode.
    final gl = _gpuContext._gl;
    gl.disable(web.WebGL2RenderingContext.CULL_FACE);
    gl.frontFace(web.WebGL2RenderingContext.CCW);
  }

  final GpuContext _gpuContext;
  final RenderTarget _target;

  RenderPipeline? _boundPipeline;
  web.WebGLVertexArrayObject? _vao;
  PrimitiveType _primitiveType = PrimitiveType.triangle;
  BufferView? _inlineVertexBufferView;

  BufferView? _indexBufferView;
  IndexType _indexType = IndexType.int32;

  web.WebGLFramebuffer? _fbo;
  bool _finished = false;

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
    final depth = _target.depthStencilAttachment?.texture;

    // Configured framebuffers (including the completeness check, a
    // synchronous GPU round trip) are cached per attachment combination.
    final fbo = _gpuContext._framebufferFor(
      color,
      depth,
      () => _createFramebuffer(gl, color, depth),
    );
    _fbo = fbo;
    gl.bindFramebuffer(web.WebGL2RenderingContext.FRAMEBUFFER, fbo);
    gl.viewport(0, 0, color.width, color.height);
  }

  static web.WebGLFramebuffer _createFramebuffer(
    web.WebGL2RenderingContext gl,
    Texture color,
    Texture? depth,
  ) {
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
    return fbo;
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
        // glClear(DEPTH) respects depthMask, which a prior draw may have
        // turned off; force it on so the clear actually writes.
        gl.depthMask(true);
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

  void bindVertexBuffer(BufferView bufferView, {int slot = 0}) {
    final gl = _gpuContext._gl;
    final pipeline = _boundPipeline;
    if (pipeline == null) {
      throw StateError('bindVertexBuffer called before bindPipeline');
    }

    final layout = pipeline.vertexLayout;
    if (layout == null && slot != 0) {
      throw RangeError.value(
        slot,
        'slot',
        'Slots other than 0 need an explicit pipeline VertexLayout',
      );
    }

    _ensureVao();
    bufferView.buffer._bindForTarget(web.WebGL2RenderingContext.ARRAY_BUFFER);

    if (layout != null) {
      // Explicit layout: the buffer's slot describes its stride, step mode,
      // and named attributes; the shader's reflection only supplies the
      // attribute locations.
      if (slot < 0 || slot >= layout.buffers.length) {
        throw RangeError.value(
          slot,
          'slot',
          'Pipeline VertexLayout declares ${layout.buffers.length} buffers',
        );
      }
      _inlineVertexBufferView = null;
      final buffer = layout.buffers[slot];
      final divisor = buffer.stepMode == VertexStepMode.instance ? 1 : 0;
      for (final attribute in buffer.attributes) {
        final input = pipeline.vertexShader.vertexInputByName(attribute.name);
        if (input == null) {
          throw StateError(
            'Vertex shader has no input named "${attribute.name}"',
          );
        }
        if (attribute.format.name.startsWith('uint') ||
            attribute.format.name.startsWith('sint')) {
          throw UnimplementedError(
            'Integer vertex formats are not implemented in the WebGL2 '
            'backend',
          );
        }
        gl.enableVertexAttribArray(input.location);
        gl.vertexAttribPointer(
          input.location,
          attribute.format.componentCount,
          web.WebGL2RenderingContext.FLOAT,
          false,
          buffer.strideInBytes,
          bufferView.offsetInBytes + attribute.offsetInBytes,
        );
        gl.vertexAttribDivisor(input.location, divisor);
      }
      return;
    }

    final inputs = pipeline.vertexShader.vertexInputs;
    if (inputs.isEmpty) {
      _inlineVertexBufferView = bufferView;
    } else {
      _inlineVertexBufferView = null;
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
        // Divisor state lives in the VAO and may be left over from an
        // instanced layout; reset it for vertex-rate inputs.
        gl.vertexAttribDivisor(input.location, 0);
      }
    }
  }

  void bindIndexBuffer(BufferView bufferView, IndexType indexType) {
    // ELEMENT_ARRAY_BUFFER binding is captured in VAO state, so the VAO must
    // be bound first.
    _ensureVao();
    bufferView.buffer._bindForTarget(
      web.WebGL2RenderingContext.ELEMENT_ARRAY_BUFFER,
    );
    _indexBufferView = bufferView;
    _indexType = indexType;
  }

  void bindUniform(UniformSlot slot, BufferView bufferView) {
    final pipeline = _boundPipeline;
    if (pipeline == null) {
      throw StateError('bindUniform called before bindPipeline');
    }
    final struct = slot.shader._uniformStructs[slot.uniformName];
    if (struct == null) return;

    final gl = _gpuContext._gl;
    final floats = bufferView.buffer._stagingFloats;
    final base = bufferView.offsetInBytes;
    final locations = pipeline._structLocations[struct.name];
    for (var i = 0; i < struct.members.length; i++) {
      final loc = locations?[i];
      if (loc == null) continue; // optimized out by the linker
      final member = struct.members[i];
      _setUniformMember(gl, loc, member, floats, base + member.offsetInBytes);
    }
  }

  // Scratch for the rare matrix repack; grows to the largest repacked member
  // and is reused across draws.
  static Float32List _matrixScratch = Float32List(64);

  void _setUniformMember(
    web.WebGL2RenderingContext gl,
    web.WebGLUniformLocation loc,
    _UniformMember member,
    Float32List floats,
    int byteOffset,
  ) {
    final floatOffset = byteOffset >> 2;
    if (member.columns > 1) {
      // Matrix, possibly an array. In std140 each matrix column is aligned
      // to 16 bytes (a mat3 column is a vec3 padded to vec4); GL's
      // uniformMatrix*fv wants tightly-packed columns. The matrix count
      // comes from the total size, not arrayElements (which Impeller
      // overloads to mean column count for a standalone matrix).
      const columnStride = 16;
      final cols = member.columns;
      final rows = member.vecSize;
      final count = member.totalSizeInBytes ~/ (cols * columnStride);
      if (rows * 4 == columnStride) {
        // mat4 columns are already tight in std140; upload straight from the
        // staging view with no copy (the overwhelmingly common case).
        gl.uniformMatrix4fv(loc, false, floats.toJS, floatOffset, count * 16);
        return;
      }
      final tightLength = count * cols * rows;
      if (_matrixScratch.length < tightLength) {
        _matrixScratch = Float32List(tightLength);
      }
      final tight = _matrixScratch;
      var w = 0;
      for (var m = 0; m < count; m++) {
        for (var c = 0; c < cols; c++) {
          final col = floatOffset + (m * cols + c) * (columnStride >> 2);
          for (var r = 0; r < rows; r++) {
            tight[w++] = floats[col + r];
          }
        }
      }
      switch (cols) {
        case 2:
          gl.uniformMatrix2fv(loc, false, tight.toJS, 0, tightLength);
        case 3:
          gl.uniformMatrix3fv(loc, false, tight.toJS, 0, tightLength);
      }
    } else {
      // Vector / scalar, possibly an array. vec4 arrays are tightly packed
      // (16-byte elements); vec3/vec2/scalar arrays would have std140
      // padding, but flutter_scene's uniforms don't use those.
      final count = member.arrayElements == 0 ? 1 : member.arrayElements;
      final length = member.vecSize * count;
      switch (member.vecSize) {
        case 1:
          gl.uniform1fv(loc, floats.toJS, floatOffset, length);
        case 2:
          gl.uniform2fv(loc, floats.toJS, floatOffset, length);
        case 3:
          gl.uniform3fv(loc, floats.toJS, floatOffset, length);
        case 4:
          gl.uniform4fv(loc, floats.toJS, floatOffset, length);
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
    // Clears per-draw resource bindings (vertex/index buffers, uniforms,
    // textures) but NOT the bound pipeline - matching flutter_gpu, where the
    // pipeline persists until the next bindPipeline. flutter_scene's encoder
    // relies on this: it caches the last pipeline and skips re-binding it
    // across consecutive draws with the same material, so nulling it here
    // would leave later draws with no pipeline.
    final gl = _gpuContext._gl;
    if (_vao != null) {
      gl.bindVertexArray(null);
    }
    _inlineVertexBufferView = null;
    _indexBufferView = null;
  }

  void setColorBlendEnable(bool enable, {int colorAttachmentIndex = 0}) {
    final gl = _gpuContext._gl;
    if (enable) {
      gl.enable(web.WebGL2RenderingContext.BLEND);
    } else {
      gl.disable(web.WebGL2RenderingContext.BLEND);
    }
  }

  void setColorBlendEquation(
    ColorBlendEquation equation, {
    int colorAttachmentIndex = 0,
  }) {
    final gl = _gpuContext._gl;
    gl.blendEquationSeparate(
      _glBlendOp(equation.colorBlendOperation),
      _glBlendOp(equation.alphaBlendOperation),
    );
    gl.blendFuncSeparate(
      _glBlendFactor(equation.sourceColorBlendFactor),
      _glBlendFactor(equation.destinationColorBlendFactor),
      _glBlendFactor(equation.sourceAlphaBlendFactor),
      _glBlendFactor(equation.destinationAlphaBlendFactor),
    );
  }

  void setDepthWriteEnable(bool enable) {
    _gpuContext._gl.depthMask(enable);
  }

  void setDepthCompareOperation(CompareFunction compareFunction) {
    final gl = _gpuContext._gl;
    if (compareFunction == CompareFunction.always) {
      gl.disable(web.WebGL2RenderingContext.DEPTH_TEST);
    } else {
      gl.enable(web.WebGL2RenderingContext.DEPTH_TEST);
      gl.depthFunc(_glCompare(compareFunction));
    }
  }

  void setStencilReference(int referenceValue) {
    /* not implemented; flutter_scene does not use stencil */
  }
  void setStencilConfig(
    StencilConfig configuration, {
    StencilFace targetFace = StencilFace.both,
  }) {
    /* not implemented; flutter_scene does not use stencil */
  }

  void setCullMode(CullMode cullMode) {
    final gl = _gpuContext._gl;
    switch (cullMode) {
      case CullMode.none:
        gl.disable(web.WebGL2RenderingContext.CULL_FACE);
      case CullMode.frontFace:
        gl.enable(web.WebGL2RenderingContext.CULL_FACE);
        gl.cullFace(web.WebGL2RenderingContext.FRONT);
      case CullMode.backFace:
        gl.enable(web.WebGL2RenderingContext.CULL_FACE);
        gl.cullFace(web.WebGL2RenderingContext.BACK);
    }
  }

  void setPolygonMode(PolygonMode polygonMode) {
    /* not implemented; WebGL2 has no glPolygonMode */
  }

  void setPrimitiveType(PrimitiveType primitiveType) {
    _primitiveType = primitiveType;
  }

  void setWindingOrder(WindingOrder windingOrder) {
    // Inverted relative to the requested order: the generated GLES vertex
    // shaders multiply gl_Position.y by `_impeller_y_flip = -1`, which mirrors
    // triangle winding while storing render targets top-down.
    _gpuContext._gl.frontFace(
      windingOrder == WindingOrder.clockwise
          ? web.WebGL2RenderingContext.CCW
          : web.WebGL2RenderingContext.CW,
    );
  }

  static int _glCompare(CompareFunction f) {
    switch (f) {
      case CompareFunction.never:
        return web.WebGL2RenderingContext.NEVER;
      case CompareFunction.always:
        return web.WebGL2RenderingContext.ALWAYS;
      case CompareFunction.less:
        return web.WebGL2RenderingContext.LESS;
      case CompareFunction.equal:
        return web.WebGL2RenderingContext.EQUAL;
      case CompareFunction.lessEqual:
        return web.WebGL2RenderingContext.LEQUAL;
      case CompareFunction.greater:
        return web.WebGL2RenderingContext.GREATER;
      case CompareFunction.notEqual:
        return web.WebGL2RenderingContext.NOTEQUAL;
      case CompareFunction.greaterEqual:
        return web.WebGL2RenderingContext.GEQUAL;
    }
  }

  static int _glBlendOp(BlendOperation op) {
    switch (op) {
      case BlendOperation.add:
        return web.WebGL2RenderingContext.FUNC_ADD;
      case BlendOperation.subtract:
        return web.WebGL2RenderingContext.FUNC_SUBTRACT;
      case BlendOperation.reverseSubtract:
        return web.WebGL2RenderingContext.FUNC_REVERSE_SUBTRACT;
    }
  }

  static int _glBlendFactor(BlendFactor f) {
    switch (f) {
      case BlendFactor.zero:
        return web.WebGL2RenderingContext.ZERO;
      case BlendFactor.one:
        return web.WebGL2RenderingContext.ONE;
      case BlendFactor.sourceColor:
        return web.WebGL2RenderingContext.SRC_COLOR;
      case BlendFactor.oneMinusSourceColor:
        return web.WebGL2RenderingContext.ONE_MINUS_SRC_COLOR;
      case BlendFactor.sourceAlpha:
        return web.WebGL2RenderingContext.SRC_ALPHA;
      case BlendFactor.oneMinusSourceAlpha:
        return web.WebGL2RenderingContext.ONE_MINUS_SRC_ALPHA;
      case BlendFactor.destinationColor:
        return web.WebGL2RenderingContext.DST_COLOR;
      case BlendFactor.oneMinusDestinationColor:
        return web.WebGL2RenderingContext.ONE_MINUS_DST_COLOR;
      case BlendFactor.destinationAlpha:
        return web.WebGL2RenderingContext.DST_ALPHA;
      case BlendFactor.oneMinusDestinationAlpha:
        return web.WebGL2RenderingContext.ONE_MINUS_DST_ALPHA;
      case BlendFactor.sourceAlphaSaturated:
        return web.WebGL2RenderingContext.SRC_ALPHA_SATURATE;
      case BlendFactor.blendColor:
        return web.WebGL2RenderingContext.CONSTANT_COLOR;
      case BlendFactor.oneMinusBlendColor:
        return web.WebGL2RenderingContext.ONE_MINUS_CONSTANT_COLOR;
      case BlendFactor.blendAlpha:
        return web.WebGL2RenderingContext.CONSTANT_ALPHA;
      case BlendFactor.oneMinusBlendAlpha:
        return web.WebGL2RenderingContext.ONE_MINUS_CONSTANT_ALPHA;
    }
  }

  void setViewport(Viewport viewport) {
    final gl = _gpuContext._gl;
    gl.viewport(viewport.x, viewport.y, viewport.width, viewport.height);
    gl.depthRange(viewport.depthRange.zNear, viewport.depthRange.zFar);
  }

  void _configureInlineVertexBuffer(int vertexCount) {
    final pipeline = _boundPipeline;
    final bufferView = _inlineVertexBufferView;
    if (pipeline == null || bufferView == null) return;
    final gl = _gpuContext._gl;
    final location = gl.getAttribLocation(pipeline._program, 'position');
    if (location < 0) {
      throw Exception(
        'RenderPipeline has no `position` attribute and no reflected '
        'vertex inputs. Use a ShaderLibrary built from a bundle for '
        'pipelines with non-trivial vertex layouts.',
      );
    }
    final perVertex = bufferView.lengthInBytes ~/ vertexCount;
    final components = perVertex ~/ 4;
    bufferView.buffer._bindForTarget(web.WebGL2RenderingContext.ARRAY_BUFFER);
    gl.enableVertexAttribArray(location);
    gl.vertexAttribPointer(
      location,
      components,
      web.WebGL2RenderingContext.FLOAT,
      false,
      perVertex,
      bufferView.offsetInBytes,
    );
  }

  void draw(int vertexCount, {int instanceCount = 1}) {
    final gl = _gpuContext._gl;
    if (_boundPipeline == null) {
      throw StateError('draw called before bindPipeline');
    }
    if (vertexCount == 0 || instanceCount == 0) return;
    _configureInlineVertexBuffer(vertexCount);
    if (instanceCount != 1) {
      gl.drawArraysInstanced(
        _glPrimitiveType(_primitiveType),
        0,
        vertexCount,
        instanceCount,
      );
    } else {
      gl.drawArrays(_glPrimitiveType(_primitiveType), 0, vertexCount);
    }
  }

  void drawIndexed(int indexCount, {int instanceCount = 1}) {
    final gl = _gpuContext._gl;
    if (_boundPipeline == null) {
      throw StateError('drawIndexed called before bindPipeline');
    }
    if (_inlineVertexBufferView != null) {
      throw StateError('Indexed inline pipelines require reflected attributes');
    }
    if (indexCount == 0 || instanceCount == 0) return;
    final indexView = _indexBufferView;
    if (indexView == null) {
      throw StateError('drawIndexed called before bindIndexBuffer');
    }
    final glIndexType = _indexType == IndexType.int16
        ? web.WebGL2RenderingContext.UNSIGNED_SHORT
        : web.WebGL2RenderingContext.UNSIGNED_INT;
    if (instanceCount != 1) {
      gl.drawElementsInstanced(
        _glPrimitiveType(_primitiveType),
        indexCount,
        glIndexType,
        indexView.offsetInBytes,
        instanceCount,
      );
    } else {
      gl.drawElements(
        _glPrimitiveType(_primitiveType),
        indexCount,
        glIndexType,
        indexView.offsetInBytes,
      );
    }
  }

  /// Called by CommandBuffer when the pass ends (a new pass begins, or the
  /// buffer is submitted). Resolves MSAA color attachments into their
  /// resolve textures.
  void _finish() {
    if (_finished) return;
    _finished = true;
    final gl = _gpuContext._gl;
    for (final att in _target.colorAttachments) {
      final resolve = att.resolveTexture;
      final needsResolve =
          att.texture.sampleCount > 1 &&
          resolve != null &&
          (att.storeAction == StoreAction.multisampleResolve ||
              att.storeAction == StoreAction.storeAndMultisampleResolve);
      if (needsResolve) {
        _resolveColor(gl, att.texture, resolve);
      }
    }
  }

  void _resolveColor(
    web.WebGL2RenderingContext gl,
    Texture msaa,
    Texture resolve,
  ) {
    final resolveFbo = gl.createFramebuffer();
    gl.bindFramebuffer(web.WebGL2RenderingContext.READ_FRAMEBUFFER, _fbo);
    gl.bindFramebuffer(web.WebGL2RenderingContext.DRAW_FRAMEBUFFER, resolveFbo);
    gl.framebufferTexture2D(
      web.WebGL2RenderingContext.DRAW_FRAMEBUFFER,
      web.WebGL2RenderingContext.COLOR_ATTACHMENT0,
      web.WebGL2RenderingContext.TEXTURE_2D,
      resolve.glTexture,
      0,
    );
    gl.blitFramebuffer(
      0,
      0,
      msaa.width,
      msaa.height,
      0,
      0,
      resolve.width,
      resolve.height,
      web.WebGL2RenderingContext.COLOR_BUFFER_BIT,
      web.WebGL2RenderingContext.NEAREST,
    );
    gl.bindFramebuffer(web.WebGL2RenderingContext.FRAMEBUFFER, null);
    gl.deleteFramebuffer(resolveFbo);
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
