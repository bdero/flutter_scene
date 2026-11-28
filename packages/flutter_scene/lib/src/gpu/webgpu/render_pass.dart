part of 'webgpu_backend.dart';

/// Records passes into one `GPUCommandEncoder` and submits them together.
/// Starting a pass ends the previous one, as on WebGL2.
final class _WebGpuCommandBuffer extends CommandBuffer {
  _WebGpuCommandBuffer(this._context)
    : _encoder = _context.device.device.createCommandEncoder();

  final _WebGpuContext _context;
  final GPUCommandEncoder _encoder;
  _WebGpuRenderPass? _active;
  bool _submitted = false;

  @override
  RenderPass createRenderPass(RenderTarget renderTarget) {
    if (_submitted) {
      throw StateError('This command buffer was already submitted.');
    }
    _active?._end();
    return _active = _WebGpuRenderPass(_context, _encoder, renderTarget);
  }

  @override
  void submit({CompletionCallback? completionCallback}) {
    if (_submitted) {
      throw StateError('This command buffer was already submitted.');
    }
    _submitted = true;
    _active?._end();
    _active = null;
    final queue = _context.device.device.queue;
    queue.submit([_encoder.finish()].toJS);
    if (completionCallback == null) return;
    _context.enqueueSubmissionCallback(completionCallback);
  }
}

final class _WebGpuRenderPass extends RenderPass {
  _WebGpuRenderPass(this._context, GPUCommandEncoder encoder, this._target) {
    final colors = _target.colorAttachments;
    if (colors.isEmpty) {
      throw Exception('RenderTarget must have at least one color attachment');
    }
    final first = colors.first;
    final firstTexture = first.texture as _WebGpuTexture;
    _width = _mipExtent(firstTexture.width, first.mipLevel);
    _height = _mipExtent(firstTexture.height, first.mipLevel);
    final depth = _target.depthStencilAttachment;
    final depthTexture = depth?.texture as _WebGpuTexture?;
    _shape = _TargetShape.of(
      [for (final c in colors) (c.texture as _WebGpuTexture)._format],
      depthTexture?._format,
      firstTexture.sampleCount,
    );
    _encoder = encoder.beginRenderPass(
      _obj({
        'colorAttachments': [for (final c in colors) _colorAttachment(c)],
        if (depth != null && depthTexture != null)
          'depthStencilAttachment': _depthAttachment(depth, depthTexture),
      }),
    );
  }

  final _WebGpuContext _context;
  final RenderTarget _target;
  late final GPURenderPassEncoder _encoder;
  late final _TargetShape _shape;
  late final int _width;
  late final int _height;
  final _RenderState _state = _RenderState();
  bool _ended = false;

  _WebGpuRenderPipeline? _pipeline;

  /// Bound resources by binding number. A bind also fills the other stage's
  /// same-named binding unless that was bound itself, since WebGL2 binds by
  /// name across both stages and the renderer is written against that.
  final PassBindingTable<_WebGpuDeviceBuffer, _WebGpuTexture, SamplerOptions>
  _bindings = PassBindingTable();

  _WebGpuDeviceBuffer? _indexBuffer;
  int _indexOffset = 0;
  bool _hasIndexBuffer = false;
  IndexType _indexType = IndexType.int32;

  // What the encoder already holds, to skip repeated calls.
  GPURenderPipeline? _encodedPipeline;
  GPUBindGroup? _encodedGroup;
  final Uint32List _encodedOffsets = Uint32List(64);
  int _encodedOffsetCount = -1;
  final List<_WebGpuDeviceBuffer?> _encodedVertexBuffers = List.filled(
    8,
    null,
    growable: true,
  );
  final List<int> _encodedVertexOffsets = List.filled(8, -1, growable: true);
  _WebGpuDeviceBuffer? _encodedIndexBuffer;
  int _encodedIndexOffset = -1;
  IndexType _encodedIndexType = IndexType.int32;

  static int _mipExtent(int base, int mipLevel) {
    final size = base >> mipLevel;
    return size < 1 ? 1 : size;
  }

