part of 'webgpu_backend.dart';

// WebGPU bakes into a pipeline what Flutter GPU sets per draw (blend, depth,
// stencil, cull, winding, topology), plus the attachment formats and each
// texture's sample type. So a shim RenderPipeline is a shader pair and a
// vertex layout, and its GPURenderPipelines are variants built the first time
// a draw needs each combination.

/// The attachments a pass renders into, interned so a variant key carries one
/// int for them.
final class _TargetShape {
  _TargetShape._(this.id, this.colorFormats, this.depthStencil, this.samples);

  final int id;
  final List<_GpuFormat> colorFormats;
  final _GpuFormat? depthStencil;
  final int samples;

  static final Map<String, _TargetShape> _interned = {};

  static _TargetShape of(
    List<_GpuFormat> colorFormats,
    _GpuFormat? depthStencil,
    int samples,
  ) {
    final key =
        '${colorFormats.map((f) => f.name).join(',')}'
        '|${depthStencil?.name}|$samples';
    return _interned[key] ??= _TargetShape._(
      _interned.length,
      List.unmodifiable(colorFormats),
      depthStencil,
      samples,
    );
  }
}

/// The fixed-function state a render pass accumulates through its setters,
/// packed into 32-bit lanes so a variant lookup hashes a few ints. A new
/// state is Impeller's at the start of a pass.
final class _RenderState {
  static const int _cull = 0; // 2 bits
  static const int _winding = 2; // 1
  static const int _topology = 3; // 3
  static const int _stripUint32 = 6; // 1
  static const int _depthWrite = 7; // 1
  static const int _depthCompare = 8; // 3

  static const int _faceBits = 12;
  static const int _defaultFace = 1; // compare always, every op keep

  int raster = CompareFunction.always.index << _depthCompare;
  int stencil = _defaultFace | _defaultFace << _faceBits;
  int stencilMasks = 0xffff;

  /// Per color attachment, bit 0 enables and the rest hold the equation.
  final List<int> blends = [_blendBits(ColorBlendEquation())];

  static int _put(int lane, int shift, int bits, int value) {
    final mask = ((1 << bits) - 1) << shift;
    return (lane & ~mask) | (value << shift);
  }

  static int _get(int lane, int shift, int bits) =>
      (lane >> shift) & ((1 << bits) - 1);

  void setCullMode(CullMode mode) =>
      raster = _put(raster, _cull, 2, mode.index);

  void setWindingOrder(WindingOrder order) =>
      raster = _put(raster, _winding, 1, order.index);

  void setPrimitiveType(PrimitiveType type) =>
      raster = _put(raster, _topology, 3, type.index);

  /// The index format a strip draw restarts on, which WebGPU bakes into a
  /// strip pipeline.
  void setStripIndexType(IndexType type) =>
      raster = _put(raster, _stripUint32, 1, type == IndexType.int32 ? 1 : 0);

  void setDepthWriteEnable(bool enable) =>
      raster = _put(raster, _depthWrite, 1, enable ? 1 : 0);

  void setDepthCompare(CompareFunction function) =>
      raster = _put(raster, _depthCompare, 3, function.index);

  void setStencilConfig(StencilConfig config, StencilFace face) {
    final bits =
        config.compareFunction.index |
        config.stencilFailureOperation.index << 3 |
        config.depthFailureOperation.index << 6 |
        config.depthStencilPassOperation.index << 9;
    if (face != StencilFace.back) stencil = _put(stencil, 0, _faceBits, bits);
    if (face != StencilFace.front) {
      stencil = _put(stencil, _faceBits, _faceBits, bits);
    }
    // WebGPU has one pair of masks for both faces, and 8-bit stencil.
    stencilMasks = (config.readMask & 0xff) | (config.writeMask & 0xff) << 8;
  }

  void setColorBlendEnable(bool enable, int attachment) {
    _growBlends(attachment);
    blends[attachment] = _put(blends[attachment], 0, 1, enable ? 1 : 0);
  }

  void setColorBlendEquation(ColorBlendEquation equation, int attachment) {
    _growBlends(attachment);
    blends[attachment] = (blends[attachment] & 1) | _blendBits(equation);
  }

  void _growBlends(int attachment) {
    while (blends.length <= attachment) {
      blends.add(_blendBits(ColorBlendEquation()));
    }
  }

