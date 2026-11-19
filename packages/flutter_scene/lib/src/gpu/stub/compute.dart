part of '_gpu.dart';

// Compute through the shim's own names. Flutter GPU's compute types are
// deliberately absent here, so shared code that names them fails analysis
// instead of failing to compile on an engine that predates them.

/// Whether the active context runs compute shaders.
bool get supportsCompute => _stub();

/// The active context's compute limits.
GpuComputeLimits get computeLimits => _stub();

/// A pipeline that runs [computeShader]. Check [supportsCompute] first.
GpuComputePipeline createComputePipeline(Shader computeShader) => _stub();

/// Begins a compute pass on [commandBuffer], ending its open pass.
GpuComputePass createComputePass(CommandBuffer commandBuffer) => _stub();

/// The storage buffer whose block is named [name] in [shader].
GpuStorageBufferSlot getStorageBufferSlot(Shader shader, String name) =>
    _stub();

/// A compute pipeline built from one compute shader.
abstract base class GpuComputePipeline {
  Shader get shader;
}

/// A storage buffer a compute shader declares.
abstract base class GpuStorageBufferSlot {
  Shader get shader;
  String get storageBufferName;

  /// The block size, counting a trailing runtime-sized array as empty.
  int get sizeInBytes;

  /// The stride of the block's trailing runtime-sized array, or 0.
  int get runtimeArrayStrideInBytes;
}

/// A pass that dispatches compute shaders. Bindings persist across
/// dispatches, and each dispatch sees every earlier write.
abstract base class GpuComputePass {
  void bindPipeline(GpuComputePipeline pipeline);
  void bindStorageBuffer(GpuStorageBufferSlot slot, BufferView bufferView);
  void bindUniform(UniformSlot slot, BufferView bufferView);
  void bindTexture(
    UniformSlot slot,
    Texture texture, {
    SamplerOptions? sampler,
  });
  void clearBindings();

  /// Dispatches workgroups, not invocations.
  void dispatch(
    int workgroupCountX, [
    int workgroupCountY = 1,
    int workgroupCountZ = 1,
  ]);
  void end();
}