  Map<String, Object?> _colorAttachment(ColorAttachment c) {
    final texture = c.texture as _WebGpuTexture;
    final resolve = c.resolveTexture as _WebGpuTexture?;
    final resolves =
        texture.sampleCount > 1 &&
        resolve != null &&
        (c.storeAction == StoreAction.multisampleResolve ||
            c.storeAction == StoreAction.storeAndMultisampleResolve);
    return {
      'view': texture.attachmentView(c.mipLevel, c.slice),
      if (resolves) 'resolveTarget': resolve.attachmentView(0, 0),
      'loadOp': _loadOp(c.loadAction),
      'storeOp':
          c.storeAction == StoreAction.store ||
              c.storeAction == StoreAction.storeAndMultisampleResolve
          ? 'store'
          : 'discard',
      'clearValue': [
        c.clearValue.x,
        c.clearValue.y,
        c.clearValue.z,
        c.clearValue.w,
      ],
    };
  }

  Map<String, Object?> _depthAttachment(
    DepthStencilAttachment d,
    _WebGpuTexture texture,
  ) => {
    'view': texture.attachmentView(d.mipLevel, d.slice),
    if (texture._format.depth) ...{
      'depthLoadOp': _loadOp(d.depthLoadAction),
      'depthStoreOp': _storeOp(d.depthStoreAction),
      'depthClearValue': d.depthClearValue.clamp(0.0, 1.0),
    },
    if (texture._format.stencil) ...{
      'stencilLoadOp': _loadOp(d.stencilLoadAction),
      'stencilStoreOp': _storeOp(d.stencilStoreAction),
      'stencilClearValue': d.stencilClearValue,
    },
  };

  /// WebGPU has no "don't care" load; clearing is the cheapest defined one.
  static String _loadOp(LoadAction action) =>
      action == LoadAction.load ? 'load' : 'clear';

  static String _storeOp(StoreAction action) =>
      action == StoreAction.store ||
          action == StoreAction.storeAndMultisampleResolve
      ? 'store'
      : 'discard';

  void _end() {
    if (_ended) return;
    _ended = true;
    _encoder.end();
  }

  void _checkOpen() {
    if (_ended) {
      throw StateError(
        'This render pass has ended; a command buffer ends a pass when it '
        'starts the next one or is submitted.',
      );
    }
  }

  // ---- binding -------------------------------------------------------------

  @override
  void bindPipeline(RenderPipeline pipeline) {
    _checkOpen();
    _pipeline = pipeline as _WebGpuRenderPipeline;
  }

  _WebGpuRenderPipeline _bound(String call) =>
      _pipeline ?? (throw StateError('$call called before bindPipeline'));

  @override
  void bindVertexBuffer(BufferView bufferView, {int slot = 0}) {
    final pipeline = _bound('bindVertexBuffer');
    final slots = pipeline.vertexSlotCount;
    if (slot < 0 || slot >= slots) {
      throw RangeError.value(
        slot,
        'slot',
        pipeline.vertexLayout == null
            ? 'Slots other than 0 need an explicit pipeline VertexLayout'
            : 'Pipeline VertexLayout declares $slots buffers',
      );
    }
    _bindings.bindVertexBuffer(
      slot,
      bufferView.buffer as _WebGpuDeviceBuffer,
      bufferView.offsetInBytes,
    );
  }

  @override
  void bindIndexBuffer(BufferView bufferView, IndexType indexType) {
    _indexBuffer = bufferView.buffer as _WebGpuDeviceBuffer;
    _indexOffset = bufferView.offsetInBytes;
    _hasIndexBuffer = true;
    _indexType = indexType;
    _state.setStripIndexType(indexType);
  }

  @override
  void bindUniform(UniformSlot slot, BufferView bufferView) {
    final pipeline = _bound('bindUniform');
    final s = slot as _WebGpuUniformSlot;
    final isVertex = s.shader.stage == ShaderStage.vertex;
    final own = isVertex ? pipeline.vertexShader : pipeline.fragmentShader;
    final other = isVertex ? pipeline.fragmentShader : pipeline.vertexShader;
    final ownBlock = s._uniformIn(own);
    final otherBlock = s._uniformIn(other);
    if (ownBlock == null &&
        otherBlock == null &&
        s._uniformIn(s.shader) == null) {
      throw StateError(
        'Failed to bind uniform. This shader declares no uniform block named '
        '"${s.uniformName}". A block binds by its type name, not its instance '
        'name, and a block nothing in the shader reads is optimized out by the '
        'compiler and reflects as absent. $_staleBundleHint',
      );
    }
    final buffer = bufferView.buffer as _WebGpuDeviceBuffer;
    final offset = bufferView.offsetInBytes;
    final length = bufferView.lengthInBytes;
    if (ownBlock != null) {
      _bindings.bindUniform(
        ownBlock.binding,
        buffer,
        offset,
        length,
        explicit: true,
      );
    }
    if (otherBlock != null) {
      _bindings.bindUniform(
        otherBlock.binding,
        buffer,
        offset,
        length,
        explicit: false,
      );
    }
  }