  static int _blendBits(ColorBlendEquation e) =>
      e.colorBlendOperation.index << 1 |
      e.sourceColorBlendFactor.index << 3 |
      e.destinationColorBlendFactor.index << 7 |
      e.alphaBlendOperation.index << 11 |
      e.sourceAlphaBlendFactor.index << 13 |
      e.destinationAlphaBlendFactor.index << 17;
}

/// Everything a variant depends on beyond its pipeline's shaders and vertex
/// layout, normalized so states that build the same GPURenderPipeline share a
/// key.
final class _VariantKey {
  _VariantKey._(
    this.target,
    this.raster,
    this.stencil,
    this.stencilMasks,
    this.blends,
    this.samples,
  ) : hashCode = Object.hash(
        target.id,
        raster,
        stencil,
        stencilMasks,
        Object.hashAll(blends),
        samples,
      );

  factory _VariantKey(
    _RenderState state,
    _TargetShape target,
    GpuSampleSignature samples, {
    required bool float32Blendable,
  }) {
    var raster = state.raster;
    final topology = PrimitiveType
        .values[_RenderState._get(raster, _RenderState._topology, 3)];
    if (topology != PrimitiveType.triangleStrip &&
        topology != PrimitiveType.lineStrip) {
      raster = _RenderState._put(raster, _RenderState._stripUint32, 1, 0);
    }
    var stencil = state.stencil;
    var masks = state.stencilMasks;
    final attachment = target.depthStencil;
    if (attachment == null || !attachment.depth) {
      raster = _RenderState._put(raster, _RenderState._depthWrite, 1, 0);
      raster = _RenderState._put(
        raster,
        _RenderState._depthCompare,
        3,
        CompareFunction.always.index,
      );
    }
    if (attachment == null || !attachment.stencil) {
      stencil = 0;
      masks = 0;
    }
    final blends = [
      for (var i = 0; i < target.colorFormats.length; i++)
        switch (i < state.blends.length ? state.blends[i] : 0) {
          final b when b & 1 == 0 => 0,
          // WebGPU rejects blending into a 32-bit float target without the
          // feature; Metal blends there. Draw unblended rather than nothing.
          _ when target.colorFormats[i].float32 && !float32Blendable => 0,
          final b => b,
        },
    ];
    return _VariantKey._(target, raster, stencil, masks, blends, samples);
  }

  final _TargetShape target;
  final int raster;
  final int stencil;
  final int stencilMasks;
  final List<int> blends;
  final GpuSampleSignature samples;

  @override
  final int hashCode;

  @override
  bool operator ==(Object other) {
    if (other is! _VariantKey ||
        other.hashCode != hashCode ||
        !identical(other.target, target) ||
        other.raster != raster ||
        other.stencil != stencil ||
        other.stencilMasks != stencilMasks ||
        other.blends.length != blends.length ||
        other.samples != samples) {
      return false;
    }
    for (var i = 0; i < blends.length; i++) {
      if (other.blends[i] != blends[i]) return false;
    }
    return true;
  }

  Map<String, Object?> get primitive {
    final topology = PrimitiveType
        .values[_RenderState._get(raster, _RenderState._topology, 3)];
    final strip =
        topology == PrimitiveType.triangleStrip ||
        topology == PrimitiveType.lineStrip;
    return {
      'topology': switch (topology) {
        PrimitiveType.triangle => 'triangle-list',
        PrimitiveType.triangleStrip => 'triangle-strip',
        PrimitiveType.line => 'line-list',
        PrimitiveType.lineStrip => 'line-strip',
        PrimitiveType.point => 'point-list',
      },
      if (strip)
        'stripIndexFormat':
            _RenderState._get(raster, _RenderState._stripUint32, 1) == 1
            ? 'uint32'
            : 'uint16',
      // The bundle's SPIR-V renders with Vulkan's flipped viewport, which is
      // WebGPU's convention, so winding maps straight across.
      'frontFace': _RenderState._get(raster, _RenderState._winding, 1) == 0
          ? 'cw'
          : 'ccw',
      'cullMode': switch (CullMode.values[_RenderState._get(
        raster,
        _RenderState._cull,
        2,
      )]) {
        CullMode.none => 'none',
        CullMode.frontFace => 'front',
        CullMode.backFace => 'back',
      },
    };
  }

