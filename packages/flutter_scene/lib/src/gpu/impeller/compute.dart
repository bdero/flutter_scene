part of '_gpu.dart';

// Compute arrived in Flutter GPU with Flutter 3.53, after this package's
// floor, so these reach that API by name and report no compute on an older
// engine. The extension types wrap Flutter GPU's own objects, costing only a
// dynamic call each.
// TODO(min-flutter-3.53): call the Flutter GPU members directly once the
// minimum Flutter version is 3.53 or newer, and make these types aliases of
// ComputePipeline, ComputePass and StorageBufferSlot.
// ignore_for_file: avoid_dynamic_calls

bool? _supportsCompute;

/// Whether the active context runs compute shaders. False on engines older
/// than Flutter 3.53 and on OpenGL ES.
bool get supportsCompute {
  final known = _supportsCompute;
  if (known != null) return known;
  final GpuContext context;
  try {
    context = gpuContext;
  } on Exception {
    // No context where Impeller is off; ask again once there is one.
    return false;
  }
  try {
    return _supportsCompute = (context as dynamic).supportsCompute as bool;
  } on NoSuchMethodError {
    return _supportsCompute = false;
  }
}

/// The active context's compute limits, or [GpuComputeLimits.none] without
/// compute.
GpuComputeLimits get computeLimits {
  if (!supportsCompute) return GpuComputeLimits.none;
  final dynamic context = gpuContext;
  (int, int, int) extent(dynamic e) => (e.x as int, e.y as int, e.z as int);
  return GpuComputeLimits(
    maxWorkgroupInvocations: context.maxComputeWorkgroupInvocations as int,
    maxWorkgroupSize: extent(context.maxComputeWorkgroupSize),
    maxWorkgroupCount: extent(context.maxComputeWorkgroupCount),
    maxSharedMemoryBytes: context.maxComputeSharedMemorySizeInBytes as int,
    minStorageBufferOffsetAlignment:
        context.minimumStorageBufferByteAlignment as int,
  );
}

Never _noCompute() => throw UnsupportedError(
  'Compute needs Flutter 3.53 or newer on Metal or Vulkan. Check '
  'supportsCompute first.',
);

/// A pipeline that runs [computeShader]. Check [supportsCompute] first.
GpuComputePipeline createComputePipeline(Shader computeShader) {
  if (!supportsCompute) _noCompute();
  return GpuComputePipeline._(
    (gpuContext as dynamic).createComputePipeline(computeShader) as Object,
  );
}

/// Begins a compute pass on [commandBuffer], ending its open pass.
GpuComputePass createComputePass(CommandBuffer commandBuffer) {
  if (!supportsCompute) _noCompute();
  return GpuComputePass._(
    (commandBuffer as dynamic).createComputePass() as Object,
  );
}

/// The storage buffer whose block is named [name] in [shader].
GpuStorageBufferSlot getStorageBufferSlot(Shader shader, String name) {
  if (!supportsCompute) _noCompute();
  return GpuStorageBufferSlot._(
    (shader as dynamic).getStorageBufferSlot(name) as Object,
  );
}

/// A Flutter GPU `ComputePipeline`.
extension type GpuComputePipeline._(Object _pipeline) {
  Shader get shader => (_pipeline as dynamic).shader as Shader;
}

/// A Flutter GPU `StorageBufferSlot`.
extension type GpuStorageBufferSlot._(Object _slot) {
  Shader get shader => (_slot as dynamic).shader as Shader;
  String get storageBufferName =>
      (_slot as dynamic).storageBufferName as String;
  int get sizeInBytes => (_slot as dynamic).sizeInBytes as int;
  int get runtimeArrayStrideInBytes =>
      (_slot as dynamic).runtimeArrayStrideInBytes as int;
}

/// A Flutter GPU `ComputePass`.
extension type GpuComputePass._(Object _pass) {
  void bindPipeline(GpuComputePipeline pipeline) =>
      (_pass as dynamic).bindPipeline(pipeline._pipeline);

  void bindStorageBuffer(GpuStorageBufferSlot slot, BufferView bufferView) =>
      (_pass as dynamic).bindStorageBuffer(slot._slot, bufferView);

  void bindUniform(UniformSlot slot, BufferView bufferView) =>
      (_pass as dynamic).bindUniform(slot, bufferView);

  void bindTexture(
    UniformSlot slot,
    Texture texture, {
    SamplerOptions? sampler,
  }) => (_pass as dynamic).bindTexture(slot, texture, sampler: sampler);

  void clearBindings() => (_pass as dynamic).clearBindings();

  void dispatch(
    int workgroupCountX, [
    int workgroupCountY = 1,
    int workgroupCountZ = 1,
  ]) => (_pass as dynamic).dispatch(
    workgroupCountX,
    workgroupCountY,
    workgroupCountZ,
  );

  void end() => (_pass as dynamic).end();
}
