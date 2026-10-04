part of '_webgl.dart';

// ---------------------------------------------------------------------------
// RenderPass: records bind / state / draw calls and immediately issues them
// against the GpuContext's GL2 context. Phase 1 is "draw a triangle" so most
// state setters are stubbed.
// ---------------------------------------------------------------------------

/// Appended to a missing-binding error, since a bundle from an earlier build
/// reflects the same way as a name the shader never declared.
const String _staleBundleHint =
    'If the app was just rebuilt, a cache in front of the server (a service '
    'worker, a CDN) may be serving a shader bundle from the previous build.';

final class WebGlRenderPass extends RenderPass {
  WebGlRenderPass._(this._gpuContext, this._target) {
    _bindFramebuffer();
    // A scissor is per pass too, and would clip the load action's clear.
    _gpuContext._gl.disable(web.WebGL2RenderingContext.SCISSOR_TEST);
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
    gl.disable(web.WebGL2RenderingContext.STENCIL_TEST);
  }

  final WebGlContext _gpuContext;
  final RenderTarget _target;

  WebGlRenderPipeline? _boundPipeline;
  web.WebGLVertexArrayObject? _vao;

  /// Vertex-stream bindings recorded since the last [clearBindings], applied
  /// through the VAO cache when the draw is issued: (view, slot, whether the
  /// stream is instance-rate).
  final List<(BufferView, int, bool)> _pendingVertexBindings = [];

  /// Uniform-block binding points, and texture units mapped to the GL target
  /// bound there, occupied since the last [clearBindings]. Recorded so the
  /// clear can release exactly what it handed out.
  final Set<int> _boundUniformBlocks = {};
  final Map<int, int> _boundTextureUnits = {};
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
    final colorAttachment = _target.colorAttachments.first;
    final color = colorAttachment.texture;
    final mipLevel = colorAttachment.mipLevel;
    final slice = colorAttachment.slice;
    final depth = _target.depthStencilAttachment?.texture;
    // A color slice selects a cube face; depth slices/mips are not supported.
    if (slice != 0 && color.textureType != TextureType.textureCube) {
      throw UnsupportedError(
        'Rendering to a 2D texture slice is not supported on the web backend',
      );
    }
    if ((_target.depthStencilAttachment?.slice ?? 0) != 0) {
      throw UnsupportedError(
        'Rendering to a depth texture slice is not supported on the web backend',
      );
    }
    if ((_target.depthStencilAttachment?.mipLevel ?? 0) != 0) {
      throw UnsupportedError(
        'Rendering to a depth mip level is not supported on the web backend',
      );
    }