  Map<String, Object?>? get depthStencil {
    final attachment = target.depthStencil;
    if (attachment == null) return null;
    Map<String, Object?> face(int bits) => {
      'compare': _compare(CompareFunction.values[bits & 7]),
      'failOp': _stencilOp(StencilOperation.values[(bits >> 3) & 7]),
      'depthFailOp': _stencilOp(StencilOperation.values[(bits >> 6) & 7]),
      'passOp': _stencilOp(StencilOperation.values[(bits >> 9) & 7]),
    };
    return {
      'format': attachment.name,
      'depthWriteEnabled':
          _RenderState._get(raster, _RenderState._depthWrite, 1) == 1,
      'depthCompare': _compare(
        CompareFunction.values[_RenderState._get(
          raster,
          _RenderState._depthCompare,
          3,
        )],
      ),
      if (attachment.stencil) ...{
        'stencilFront': face(stencil & 0xfff),
        'stencilBack': face(stencil >> _RenderState._faceBits),
        'stencilReadMask': stencilMasks & 0xff,
        'stencilWriteMask': stencilMasks >> 8,
      },
    };
  }

  List<Map<String, Object?>> get colorTargets => [
    for (var i = 0; i < target.colorFormats.length; i++)
      {
        'format': target.colorFormats[i].name,
        if (blends[i] != 0) 'blend': _blend(blends[i]),
      },
  ];

  static Map<String, Object?> _blend(int bits) {
    String factor(int shift) =>
        _blendFactor(BlendFactor.values[(bits >> shift) & 0xf]);
    String operation(int shift) =>
        switch (BlendOperation.values[(bits >> shift) & 3]) {
          BlendOperation.add => 'add',
          BlendOperation.subtract => 'subtract',
          BlendOperation.reverseSubtract => 'reverse-subtract',
        };
    return {
      'color': {
        'operation': operation(1),
        'srcFactor': factor(3),
        'dstFactor': factor(7),
      },
      'alpha': {
        'operation': operation(11),
        'srcFactor': factor(13),
        'dstFactor': factor(17),
      },
    };
  }
}

String _compare(CompareFunction function) => switch (function) {
  CompareFunction.never => 'never',
  CompareFunction.always => 'always',
  CompareFunction.less => 'less',
  CompareFunction.equal => 'equal',
  CompareFunction.lessEqual => 'less-equal',
  CompareFunction.greater => 'greater',
  CompareFunction.notEqual => 'not-equal',
  CompareFunction.greaterEqual => 'greater-equal',
};

String _stencilOp(StencilOperation operation) => switch (operation) {
  StencilOperation.keep => 'keep',
  StencilOperation.zero => 'zero',
  StencilOperation.setToReferenceValue => 'replace',
  StencilOperation.incrementClamp => 'increment-clamp',
  StencilOperation.decrementClamp => 'decrement-clamp',
  StencilOperation.invert => 'invert',
  StencilOperation.incrementWrap => 'increment-wrap',
  StencilOperation.decrementWrap => 'decrement-wrap',
};

String _blendFactor(BlendFactor factor) => switch (factor) {
  BlendFactor.zero => 'zero',
  BlendFactor.one => 'one',
  BlendFactor.sourceColor => 'src',
  BlendFactor.oneMinusSourceColor => 'one-minus-src',
  BlendFactor.sourceAlpha => 'src-alpha',
  BlendFactor.oneMinusSourceAlpha => 'one-minus-src-alpha',
  BlendFactor.destinationColor => 'dst',
  BlendFactor.oneMinusDestinationColor => 'one-minus-dst',
  BlendFactor.destinationAlpha => 'dst-alpha',
  BlendFactor.oneMinusDestinationAlpha => 'one-minus-dst-alpha',
  BlendFactor.sourceAlphaSaturated => 'src-alpha-saturated',
  BlendFactor.blendColor => 'constant',
  BlendFactor.oneMinusBlendColor => 'one-minus-constant',
  // TODO(webgpu-blend-alpha-factor): WebGPU's constant factor uses all four
  // channels of the blend constant, so a color factor reading only its alpha
  // is exact only when the pass sets an opaque-gray constant. Splat the
  // alpha into the constant when a pipeline uses these.
  BlendFactor.blendAlpha => 'constant',
  BlendFactor.oneMinusBlendAlpha => 'one-minus-constant',
};

/// A realized bind group layout, and what a pass needs to fill a group for it.
final class _BindingLayout {
  _BindingLayout(this.key, this.layout, this.pipelineLayout, this.dynamic);