  @override
  void bindTexture(
    UniformSlot slot,
    Texture texture, {
    SamplerOptions? sampler,
  }) {
    final pipeline = _bound('bindTexture');
    final s = slot as _WebGpuUniformSlot;
    final isVertex = s.shader.stage == ShaderStage.vertex;
    final own = isVertex ? pipeline.vertexShader : pipeline.fragmentShader;
    final other = isVertex ? pipeline.fragmentShader : pipeline.vertexShader;
    final ownSlot = s._textureIn(own);
    final otherSlot = s._textureIn(other);
    if (ownSlot == null && otherSlot == null) {
      throw StateError(
        'Failed to bind texture. This shader declares no texture named '
        '"${s.uniformName}". Check the sampler name spelling, and note that a '
        'sampler nothing in the shader reads is optimized out by the compiler '
        'and reflects as absent. $_staleBundleHint',
      );
    }
    final tex = texture as _WebGpuTexture;
    if (ownSlot != null) {
      _bindings.bindTexture(ownSlot.binding, tex, sampler, explicit: true);
    }
    if (otherSlot != null) {
      _bindings.bindTexture(otherSlot.binding, tex, sampler, explicit: false);
    }
  }

  @override
  void clearBindings() {
    _bindings.clear();
    _hasIndexBuffer = false;
  }

  // ---- fixed-function state --------------------------------------------------

  @override
  void setColorBlendEnable(bool enable, {int colorAttachmentIndex = 0}) =>
      _state.setColorBlendEnable(enable, colorAttachmentIndex);

  @override
  void setColorBlendEquation(
    ColorBlendEquation equation, {
    int colorAttachmentIndex = 0,
  }) => _state.setColorBlendEquation(equation, colorAttachmentIndex);

  @override
  void setDepthWriteEnable(bool enable) => _state.setDepthWriteEnable(enable);

  @override
  void setDepthCompareOperation(CompareFunction compareFunction) =>
      _state.setDepthCompare(compareFunction);

  @override
  void setStencilReference(int referenceValue) {
    _checkOpen();
    _encoder.setStencilReference(referenceValue);
  }

  @override
  void setStencilConfig(
    StencilConfig configuration, {
    StencilFace targetFace = StencilFace.both,
  }) => _state.setStencilConfig(configuration, targetFace);

  @override
  void setCullMode(CullMode cullMode) => _state.setCullMode(cullMode);

  // TODO(webgpu-polygon-mode): WebGPU has no line fill mode; draw the
  // triangles' edges as a line list to support PolygonMode.line. WebGL2
  // ignores it the same way.
  @override
  void setPolygonMode(PolygonMode polygonMode) {}

  @override
  void setPrimitiveType(PrimitiveType primitiveType) =>
      _state.setPrimitiveType(primitiveType);

  @override
  void setWindingOrder(WindingOrder windingOrder) =>
      _state.setWindingOrder(windingOrder);

  @override
  void setScissor(Scissor scissor) {
    _checkOpen();
    // WebGPU rejects a rect past the attachment; GL clips it.
    final x0 = scissor.x.clamp(0, _width);
    final y0 = scissor.y.clamp(0, _height);
    final x1 = (scissor.x + scissor.width).clamp(x0, _width);
    final y1 = (scissor.y + scissor.height).clamp(y0, _height);
    _encoder.setScissorRect(x0, y0, x1 - x0, y1 - y0);
  }

  @override
  void setViewport(Viewport viewport) {
    _checkOpen();
    final near = viewport.depthRange.zNear.clamp(0.0, 1.0);
    final far = viewport.depthRange.zFar.clamp(0.0, 1.0);
    // TODO(webgpu-reversed-depth-range): WebGPU needs minDepth <= maxDepth;
    // a reversed range would need the shader's depth flipped instead.
    _encoder.setViewport(
      viewport.x.toDouble(),
      viewport.y.toDouble(),
      viewport.width.toDouble(),
      viewport.height.toDouble(),
      near < far ? near : far,
      near < far ? far : near,
    );
  }

  // ---- drawing ---------------------------------------------------------------

  @override
  void draw(int vertexCount, {int instanceCount = 1}) {
    _checkOpen();
    final pipeline = _bound('draw');
    if (vertexCount == 0 || instanceCount == 0) return;
    _prepare(pipeline);
    _encoder.draw(vertexCount, instanceCount);
  }

