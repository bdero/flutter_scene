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
    queue.onSubmittedWorkDone().toDart.then(
      (_) => completionCallback(CompletionStatus.successful),
      onError: (Object _) => completionCallback(CompletionStatus.error),
    );
  }
}

/// A bound uniform block's buffer range.
typedef _BoundUniform = ({_WebGpuDeviceBuffer buffer, int offset, int length});

/// A bound texture and the options it is sampled with.
typedef _BoundTexture = ({_WebGpuTexture texture, SamplerOptions? sampler});

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
  final Map<int, _BoundUniform> _uniforms = {};
  final Set<int> _explicitUniforms = {};
  final Map<int, _BoundTexture> _textures = {};
  final Set<int> _explicitTextures = {};

  final List<BufferView?> _vertexBuffers = [];
  BufferView? _indexBuffer;
  IndexType _indexType = IndexType.int32;

  // What the encoder already holds, to skip repeated calls.
  GPURenderPipeline? _encodedPipeline;
  GPUBindGroup? _encodedGroup;
  final List<int> _encodedOffsets = [];
  final List<(_WebGpuDeviceBuffer, int)?> _encodedVertex = [];
  (_WebGpuDeviceBuffer, int, IndexType)? _encodedIndex;

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
    final slots = pipeline.vertexLayout?.buffers.length ?? 1;
    if (slot < 0 || slot >= slots) {
      throw RangeError.value(
        slot,
        'slot',
        pipeline.vertexLayout == null
            ? 'Slots other than 0 need an explicit pipeline VertexLayout'
            : 'Pipeline VertexLayout declares $slots buffers',
      );
    }
    while (_vertexBuffers.length <= slot) {
      _vertexBuffers.add(null);
    }
    _vertexBuffers[slot] = bufferView;
  }

  @override
  void bindIndexBuffer(BufferView bufferView, IndexType indexType) {
    _indexBuffer = bufferView;
    _indexType = indexType;
    _state.setStripIndexType(indexType);
  }

  /// The bound pipeline's shader for [stage], then the other one.
  (_WebGpuShader, _WebGpuShader) _stages(_WebGpuRenderPipeline p, Shader s) =>
      s.stage == ShaderStage.vertex
      ? (p.vertexShader, p.fragmentShader)
      : (p.fragmentShader, p.vertexShader);

  @override
  void bindUniform(UniformSlot slot, BufferView bufferView) {
    final pipeline = _bound('bindUniform');
    final name = slot.uniformName;
    final (own, other) = _stages(pipeline, slot.shader);
    final ownBlock = own.uniforms[name];
    final otherBlock = other.uniforms[name];
    if (ownBlock == null &&
        otherBlock == null &&
        (slot.shader as _WebGpuShader).uniforms[name] == null) {
      throw StateError(
        'Failed to bind uniform. This shader declares no uniform block named '
        '"$name". A block binds by its type name, not its instance name, and '
        'a block nothing in the shader reads is optimized out by the compiler '
        'and reflects as absent. $_staleBundleHint',
      );
    }
    final bound = (
      buffer: bufferView.buffer as _WebGpuDeviceBuffer,
      offset: bufferView.offsetInBytes,
      length: bufferView.lengthInBytes,
    );
    if (ownBlock != null) {
      _uniforms[ownBlock.binding] = bound;
      _explicitUniforms.add(ownBlock.binding);
    }
    if (otherBlock != null && !_explicitUniforms.contains(otherBlock.binding)) {
      _uniforms[otherBlock.binding] = bound;
    }
  }

  @override
  void bindTexture(
    UniformSlot slot,
    Texture texture, {
    SamplerOptions? sampler,
  }) {
    final pipeline = _bound('bindTexture');
    final name = slot.uniformName;
    final (own, other) = _stages(pipeline, slot.shader);
    final ownSlot = own.textures.where((t) => t.name == name).firstOrNull;
    final otherSlot = other.textures.where((t) => t.name == name).firstOrNull;
    if (ownSlot == null && otherSlot == null) {
      throw StateError(
        'Failed to bind texture. This shader declares no texture named '
        '"$name". Check the sampler name spelling, and note that a sampler '
        'nothing in the shader reads is optimized out by the compiler and '
        'reflects as absent. $_staleBundleHint',
      );
    }
    final bound = (texture: texture as _WebGpuTexture, sampler: sampler);
    if (ownSlot != null) {
      _textures[ownSlot.binding] = bound;
      _explicitTextures.add(ownSlot.binding);
    }
    if (otherSlot != null && !_explicitTextures.contains(otherSlot.binding)) {
      _textures[otherSlot.binding] = bound;
    }
  }

  @override
  void clearBindings() {
    _uniforms.clear();
    _explicitUniforms.clear();
    _textures.clear();
    _explicitTextures.clear();
    _vertexBuffers.clear();
    _indexBuffer = null;
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
    final index = _indexBuffer;
    if (index == null) {
      throw StateError('drawIndexed called before bindIndexBuffer');
    }
    _prepare(pipeline);
    final buffer = index.buffer as _WebGpuDeviceBuffer;
    final encoded = _encodedIndex;
    if (encoded == null ||
        !identical(encoded.$1, buffer) ||
        encoded.$2 != index.offsetInBytes ||
        encoded.$3 != _indexType) {
      _encoder.setIndexBuffer(
        buffer.buffer,
        _indexType == IndexType.int16 ? 'uint16' : 'uint32',
        index.offsetInBytes,
      );
      _encodedIndex = (buffer, index.offsetInBytes, _indexType);
    }
    _encoder.drawIndexed(indexCount, instanceCount);
  }

  /// Sets the variant, bind group, and vertex buffers a draw needs.
  void _prepare(_WebGpuRenderPipeline pipeline) {
    final sampled = pipeline.sampledTextures;
    final f32 = _context.float32Filterable;
    final slots = <GpuSampleSlot>[
      for (final (shader: _, :slot) in sampled)
        switch (_textures[slot.binding]) {
          final bound? => resolveSampleSlot(
            shape: slot.shape!,
            format: (
              depth: bound.texture._format.depth,
              float32: bound.texture._format.float32,
            ),
            samplerFilters: _filters(bound.sampler),
            float32Filterable: f32,
          ),
          null => _defaultSampleSlot(slot, f32: f32),
        },
    ];
    final variant = pipeline.variantFor(_state, _shape, slots);
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
    final parts = <Object>[];
    final offsets = _context.dynamicOffsets;
    var dynamicCount = 0;
    for (final entry in layout.entries) {
      switch (entry.kind) {
        case _EntryKind.uniform:
          final size = pipeline.uniformSize(entry.binding);
          final bound = _uniforms[entry.binding];
          if (bound == null) {
            final zero = _context.zeroUniformBuffer(size);
            parts
              ..add(zero)
              ..add(size);
            if (entry.dynamic) {
              offsets[dynamicCount++] = 0;
            } else {
              parts.add(0);
            }
            continue;
          }
          final alignment = _context.minimumUniformByteAlignment;
          if (bound.offset % alignment != 0) {
            throw StateError(
              'A uniform buffer range at offset ${bound.offset} is not '
              'aligned to $alignment bytes, which WebGPU requires; emplace '
              'uniforms through a HostBuffer.',
            );
          }
          // Never past the buffer, even where the block is padded beyond
          // what was written.
          final room = bound.buffer.sizeInBytes - bound.offset;
          final bindSize = size <= room ? size : room;
          parts
            ..add(bound.buffer)
            ..add(bindSize);
          if (entry.dynamic) {
            offsets[dynamicCount++] = bound.offset;
          } else {
            parts.add(bound.offset);
          }
        case _EntryKind.texture:
          final bound = _textures[entry.binding];
          parts.add(
            bound?.texture ?? _context.blankTexture(entry.viewDimension!),
          );
        case _EntryKind.sampler:
          final bound =
              _textures[entry.binding - WgslBindingMap.splitSamplerOffset];
          parts.add(
            _SamplerCache.keyOf(
              bound?.sampler ?? _defaultSampler,
              nonFiltering: entry.nonFiltering,
            ),
          );
      }
    }
    final key = _GroupKey(parts);
    var group = layout.groups[key];
    if (group == null) {
      if (layout.groups.length >= 1024) layout.groups.clear();
      group = layout.groups[key] = _createGroup(layout, parts);
    }
    if (identical(group, _encodedGroup) && _sameOffsets(dynamicCount)) return;
    _encoder.setBindGroup(0, group, _context.dynamicOffsetsJs, 0, dynamicCount);
    _encodedGroup = group;
    _encodedOffsets
      ..clear()
      ..addAll(offsets.take(dynamicCount));
  }

  static final SamplerOptions _defaultSampler = SamplerOptions();

  bool _sameOffsets(int count) {
    if (_encodedOffsets.length != count) return false;
    final offsets = _context.dynamicOffsets;
    for (var i = 0; i < count; i++) {
      if (_encodedOffsets[i] != offsets[i]) return false;
    }
    return true;
  }

  /// Builds a group from the [parts] a key was made of, which list each
  /// entry's resources in entry order.
  GPUBindGroup _createGroup(_BindingLayout layout, List<Object> parts) {
    var i = 0;
    final entries = <Map<String, Object?>>[];
    for (final entry in layout.entries) {
      switch (entry.kind) {
        case _EntryKind.uniform:
          final buffer = parts[i++] as _WebGpuDeviceBuffer;
          final size = parts[i++] as int;
          final offset = entry.dynamic ? 0 : parts[i++] as int;
          entries.add({
            'binding': entry.binding,
            'resource': {
              'buffer': buffer.buffer,
              'offset': offset,
              'size': size,
            },
          });
        case _EntryKind.texture:
          entries.add({
            'binding': entry.binding,
            'resource': (parts[i++] as _WebGpuTexture).sampledView,
          });
        case _EntryKind.sampler:
          entries.add({
            'binding': entry.binding,
            'resource': _context.samplers.byKey(parts[i++] as int),
          });
      }
    }
    return _context.device.device.createBindGroup(
      _obj({'layout': layout.layout, 'entries': entries}),
    );
  }

  void _setVertexBuffers(_WebGpuRenderPipeline pipeline) {
    final slots = pipeline.vertexLayout?.buffers.length ?? 1;
    while (_encodedVertex.length < slots) {
      _encodedVertex.add(null);
    }
    for (var slot = 0; slot < slots; slot++) {
      final view = slot < _vertexBuffers.length ? _vertexBuffers[slot] : null;
      if (view == null) {
        throw StateError(
          'Draw with "${pipeline.vertexShader.name}" has no vertex buffer '
          'bound to slot $slot.',
        );
      }
      final buffer = view.buffer as _WebGpuDeviceBuffer;
      final encoded = _encodedVertex[slot];
      if (encoded != null &&
          identical(encoded.$1, buffer) &&
          encoded.$2 == view.offsetInBytes) {
        continue;
      }
      _encoder.setVertexBuffer(slot, buffer.buffer, view.offsetInBytes);
      _encodedVertex[slot] = (buffer, view.offsetInBytes);
    }
  }
}

/// Appended to a missing-binding error, since a bundle from an earlier build
/// reflects the same way as a name the shader never declared.
const String _staleBundleHint =
    'If the app was just rebuilt, a cache in front of the server (a service '
    'worker, a CDN) may be serving a shader bundle from the previous build.';