  /// The canonical descriptor text it was deduplicated by.
  final String key;
  final GPUBindGroupLayout layout;
  final GPUPipelineLayout pipelineLayout;

  /// Uniform bindings addressed by dynamic offset, ascending, which is the
  /// order `setBindGroup` takes their offsets in. Others bind at a fixed
  /// offset, so their bind group changes with the buffer range.
  final List<int> dynamic;
}

/// One GPURenderPipeline of a [_WebGpuRenderPipeline].
final class _PipelineVariant {
  _PipelineVariant(this.pipeline, this.bindings, this.validation);

  final GPURenderPipeline pipeline;
  final _BindingLayout bindings;

  /// The validation error building it raised, or null; checked in debug
  /// builds only, where a failure is also printed.
  final Future<String?>? validation;
}

/// A texture a pipeline samples, in the order its sample signature lists it.
typedef _SampledTexture = ({_WebGpuShader shader, _TextureSlot slot});

final class _WebGpuRenderPipeline extends RenderPipeline {
  _WebGpuRenderPipeline(
    this._context,
    this.vertexShader,
    this.fragmentShader,
    this.vertexLayout,
  ) {
    if (vertexShader.stage != ShaderStage.vertex ||
        fragmentShader.stage != ShaderStage.fragment) {
      throw Exception(
        'A render pipeline needs a vertex shader then a fragment shader, not '
        '"${vertexShader.name}" (${vertexShader.stage.name}) and '
        '"${fragmentShader.name}" (${fragmentShader.stage.name}).',
      );
    }
    _refresh();
  }

  final _WebGpuContext _context;

  @override
  final _WebGpuShader vertexShader;

  @override
  final _WebGpuShader fragmentShader;

  /// The explicit layout, or null for the shader's reflected inputs in one
  /// interleaved buffer.
  final VertexLayout? vertexLayout;

  final Map<_VariantKey, _PipelineVariant> _variants = {};
  int _vertexGeneration = -1;
  int _fragmentGeneration = -1;
  late List<Map<String, Object?>> _vertexBuffers;
  late List<_SampledTexture> _sampled;

  /// The textures this pipeline samples, in signature order. A pass resolves
  /// one [GpuSampleSlot] per entry.
  List<_SampledTexture> get sampledTextures {
    _refresh();
    return _sampled;
  }

  /// Rebuilds what depends on the shaders after either was hot reloaded.
  void _refresh() {
    if (_vertexGeneration == vertexShader.generation &&
        _fragmentGeneration == fragmentShader.generation) {
      return;
    }
    _vertexBuffers = _buildVertexBuffers();
    _sampled = [
      for (final shader in [vertexShader, fragmentShader])
        for (final slot in shader.textures)
          if (slot.shape != null) (shader: shader, slot: slot),
    ];
    _variants.clear();
    _vertexGeneration = vertexShader.generation;
    _fragmentGeneration = fragmentShader.generation;
  }

  /// The variant for a draw with [state] into [target], whose sampled
  /// textures resolved to [slots] (in [sampledTextures] order).
  _PipelineVariant variantFor(
    _RenderState state,
    _TargetShape target,
    List<GpuSampleSlot> slots,
  ) {
    _refresh();
    final key = _VariantKey(
      state,
      target,
      GpuSampleSignature(slots),
      float32Blendable: _context.float32Blendable,
    );
    return _variants[key] ??= _build(key, slots);
  }

  _PipelineVariant _build(_VariantKey key, List<GpuSampleSlot> slots) {
    final device = _context.device.device;
    if (kDebugMode) device.pushErrorScope('validation');
    final bindings = _context._bindingLayoutFor(_layoutEntries(slots));
    final pipeline = device.createRenderPipeline(
      _obj({
        'label': '${vertexShader.name} + ${fragmentShader.name}',
        'layout': bindings.pipelineLayout,
        'vertex': {
          'module': vertexShader.module,
          'entryPoint': vertexShader.entryPoint,
          'buffers': _vertexBuffers,
        },
        'fragment': {
          'module': fragmentShader.module,
          'entryPoint': fragmentShader.entryPoint,
          'targets': key.colorTargets,
        },
        'primitive': key.primitive,
        if (key.depthStencil case final depthStencil?)
          'depthStencil': depthStencil,
        'multisample': {'count': key.target.samples},
      }),
    );
    Future<String?>? validation;
    if (kDebugMode) {
      validation = device.popErrorScope().toDart.then((error) {
        if (error == null) return null;
        debugPrint(
          'flutter_scene (WebGPU): the pipeline for "${vertexShader.name}" '
          'and "${fragmentShader.name}" is invalid: ${error.message}',
        );
        return error.message;
      });
    }
    return _PipelineVariant(pipeline, bindings, validation);
  }