  @override
  void drawIndexed(int indexCount, {int instanceCount = 1}) {
    _checkOpen();
    final pipeline = _bound('drawIndexed');
    if (indexCount == 0 || instanceCount == 0) return;
    final buffer = _indexBuffer;
    if (!_hasIndexBuffer || buffer == null) {
      throw StateError('drawIndexed called before bindIndexBuffer');
    }
    _prepare(pipeline);
    if (!identical(_encodedIndexBuffer, buffer) ||
        _encodedIndexOffset != _indexOffset ||
        _encodedIndexType != _indexType) {
      _encoder.setIndexBuffer(
        buffer.buffer,
        _indexType == IndexType.int16 ? 'uint16' : 'uint32',
        _indexOffset,
      );
      _encodedIndexBuffer = buffer;
      _encodedIndexOffset = _indexOffset;
      _encodedIndexType = _indexType;
    }
    _encoder.drawIndexed(indexCount, instanceCount);
  }

  /// Sets the variant, bind group, and vertex buffers a draw needs.
  void _prepare(_WebGpuRenderPipeline pipeline) {
    final sampled = pipeline.sampledTextures;
    final f32 = _context.float32Filterable;
    final samples = _context.sampleLanesScratch..reset();
    for (var i = 0; i < sampled.length; i++) {
      final entry = sampled[i];
      if (!_bindings.hasTexture(entry.binding)) {
        samples.add(entry.defaultCode);
        continue;
      }
      final format = _bindings.texture(entry.binding)._format;
      samples.add(
        resolveSampleSlotCode(
          shape: entry.slot.shape!,
          formatDepth: format.depth,
          formatFloat32: format.float32,
          samplerFilters: _filters(_bindings.sampler(entry.binding)),
          float32Filterable: f32,
        ),
      );
    }

    final variant = pipeline.variantForLanes(_state, _shape, samples);
    if (!identical(variant.pipeline, _encodedPipeline)) {
      _encoder.setPipeline(variant.pipeline);
      _encodedPipeline = variant.pipeline;
    }
    _setBindGroup(pipeline, variant.bindings);
    _setVertexBuffers(pipeline);
  }

  static bool _filters(SamplerOptions? options) =>
      options != null &&
      (options.minFilter == MinMagFilter.linear ||
          options.magFilter == MinMagFilter.linear ||
          options.mipFilter == MipFilter.linear);

  void _setBindGroup(_WebGpuRenderPipeline pipeline, _BindingLayout layout) {
    var keyScratch = _context.groupKeyScratch;
    if (keyScratch.length < layout.keyLength) {
      keyScratch = _context.growGroupKeyScratch(layout.keyLength);
    }
    var keyIndex = 0;
    final offsets = _context.dynamicOffsets;
    var dynamicCount = 0;
    final entries = layout.entries;
    final alignmentMask = _context._uniformAlignmentMask;
    for (var i = 0; i < entries.length; i++) {
      final entry = entries[i];
      switch (entry.kind) {
        case _EntryKind.uniform:
          final size = pipeline.uniformSize(entry.binding);
          if (!_bindings.hasUniform(entry.binding)) {
            final zero = _context.zeroUniformBuffer(size);
            keyScratch[keyIndex++] = zero._id;
            keyScratch[keyIndex++] = size;
            if (entry.dynamic) {
              offsets[dynamicCount++] = 0;
            } else {
              keyScratch[keyIndex++] = 0;
            }
            continue;
          }
          final buffer = _bindings.uniformBuffer(entry.binding);
          final offset = _bindings.uniformOffset(entry.binding);
          if ((offset & alignmentMask) != 0) {
            throw StateError(
              'A uniform buffer range at offset $offset is not '
              'aligned to ${_context.minimumUniformByteAlignment} bytes, '
              'which WebGPU requires; emplace uniforms through a HostBuffer.',
            );
          }
          // Never past the buffer, even where the block is padded beyond
          // what was written.
          final room = buffer.sizeInBytes - offset;
          final bindSize = size <= room ? size : room;
          keyScratch[keyIndex++] = buffer._id;
          keyScratch[keyIndex++] = bindSize;
          if (entry.dynamic) {
            offsets[dynamicCount++] = offset;
          } else {
            keyScratch[keyIndex++] = offset;
          }
        case _EntryKind.texture:
          keyScratch[keyIndex++] = _textureOrBlank(entry)._id;
        case _EntryKind.sampler:
          keyScratch[keyIndex++] = _samplerKey(entry);
      }
    }
    final group =
        layout.groups.lookup(keyScratch, keyIndex) ??
        layout.groups.put(keyScratch, keyIndex, _createGroup(pipeline, layout));
    if (identical(group, _encodedGroup) && _sameOffsets(dynamicCount)) return;
    _encoder.setBindGroup(0, group, _context.dynamicOffsetsJs, 0, dynamicCount);
    _encodedGroup = group;
    _encodedOffsetCount = dynamicCount;
    for (var i = 0; i < dynamicCount; i++) {
      _encodedOffsets[i] = offsets[i];
    }
  }

