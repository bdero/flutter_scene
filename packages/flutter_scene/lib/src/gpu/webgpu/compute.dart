part of 'webgpu_backend.dart';

// Compute on WebGPU, matching Flutter GPU's ComputePass semantics: bindings
// persist across dispatches and pipelines, a dispatch needs every resource
// the shader reflects bound, and WebGPU orders each dispatch's writes before
// later dispatches and passes, so no barrier is needed.

final class _WebGpuStorageBufferSlot extends GpuStorageBufferSlot {
  _WebGpuStorageBufferSlot(this.shader, this.storageBufferName);

  @override
  final _WebGpuShader shader;

  @override
  final String storageBufferName;

  _StorageBlock get _block =>
      shader.storageBuffers[storageBufferName] ??
      (throw StateError(
        '"${shader.name}" no longer declares a storage buffer named '
        '"$storageBufferName". A hot reload removed it.',
      ));

  @override
  int get sizeInBytes => _block.size;

  @override
  int get runtimeArrayStrideInBytes => _block.stride;

  /// Throws unless [view] can back this buffer, with Flutter GPU's checks,
  /// since an out-of-bounds storage access is undefined on the GPU.
  void _validate(BufferView view, int alignment) {
    final block = _block;
    final name = storageBufferName;
    if (view.offsetInBytes < 0 ||
        view.lengthInBytes <= 0 ||
        view.offsetInBytes + view.lengthInBytes > view.buffer.sizeInBytes) {
      throw ArgumentError(
        'The BufferView for storage buffer "$name" (offset '
        '${view.offsetInBytes}, length ${view.lengthInBytes}) must be '
        'non-empty and lie within its DeviceBuffer '
        '(${view.buffer.sizeInBytes} bytes)',
      );
    }
    if (alignment > 1 && view.offsetInBytes % alignment != 0) {
      throw ArgumentError(
        'The BufferView offset for storage buffer "$name" '
        '(${view.offsetInBytes}) must be a multiple of $alignment',
      );
    }
    if (view.lengthInBytes < block.size) {
      throw ArgumentError(
        'Storage buffer "$name" needs at least ${block.size} bytes, but the '
        'BufferView is ${view.lengthInBytes} bytes',
      );
    }
    if (block.stride > 0 &&
        (view.lengthInBytes - block.size) % block.stride != 0) {
      throw ArgumentError(
        'Storage buffer "$name" ends in an array of ${block.stride}-byte '
        'elements after ${block.size} bytes, but the BufferView length '
        '(${view.lengthInBytes}) leaves a partial element',
      );
    }
  }
}

final class _WebGpuComputePipeline extends GpuComputePipeline {
  _WebGpuComputePipeline(this._context, this.shader) {
    if (!shader.isCompute) {
      throw ArgumentError(
        '"${shader.name}" is a ${shader.stage.name} shader, not a compute '
        'shader.',
      );
    }
    _refresh();
  }

  final _WebGpuContext _context;

  @override
  final _WebGpuShader shader;

  late GPUComputePipeline _pipeline;
  late GPUBindGroupLayout _layout;
  int _generation = -1;

  /// The validation error building the pipeline raised, once WebGPU answers.
  // TODO(webgpu-compute-validation): a dispatch before the answer reaches the
  // GPU and fails at submit, where Flutter GPU throws at creation. Await it
  // in an async pipeline factory.
  String? _error;

  /// Rebuilds the pipeline after a hot reload replaced the shader's module.
  void _refresh() {
    if (_generation == shader.generation) return;
    _checkWorkgroupSize();
    final device = _context.device.device;
    device.pushErrorScope('validation');
    // The auto layout leaves out what Tint dropped, as the bind group does.
    // TODO(webgpu-compute-layouts): build explicit layouts, shared across
    // pipelines like the render path's, so bind groups can be cached.
    _pipeline = device.createComputePipeline(
      _obj({
        'label': shader.name,
        'layout': 'auto',
        'compute': {'module': shader.module, 'entryPoint': shader.entryPoint},
      }),
    );
    _layout = _pipeline.getBindGroupLayout(0);
    _error = null;
    device.popErrorScope().toDart.then((error) => _error = error?.message);
    _generation = shader.generation;
  }