    // Configured framebuffers (including the completeness check, a
    // synchronous GPU round trip) are cached per attachment combination.
    final fbo = _gpuContext._framebufferFor(
      color,
      mipLevel,
      slice,
      depth,
      () => _createFramebuffer(gl, color, mipLevel, slice, depth),
    );
    _fbo = fbo;
    gl.bindFramebuffer(web.WebGL2RenderingContext.FRAMEBUFFER, fbo);
    gl.viewport(
      0,
      0,
      (color.width >> mipLevel).clamp(1, color.width).toInt(),
      (color.height >> mipLevel).clamp(1, color.height).toInt(),
    );
  }

  static web.WebGLFramebuffer _createFramebuffer(
    web.WebGL2RenderingContext gl,
    Texture color,
    int mipLevel,
    int slice,
    Texture? depth,
  ) {
    final fbo = gl.createFramebuffer();
    if (fbo == null) {
      throw StateError('Failed to create WebGL framebuffer');
    }
    gl.bindFramebuffer(web.WebGL2RenderingContext.FRAMEBUFFER, fbo);

    if (color.sampleCount == 1) {
      // For a cube the attachment target is the face; for 2D it is TEXTURE_2D.
      gl.framebufferTexture2D(
        web.WebGL2RenderingContext.FRAMEBUFFER,
        web.WebGL2RenderingContext.COLOR_ATTACHMENT0,
        color.webGl.glSliceTarget(slice),
        color.webGl.glTexture,
        mipLevel,
      );
    } else {
      assert(
        mipLevel == 0,
        'Multisampled attachments cannot target a mip level',
      );
      gl.framebufferRenderbuffer(
        web.WebGL2RenderingContext.FRAMEBUFFER,
        web.WebGL2RenderingContext.COLOR_ATTACHMENT0,
        web.WebGL2RenderingContext.RENDERBUFFER,
        color.webGl.glRenderbuffer,
      );
    }

    if (depth != null) {
      if (depth.sampleCount == 1) {
        gl.framebufferTexture2D(
          web.WebGL2RenderingContext.FRAMEBUFFER,
          web.WebGL2RenderingContext.DEPTH_STENCIL_ATTACHMENT,
          web.WebGL2RenderingContext.TEXTURE_2D,
          depth.webGl.glTexture,
          0,
        );
      } else {
        gl.framebufferRenderbuffer(
          web.WebGL2RenderingContext.FRAMEBUFFER,
          web.WebGL2RenderingContext.DEPTH_STENCIL_ATTACHMENT,
          web.WebGL2RenderingContext.RENDERBUFFER,
          depth.webGl.glRenderbuffer,
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
        // Like depthMask, glClear(STENCIL) respects the stencil write mask.
        gl.stencilMask(0xFF);
        gl.clearStencil(depth.stencilClearValue);
        clearMask |= web.WebGL2RenderingContext.STENCIL_BUFFER_BIT;
      }
    }
    if (clearMask != 0) {
      gl.clear(clearMask);
    }
  }

  // ---- public API ----------------------------------------------------------

  @override
  void bindPipeline(RenderPipeline pipeline) {
    final gl = _gpuContext._gl;
    _boundPipeline = pipeline.webGl;
    gl.useProgram(pipeline.webGl._program);
    // Give every active uniform block a valid (zeroed) buffer up front, so a
    // block the caller never binds does not raise a used-but-unbound uniform
    // buffer error on this backend. Explicit bindUniform calls override it.
    pipeline.webGl._bindDefaultUniformBlocks();
  }

  @override
  void bindVertexBuffer(BufferView bufferView, {int slot = 0}) {
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

    if (layout == null && pipeline.vertexShader.vertexInputs.isEmpty) {
      // Inline pipeline (no reflected attributes): configured at draw time
      // from the vertex count; not part of the cached-VAO path.
      _inlineVertexBufferView = bufferView;
      return;
    }
    _inlineVertexBufferView = null;

    var instanceRate = false;
    if (layout != null) {
      if (slot < 0 || slot >= layout.buffers.length) {
        throw RangeError.value(
          slot,
          'slot',
          'Pipeline VertexLayout declares ${layout.buffers.length} buffers',
        );
      }
      instanceRate = layout.buffers[slot].stepMode == VertexStepMode.instance;
    }
    // Deferred: applied (through the VAO cache) when the draw is issued.
    // Bindings persist across same-pipeline draws, so a re-bind replaces its
    // slot's entry rather than growing the list.
    final entry = (bufferView, slot, instanceRate);
    for (var i = 0; i < _pendingVertexBindings.length; i++) {
      if (_pendingVertexBindings[i].$2 == slot) {
        _pendingVertexBindings[i] = entry;
        return;
      }
    }
    _pendingVertexBindings.add(entry);
  }

  /// Applies one recorded vertex-stream binding to the currently bound VAO:
  /// binds the stream's GL buffer and points/enables its attributes.
  void _applyVertexBinding(BufferView bufferView, int slot) {
    final gl = _gpuContext._gl;
    final pipeline = _boundPipeline!;
    bufferView.buffer.webGl._bindForTarget(
      web.WebGL2RenderingContext.ARRAY_BUFFER,
    );

    final layout = pipeline.vertexLayout;
    if (layout != null) {
      // Explicit layout: the buffer's slot describes its stride, step mode,
      // and named attributes; the shader's reflection only supplies the
      // attribute locations.
      final buffer = layout.buffers[slot];
      final divisor = buffer.stepMode == VertexStepMode.instance ? 1 : 0;
      for (final attribute in buffer.attributes) {
        final input = pipeline.vertexShader.vertexInputByName(attribute.name);
        if (input == null) {
          throw StateError(
            'Vertex shader has no input named "${attribute.name}"',
          );
        }
        gl.enableVertexAttribArray(input.location);
        final name = attribute.format.name;
        final unsigned = name.startsWith('uint');
        if (unsigned || name.startsWith('sint')) {
          // Integer inputs (`in uvec2`) need the I variant, which keeps the
          // values integral instead of converting them to float.
          gl.vertexAttribIPointer(
            input.location,
            attribute.format.componentCount,
            unsigned
                ? web.WebGL2RenderingContext.UNSIGNED_INT
                : web.WebGL2RenderingContext.INT,
            buffer.strideInBytes,
            bufferView.offsetInBytes + attribute.offsetInBytes,
          );
        } else {
          gl.vertexAttribPointer(
            input.location,
            attribute.format.componentCount,
            web.WebGL2RenderingContext.FLOAT,
            false,
            buffer.strideInBytes,
            bufferView.offsetInBytes + attribute.offsetInBytes,
          );
        }
        gl.vertexAttribDivisor(input.location, divisor);
      }
      return;
    }

    final inputs = pipeline.vertexShader.vertexInputs;
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

  /// Binds the vertex (and, when [needsIndex] is set, index) state for the
  /// draw being issued, through a cached VAO.
  ///
  /// Vertex-attribute specification is the dominant per-draw GL traffic, and
  /// on the web every GL call is validated in the browser's GPU process, so
  /// re-specifying stable geometry streams per draw is expensive out of all
  /// proportion to the Dart-side cost. Geometry streams are stable per
  /// (pipeline, buffers, offsets), so their full attribute state is captured
  /// in a VAO once and re-bound with a single call thereafter.
  ///
  /// Instance-rate streams are excluded from the cache key and re-pointed on
  /// the bound VAO every draw: they ride the per-frame bump allocator, so
  /// their offset changes per draw and every instanced draw re-points them
  /// anyway.
  void _applyVertexState({required bool needsIndex}) {
    if (_inlineVertexBufferView != null) {
      _ensureVao();
      return;
    }
    final gl = _gpuContext._gl;
    final pipeline = _boundPipeline!;
    final key = StringBuffer()..write(identityHashCode(pipeline));
    for (final (view, slot, instanceRate) in _pendingVertexBindings) {
      if (instanceRate) continue;
      key
        ..write('|')
        ..write(identityHashCode(view.buffer))
        ..write(':')
        ..write(view.offsetInBytes)
        ..write(':')
        ..write(slot);
    }
    final indexView = needsIndex ? _indexBufferView : null;
    if (indexView != null) {
      key
        ..write('#')
        ..write(identityHashCode(indexView.buffer))
        ..write(':')
        ..write(indexView.offsetInBytes);
    }
    final cacheKey = key.toString();
    final cache = _gpuContext._vaoCache;
    // Remove-and-reinsert keeps the map in least-recently-used order.
    var vao = cache.remove(cacheKey);
    if (vao != null) {
      cache[cacheKey] = vao;
      gl.bindVertexArray(vao);
    } else {
      vao = gl.createVertexArray();
      if (vao == null) {
        throw StateError('Failed to create WebGL vertex array');
      }
      gl.bindVertexArray(vao);
      for (final (view, slot, instanceRate) in _pendingVertexBindings) {
        if (instanceRate) continue;
        _applyVertexBinding(view, slot);
      }
      // ELEMENT_ARRAY_BUFFER binding is VAO state; capture it with the rest.
      indexView?.buffer.webGl._bindForTarget(
        web.WebGL2RenderingContext.ELEMENT_ARRAY_BUFFER,
      );
      cache[cacheKey] = vao;
      if (cache.length > WebGlContext._kMaxCachedVaos) {
        final oldest = cache.keys.first;
        gl.deleteVertexArray(cache.remove(oldest)!);
      }
    }
    for (final (view, slot, instanceRate) in _pendingVertexBindings) {
      if (instanceRate) _applyVertexBinding(view, slot);
    }
  }

  @override
  void bindIndexBuffer(BufferView bufferView, IndexType indexType) {
    // Deferred: ELEMENT_ARRAY_BUFFER binding is VAO state, applied (through
    // the VAO cache) when the draw is issued.
    _indexBufferView = bufferView;
    _indexType = indexType;
  }

  @override
  void bindUniform(UniformSlot slot, BufferView bufferView) {
    final pipeline = _boundPipeline;
    if (pipeline == null) {
      throw StateError('bindUniform called before bindPipeline');
    }
    final struct = slot.shader.webGl._uniformStructs[slot.uniformName];
    if (struct == null) {
      // Match the native backend, which throws when the shader has no uniform
      // slot of this name. Swallowing it silently binds nothing and the draw
      // reads stale uniform state, wrong only on web and only for some draw
      // orders. The lookup reads the shader's live reflection, so it stays
      // correct across hot reload.
      throw StateError(
        'Failed to bind uniform. This shader declares no uniform block named '
        '"${slot.uniformName}". A block binds by its type name, not its '
        'instance name, and a block nothing in the shader reads is optimized '
        'out by the compiler and reflects as absent. $_staleBundleHint',
      );
    }

    final gl = _gpuContext._gl;

    // GLSL ES 3.00 bundles expose the struct as a std140 uniform block;
    // attach the emplaced bytes directly as a buffer range. The emplaced
    // layout matches std140 (it is what the reflection metadata describes),
    // and HostBuffer offsets are 256-aligned, satisfying WebGL2's
    // UNIFORM_BUFFER_OFFSET_ALIGNMENT.
    final blockBinding = pipeline._structBlockBindings[struct.name];
    if (blockBinding != null) {
      final glBuffer = bufferView.buffer.webGl._bindForTarget(
        web.WebGL2RenderingContext.UNIFORM_BUFFER,
      );
      // Bind at least the driver-reported block data size; the emplaced
      // length alone can be smaller than the driver's padded size, and a
      // too-small range makes the draw a no-op. DeviceBuffer pads its GL
      // data store so the extended range stays inside the buffer.
      var lengthInBytes = bufferView.lengthInBytes;
      final minBindSize = pipeline._structBlockBindSizes[struct.name];
      if (minBindSize != null && minBindSize > lengthInBytes) {
        lengthInBytes = minBindSize;
      }
      gl.bindBufferRange(
        web.WebGL2RenderingContext.UNIFORM_BUFFER,
        blockBinding,
        glBuffer,
        bufferView.offsetInBytes,
        lengthInBytes,
      );
      _boundUniformBlocks.add(blockBinding);
      return;
    }

    final floats = bufferView.buffer.webGl._stagingFloats;
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

  @override
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
    if (unit == null) {
      // Match the native backend, which throws when the shader has no sampler
      // of this name. Swallowing it silently leaves the unit unbound and the
      // draw samples whatever texture that unit last held, wrong only on web
      // and varying with draw order. _samplerUnits comes from the shader's
      // live reflection, not GL introspection, so a reflected-but-unused
      // sampler still resolves and only a truly absent name throws.
      throw StateError(
        'Failed to bind texture. This shader declares no texture named '
        '"${slot.uniformName}". Check the sampler name spelling, and note '
        'that a sampler nothing in the shader reads is optimized out by the '
        'compiler and reflects as absent. $_staleBundleHint',
      );
    }

    final gl = _gpuContext._gl;
    final target = texture.webGl.glTarget;
    gl.activeTexture(web.WebGL2RenderingContext.TEXTURE0 + unit);
    gl.bindTexture(target, texture.webGl.glTexture);
    _boundTextureUnits[unit] = target;
    if (sampler != null) {
      // Sampler parameters are per-texture-object GL state; skip the ones
      // already applied to this texture. Per-draw texParameteri calls are
      // validated in the browser's GPU process and add up across draws.
      final minFilter = _glMinFilter(sampler, texture);
      if (texture.webGl._lastMinFilter != minFilter) {
        texture.webGl._lastMinFilter = minFilter;
        gl.texParameteri(
          target,
          web.WebGL2RenderingContext.TEXTURE_MIN_FILTER,
          minFilter,
        );
      }
      final magFilter = sampler.magFilter == MinMagFilter.nearest
          ? web.WebGL2RenderingContext.NEAREST
          : web.WebGL2RenderingContext.LINEAR;
      if (texture.webGl._lastMagFilter != magFilter) {
        texture.webGl._lastMagFilter = magFilter;
        gl.texParameteri(
          target,
          web.WebGL2RenderingContext.TEXTURE_MAG_FILTER,
          magFilter,
        );
      }
      final wrapS = _glAddressMode(sampler.widthAddressMode);
      if (texture.webGl._lastWrapS != wrapS) {
        texture.webGl._lastWrapS = wrapS;
        gl.texParameteri(
          target,
          web.WebGL2RenderingContext.TEXTURE_WRAP_S,
          wrapS,
        );
      }
      final wrapT = _glAddressMode(sampler.heightAddressMode);
      if (texture.webGl._lastWrapT != wrapT) {
        texture.webGl._lastWrapT = wrapT;
        gl.texParameteri(
          target,
          web.WebGL2RenderingContext.TEXTURE_WRAP_T,
          wrapT,
        );
      }
      final maxAniso = _gpuContext.maxSupportedAnisotropy;
      if (sampler.maxAnisotropy > 1 && maxAniso > 1) {
        // EXT_texture_filter_anisotropic: TEXTURE_MAX_ANISOTROPY_EXT = 0x84FE.
        final anisotropy = sampler.maxAnisotropy.clamp(1, maxAniso).toDouble();
        if (texture.webGl._lastAnisotropy != anisotropy) {
          texture.webGl._lastAnisotropy = anisotropy;
          gl.texParameterf(target, 0x84FE, anisotropy);
        }
      }
    }
  }

  // The GL minification filter for [sampler]. Mipmap modes apply only when
  // the texture actually has mip levels; a mipmap MIN_FILTER on a
  // single-level texture is incomplete in GL and samples black.
  static int _glMinFilter(SamplerOptions sampler, Texture texture) {
    final nearest = sampler.minFilter == MinMagFilter.nearest;
    if (texture.mipLevelCount <= 1) {
      return nearest
          ? web.WebGL2RenderingContext.NEAREST
          : web.WebGL2RenderingContext.LINEAR;
    }
    return switch ((nearest, sampler.mipFilter)) {
      (true, MipFilter.nearest) =>
        web.WebGL2RenderingContext.NEAREST_MIPMAP_NEAREST,
      (true, MipFilter.linear) =>
        web.WebGL2RenderingContext.NEAREST_MIPMAP_LINEAR,
      (false, MipFilter.nearest) =>
        web.WebGL2RenderingContext.LINEAR_MIPMAP_NEAREST,
      (false, MipFilter.linear) =>
        web.WebGL2RenderingContext.LINEAR_MIPMAP_LINEAR,
    };
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

  @override
  void clearBindings() {
    // Drops every per-draw resource binding, leaving the bound pipeline in
    // place (matching flutter_gpu, where the pipeline persists until the next
    // bindPipeline; the encoder skips rebinding a pipeline it already bound,
    // so nulling it here would leave later draws without one).
    //
    // Releasing the uniform blocks and texture units matters beyond tidiness.
    // They are GL context state rather than per-draw descriptors, so leaving
    // them attached lets a draw that should have rebound a slot read the
    // previous draw's resource and render correctly, which hides bind
    // lifetime bugs here that break on the native backends.
    final gl = _gpuContext._gl;
    if (_vao != null) {
      gl.bindVertexArray(null);
    }
    for (final binding in _boundUniformBlocks) {
      gl.bindBufferBase(
        web.WebGL2RenderingContext.UNIFORM_BUFFER,
        binding,
        null,
      );
    }
    _boundUniformBlocks.clear();
    for (final entry in _boundTextureUnits.entries) {
      gl.activeTexture(web.WebGL2RenderingContext.TEXTURE0 + entry.key);
      gl.bindTexture(entry.value, null);
    }
    _boundTextureUnits.clear();
    _inlineVertexBufferView = null;
    _indexBufferView = null;
    _pendingVertexBindings.clear();
  }

  @override
  void setColorBlendEnable(bool enable, {int colorAttachmentIndex = 0}) {
    final gl = _gpuContext._gl;
    if (enable) {
      gl.enable(web.WebGL2RenderingContext.BLEND);
    } else {
      gl.disable(web.WebGL2RenderingContext.BLEND);
    }
  }

  @override
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

  @override
  void setDepthWriteEnable(bool enable) {
    _gpuContext._gl.depthMask(enable);
  }

  @override
  void setDepthCompareOperation(CompareFunction compareFunction) {
    final gl = _gpuContext._gl;
    // GL skips depth writes while the test is disabled, so `always` keeps
    // the test on with GL_ALWAYS, as Impeller's GLES backend does.
    gl.enable(web.WebGL2RenderingContext.DEPTH_TEST);
    gl.depthFunc(_glCompare(compareFunction));
  }

  StencilConfig _stencilFront = StencilConfig();
  StencilConfig _stencilBack = StencilConfig();
  int _stencilReference = 0;

  @override
  void setStencilReference(int referenceValue) {
    _stencilReference = referenceValue;
    _applyStencil();
  }

  @override
  void setStencilConfig(
    StencilConfig configuration, {
    StencilFace targetFace = StencilFace.both,
  }) {
    if (targetFace != StencilFace.back) _stencilFront = configuration;
    if (targetFace != StencilFace.front) _stencilBack = configuration;
    _applyStencil();
  }

  static bool _stencilInactive(StencilConfig c) =>
      c.compareFunction == CompareFunction.always &&
      c.stencilFailureOperation == StencilOperation.keep &&
      c.depthFailureOperation == StencilOperation.keep &&
      c.depthStencilPassOperation == StencilOperation.keep;

  // GL holds the stencil state globally; the test is only enabled while a
  // config can reject or write, as Impeller's GLES backend does.
  void _applyStencil() {
    final gl = _gpuContext._gl;
    if (_stencilInactive(_stencilFront) && _stencilInactive(_stencilBack)) {
      gl.disable(web.WebGL2RenderingContext.STENCIL_TEST);
      return;
    }
    gl.enable(web.WebGL2RenderingContext.STENCIL_TEST);
    for (final (face, config) in [
      (web.WebGL2RenderingContext.FRONT, _stencilFront),
      (web.WebGL2RenderingContext.BACK, _stencilBack),
    ]) {
      gl.stencilFuncSeparate(
        face,
        _glCompare(config.compareFunction),
        _stencilReference,
        config.readMask & 0xFF,
      );
      gl.stencilOpSeparate(
        face,
        _glStencilOp(config.stencilFailureOperation),
        _glStencilOp(config.depthFailureOperation),
        _glStencilOp(config.depthStencilPassOperation),
      );
      gl.stencilMaskSeparate(face, config.writeMask & 0xFF);
    }
  }

  static int _glStencilOp(StencilOperation op) => switch (op) {
    StencilOperation.keep => web.WebGL2RenderingContext.KEEP,
    StencilOperation.zero => web.WebGL2RenderingContext.ZERO,
    StencilOperation.setToReferenceValue => web.WebGL2RenderingContext.REPLACE,
    StencilOperation.incrementClamp => web.WebGL2RenderingContext.INCR,
    StencilOperation.decrementClamp => web.WebGL2RenderingContext.DECR,
    StencilOperation.invert => web.WebGL2RenderingContext.INVERT,
    StencilOperation.incrementWrap => web.WebGL2RenderingContext.INCR_WRAP,
    StencilOperation.decrementWrap => web.WebGL2RenderingContext.DECR_WRAP,
  };

  @override
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

  @override
  void setPolygonMode(PolygonMode polygonMode) {
    /* not implemented; WebGL2 has no glPolygonMode */
  }

  @override
  void setPrimitiveType(PrimitiveType primitiveType) {
    _primitiveType = primitiveType;
  }

  @override
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

  @override
  void setScissor(Scissor scissor) {
    final gl = _gpuContext._gl;
    gl.enable(web.WebGL2RenderingContext.SCISSOR_TEST);
    gl.scissor(scissor.x, scissor.y, scissor.width, scissor.height);
  }

  @override
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
    bufferView.buffer.webGl._bindForTarget(
      web.WebGL2RenderingContext.ARRAY_BUFFER,
    );
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

  @override
  void draw(int vertexCount, {int instanceCount = 1}) {
    final gl = _gpuContext._gl;
    if (_boundPipeline == null) {
      throw StateError('draw called before bindPipeline');
    }
    if (vertexCount == 0 || instanceCount == 0) return;
    _applyVertexState(needsIndex: false);
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

  @override
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
    _applyVertexState(needsIndex: true);
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
      resolve.webGl.glTexture,
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