  static final SamplerOptions _defaultSampler = SamplerOptions();

  _WebGpuTexture _textureOrBlank(_LayoutEntry entry) =>
      _bindings.hasTexture(entry.binding)
      ? _bindings.texture(entry.binding)
      : _context.blankTexture(entry.viewDimension!);

  int _samplerKey(_LayoutEntry entry) {
    final texBinding = entry.binding - WgslBindingMap.splitSamplerOffset;
    final sampler = _bindings.hasTexture(texBinding)
        ? (_bindings.sampler(texBinding) ?? _defaultSampler)
        : _defaultSampler;
    return _SamplerCache.keyOf(sampler, nonFiltering: entry.nonFiltering);
  }

  bool _sameOffsets(int count) {
    if (_encodedOffsetCount != count) return false;
    final offsets = _context.dynamicOffsets;
    for (var i = 0; i < count; i++) {
      if (_encodedOffsets[i] != offsets[i]) return false;
    }
    return true;
  }

  /// Builds a bind group directly from the currently bound resources on a
  /// cache miss.
  GPUBindGroup _createGroup(
    _WebGpuRenderPipeline pipeline,
    _BindingLayout layout,
  ) {
    final entries = <Map<String, Object?>>[];
    for (final entry in layout.entries) {
      switch (entry.kind) {
        case _EntryKind.uniform:
          final size = pipeline.uniformSize(entry.binding);
          final _WebGpuDeviceBuffer buffer;
          final int bindSize;
          final int offset;
          if (!_bindings.hasUniform(entry.binding)) {
            buffer = _context.zeroUniformBuffer(size);
            bindSize = size;
            offset = 0;
          } else {
            buffer = _bindings.uniformBuffer(entry.binding);
            final boundOffset = _bindings.uniformOffset(entry.binding);
            final room = buffer.sizeInBytes - boundOffset;
            bindSize = size <= room ? size : room;
            offset = entry.dynamic ? 0 : boundOffset;
          }
          entries.add({
            'binding': entry.binding,
            'resource': {
              'buffer': buffer.buffer,
              'offset': offset,
              'size': bindSize,
            },
          });
        case _EntryKind.texture:
          entries.add({
            'binding': entry.binding,
            'resource': _textureOrBlank(entry).sampledView,
          });
        case _EntryKind.sampler:
          entries.add({
            'binding': entry.binding,
            'resource': _context.samplers.byKey(_samplerKey(entry)),
          });
      }
    }
    return _context.device.device.createBindGroup(
      _obj({'layout': layout.layout, 'entries': entries}),
    );
  }

  void _setVertexBuffers(_WebGpuRenderPipeline pipeline) {
    final slots = pipeline.vertexSlotCount;
    while (_encodedVertexBuffers.length < slots) {
      _encodedVertexBuffers.add(null);
      _encodedVertexOffsets.add(-1);
    }
    for (var slot = 0; slot < slots; slot++) {
      if (!_bindings.hasVertexBuffer(slot)) {
        throw StateError(
          'Draw with "${pipeline.vertexShader.name}" has no vertex buffer '
          'bound to slot $slot.',
        );
      }
      final buffer = _bindings.vertexBuffer(slot);
      final offset = _bindings.vertexOffset(slot);
      if (identical(_encodedVertexBuffers[slot], buffer) &&
          _encodedVertexOffsets[slot] == offset) {
        continue;
      }
      _encoder.setVertexBuffer(slot, buffer.buffer, offset);
      _encodedVertexBuffers[slot] = buffer;
      _encodedVertexOffsets[slot] = offset;
    }
  }
}

/// Appended to a missing-binding error, since a bundle from an earlier build
/// reflects the same way as a name the shader never declared.
const String _staleBundleHint =
    'If the app was just rebuilt, a cache in front of the server (a service '
    'worker, a CDN) may be serving a shader bundle from the previous build.';