  /// Throws if the shader's `local_size` exceeds the device, as Flutter GPU
  /// does when it creates a pipeline.
  void _checkWorkgroupSize() {
    final limits = _context.computeLimits;
    final (x, y, z) = shader.workgroupSize;
    final (maxX, maxY, maxZ) = limits.maxWorkgroupSize;
    if (x > maxX ||
        y > maxY ||
        z > maxZ ||
        x * y * z > limits.maxWorkgroupInvocations) {
      throw Exception(
        '"${shader.name}" declares a workgroup of $x x $y x $z, past this '
        "device's $maxX x $maxY x $maxZ and "
        '${limits.maxWorkgroupInvocations} invocations.',
      );
    }
  }
}

typedef _TextureBinding = ({_WebGpuTexture texture, SamplerOptions sampler});

final class _WebGpuComputePass extends GpuComputePass
    implements _WebGpuOpenPass {
  _WebGpuComputePass(this._context, GPUCommandEncoder encoder)
    : _encoder = encoder.beginComputePass();

  final _WebGpuContext _context;
  final GPUComputePassEncoder _encoder;
  bool _ended = false;
  _WebGpuComputePipeline? _pipeline;

  // Bindings by shader and resource name, so a pipeline bound again later in
  // the pass finds its own.
  final Map<_WebGpuShader, Map<String, BufferView>> _storage = {};
  final Map<_WebGpuShader, Map<String, BufferView>> _uniforms = {};
  final Map<_WebGpuShader, Map<String, _TextureBinding>> _textures = {};

  void _checkOpen() {
    if (_ended) {
      throw StateError(
        'This compute pass has ended; a command buffer ends a pass when it '
        'starts the next one or is submitted.',
      );
    }
  }

  @override
  void bindPipeline(GpuComputePipeline pipeline) {
    _checkOpen();
    _pipeline = pipeline as _WebGpuComputePipeline;
  }

  @override
  void bindStorageBuffer(GpuStorageBufferSlot slot, BufferView bufferView) {
    _checkOpen();
    final s = slot as _WebGpuStorageBufferSlot;
    s._validate(
      bufferView,
      _context.computeLimits.minStorageBufferOffsetAlignment,
    );
    (_storage[s.shader] ??= {})[s.storageBufferName] = bufferView;
  }

  @override
  void bindUniform(UniformSlot slot, BufferView bufferView) {
    _checkOpen();
    final s = slot as _WebGpuUniformSlot;
    if (!s.shader.uniforms.containsKey(s.uniformName)) {
      throw Exception(
        'Failed to bind uniform (no uniform struct named "${s.uniformName}")',
      );
    }
    (_uniforms[s.shader] ??= {})[s.uniformName] = bufferView;
  }

  @override
  void bindTexture(
    UniformSlot slot,
    Texture texture, {
    SamplerOptions? sampler,
  }) {
    _checkOpen();
    final s = slot as _WebGpuUniformSlot;
    if (!s.shader.texturesByName.containsKey(s.uniformName)) {
      throw Exception(
        'Failed to bind texture (no texture named "${s.uniformName}")',
      );
    }
    (_textures[s.shader] ??= {})[s.uniformName] = (
      texture: texture as _WebGpuTexture,
      sampler: sampler ?? SamplerOptions(),
    );
  }

  @override
  void clearBindings() {
    _checkOpen();
    _storage.clear();
    _uniforms.clear();
    _textures.clear();
  }

  @override
  void dispatch(
    int workgroupCountX, [
    int workgroupCountY = 1,
    int workgroupCountZ = 1,
  ]) {
    _checkOpen();
    if (workgroupCountX < 0 || workgroupCountY < 0 || workgroupCountZ < 0) {
      throw RangeError('Workgroup counts must be non-negative.');
    }
    if (workgroupCountX == 0 || workgroupCountY == 0 || workgroupCountZ == 0) {
      return;
    }
    final pipeline = _pipeline;
    if (pipeline == null) {
      throw StateError(
        'ComputePass.dispatch() was called before a ComputePipeline was bound '
        'with ComputePass.bindPipeline().',
      );
    }
    final (maxX, maxY, maxZ) = _context.computeLimits.maxWorkgroupCount;
    if (workgroupCountX > maxX ||
        workgroupCountY > maxY ||
        workgroupCountZ > maxZ) {
      throw Exception(
        'Dispatching $workgroupCountX x $workgroupCountY x $workgroupCountZ '
        "workgroups exceeds this device's $maxX x $maxY x $maxZ.",
      );
    }
    pipeline._refresh();
    final error = pipeline._error;
    if (error != null) {
      throw Exception('"${pipeline.shader.name}" did not build: $error');
    }
    final entries = _bindGroupEntries(pipeline.shader);
    _encoder.setPipeline(pipeline._pipeline);
    if (entries.isNotEmpty) {
      // TODO(webgpu-compute-layouts): cache bind groups by bound resources,
      // as the render path does, instead of creating one per dispatch.
      _encoder.setBindGroup(
        0,
        _context.device.device.createBindGroup(
          _obj({'layout': pipeline._layout, 'entries': entries}),
        ),
      );
    }
    _encoder.dispatchWorkgroups(
      workgroupCountX,
      workgroupCountY,
      workgroupCountZ,
    );
  }

  /// The bind group entries for [shader] from what is bound. Throws naming
  /// the first reflected resource with nothing bound, including one Tint
  /// dropped, so a pass that dispatches here dispatches on every backend.
  List<Map<String, Object?>> _bindGroupEntries(_WebGpuShader shader) {
    final storage = _storage[shader] ?? const {};
    final uniforms = _uniforms[shader] ?? const {};
    final textures = _textures[shader] ?? const {};
    Never unbound(String kind, String name) => throw Exception(
      'Dispatching "${shader.name}" needs its $kind "$name" bound.',
    );

    final entries = <Map<String, Object?>>[];
    for (final block in shader.storageBuffers.values) {
      final view = storage[block.name] ?? unbound('storage buffer', block.name);
      if (!block.declared) continue;
      entries.add({
        'binding': block.binding,
        'resource': {
          'buffer': (view.buffer as _WebGpuDeviceBuffer).buffer,
          'offset': view.offsetInBytes,
          'size': view.lengthInBytes,
        },
      });
    }
    for (final block in shader.uniforms.values) {
      final view = uniforms[block.name] ?? unbound('uniform', block.name);
      if (!block.declared) continue;
      // WGSL pads a uniform struct to 16 bytes past the reflected size.
      final padded = (block.size + 15) & ~15;
      final room = view.buffer.sizeInBytes - view.offsetInBytes;
      entries.add({
        'binding': block.binding,
        'resource': {
          'buffer': (view.buffer as _WebGpuDeviceBuffer).buffer,
          'offset': view.offsetInBytes,
          'size': padded <= room ? padded : room,
        },
      });
    }
    // TODO(webgpu-compute-layouts): the auto layout assumes filterable float
    // textures; resolve GpuSampleSlots as the render path does once layouts
    // are explicit, so unfilterable formats bind.
    for (final slot in shader.textures) {
      final bound = textures[slot.name] ?? unbound('texture', slot.name);
      if (slot.shape != null) {
        entries.add({
          'binding': slot.binding,
          'resource': bound.texture.sampledView,
        });
      }
      if (slot.samplerDeclared) {
        entries.add({
          'binding': slot.sampler,
          'resource': _context.samplers.get(bound.sampler),
        });
      }
    }
    return entries;
  }

  @override
  void end() => _end();

  @override
  void _end() {
    if (_ended) return;
    _ended = true;
    _encoder.end();
  }
}