  /// Bind group layout entries for both stages. Everything sits in group 0
  /// with the bundle's binding numbers, which never overlap across stages.
  List<Map<String, Object?>> _layoutEntries(List<GpuSampleSlot> slots) {
    if (slots.length != _sampled.length) {
      throw ArgumentError(
        'Expected ${_sampled.length} resolved texture slots, got '
        '${slots.length}.',
      );
    }
    final uniforms = [
      for (final shader in [vertexShader, fragmentShader])
        for (final block in shader.uniforms.values)
          if (block.declared) (shader: shader, binding: block.binding),
    ]..sort((a, b) => a.binding.compareTo(b.binding));
    var dynamicLeft =
        _context.device.device.limits.maxDynamicUniformBuffersPerPipelineLayout;
    final entries = <Map<String, Object?>>[
      for (final u in uniforms)
        {
          'binding': u.binding,
          'visibility': _visibility(u.shader),
          'buffer': {'type': 'uniform', 'hasDynamicOffset': dynamicLeft-- > 0},
        },
    ];
    for (var i = 0; i < _sampled.length; i++) {
      final (:shader, :slot) = _sampled[i];
      final shape = slot.shape!;
      final resolved = slots[i];
      entries.add({
        'binding': slot.binding,
        'visibility': _visibility(shader),
        'texture': {
          'sampleType': resolved.sampleType.webGpuName,
          'viewDimension': shape.viewDimension.webGpuName,
          'multisampled': shape.multisampled,
        },
      });
      if (slot.samplerDeclared) {
        entries.add({
          'binding': slot.sampler,
          'visibility': _visibility(shader),
          'sampler': {'type': resolved.samplerType.webGpuName},
        });
      }
    }
    return entries
      ..sort((a, b) => (a['binding']! as int).compareTo(b['binding']! as int));
  }

  static int _visibility(_WebGpuShader shader) =>
      shader.stage == ShaderStage.vertex
      ? GPUShaderStage.vertex
      : GPUShaderStage.fragment;

  /// `GPUVertexBufferLayout`s, checked against the inputs the WGSL declares.
  /// A pipeline that cannot be built is an Exception, as on native, since
  /// the renderer's guard for a failed build catches exactly that.
  List<Map<String, Object?>> _buildVertexBuffers() {
    final declared = vertexShader.declaredInputs;
    final fed = <int>{};
    final buffers = <Map<String, Object?>>[];
    final layout = vertexLayout;
    if (layout == null) {
      final attributes = <Map<String, Object?>>[];
      for (final input in vertexShader.inputs) {
        final type = declared[input.location];
        if (type == null) continue;
        fed.add(input.location);
        attributes.add({
          'format': _defaultFormat(input.vecSize, type),
          'offset': input.offset,
          'shaderLocation': input.location,
        });
      }
      buffers.add({
        'arrayStride': vertexShader.vertexStride,
        'attributes': attributes,
      });
    } else {
      for (final buffer in layout.buffers) {
        buffers.add({
          'arrayStride': buffer.strideInBytes,
          'stepMode': buffer.stepMode == VertexStepMode.instance
              ? 'instance'
              : 'vertex',
          'attributes': [
            for (final attribute in buffer.attributes)
              _attribute(attribute, declared, fed),
          ],
        });
      }
    }
    final missing = declared.keys.where((l) => !fed.contains(l)).toList()
      ..sort();
    if (missing.isNotEmpty) {
      final names = [
        for (final l in missing)
          vertexShader.inputs
                  .where((i) => i.location == l)
                  .map((i) => i.name)
                  .firstOrNull ??
              'location $l',
      ];
      throw Exception(
        'The vertex layout for "${vertexShader.name}" feeds none of its '
        'inputs ${names.join(', ')}.',
      );
    }
    return buffers;
  }

  Map<String, Object?> _attribute(
    VertexAttribute attribute,
    Map<int, String> declared,
    Set<int> fed,
  ) {
    final input = vertexShader.inputs
        .where((i) => i.name == attribute.name)
        .firstOrNull;
    if (input == null) {
      throw Exception(
        'Vertex shader "${vertexShader.name}" has no input named '
        '"${attribute.name}".',
      );
    }
    final type = declared[input.location];
    if (type != null && _scalarOf(type) != _scalarOfFormat(attribute.format)) {
      throw Exception(
        'Vertex attribute "${attribute.name}" is ${attribute.format.name}, '
        'but "${vertexShader.name}" reads it as $type.',
      );
    }
    fed.add(input.location);
    return {
      'format': attribute.format.name,
      'offset': attribute.offsetInBytes,
      'shaderLocation': input.location,
    };
  }

  static String _defaultFormat(int components, String wgslType) {
    final scalar = switch (_scalarOf(wgslType)) {
      'u32' => 'uint32',
      'i32' => 'sint32',
      _ => 'float32',
    };
    return components == 1 ? scalar : '${scalar}x$components';
  }

  static String _scalarOf(String wgslType) => wgslType.contains('u32')
      ? 'u32'
      : wgslType.contains('i32')
      ? 'i32'
      : 'f32';

  static String _scalarOfFormat(VertexFormat format) =>
      format.name.startsWith('uint')
      ? 'u32'
      : format.name.startsWith('sint')
      ? 'i32'
      : 'f32';
}

/// A sampled slot resolved as if a plain color texture and a filtering
/// sampler were bound, the common case.
GpuSampleSlot _defaultSampleSlot(_TextureSlot slot, {required bool f32}) =>
    resolveSampleSlot(
      shape: slot.shape!,
      format: (depth: false, float32: false),
      samplerFilters: true,
      float32Filterable: f32,
    );

/// Builds (or finds) a variant of [pipeline], for tests that check pipeline
/// state without a pass. [textures] gives, per sampled texture, the format
/// bound and whether its sampler filters; omitted, every slot resolves as a
/// filtered color texture.
@visibleForTesting
({
  Object variant,
  Object bindGroupLayout,
  String layoutKey,
  List<int> dynamicBindings,
  Future<String?>? validation,
})
webGpuPipelineVariant(
  RenderPipeline pipeline, {
  List<PixelFormat> colorFormats = const [PixelFormat.r8g8b8a8UNormInt],
  PixelFormat? depthStencilFormat,
  int sampleCount = 1,
  CullMode? cullMode,
  WindingOrder? windingOrder,
  PrimitiveType? primitiveType,
  IndexType? stripIndexType,
  bool? depthWriteEnable,
  CompareFunction? depthCompare,
  ColorBlendEquation? blend,
  StencilConfig? stencil,
  List<({PixelFormat format, bool filters})>? textures,
}) {
  final p = pipeline as _WebGpuRenderPipeline;
  final device = p._context.device;
  final state = _RenderState();
  if (cullMode != null) state.setCullMode(cullMode);
  if (windingOrder != null) state.setWindingOrder(windingOrder);
  if (primitiveType != null) state.setPrimitiveType(primitiveType);
  if (stripIndexType != null) state.setStripIndexType(stripIndexType);
  if (depthWriteEnable != null) state.setDepthWriteEnable(depthWriteEnable);
  if (depthCompare != null) state.setDepthCompare(depthCompare);
  if (blend != null) {
    state
      ..setColorBlendEnable(true, 0)
      ..setColorBlendEquation(blend, 0);
  }
  if (stencil != null) state.setStencilConfig(stencil, StencilFace.both);
  final target = _TargetShape.of(
    [for (final f in colorFormats) _gpuFormatFor(f, device)],
    depthStencilFormat == null
        ? null
        : _gpuFormatFor(depthStencilFormat, device),
    sampleCount,
  );
  final f32 = p._context.float32Filterable;
  final sampled = p.sampledTextures;
  final slots = [
    for (var i = 0; i < sampled.length; i++)
      if (textures == null)
        _defaultSampleSlot(sampled[i].slot, f32: f32)
      else
        resolveSampleSlot(
          shape: sampled[i].slot.shape!,
          format: (
            depth: _gpuFormatFor(textures[i].format, device).depth,
            float32: _gpuFormatFor(textures[i].format, device).float32,
          ),
          samplerFilters: textures[i].filters,
          float32Filterable: f32,
        ),
  ];
  final variant = p.variantFor(state, target, slots);
  return (
    variant: variant,
    bindGroupLayout: variant.bindings.layout,
    layoutKey: variant.bindings.key,
    dynamicBindings: variant.bindings.dynamic,
    validation: variant.validation,
  );
}
