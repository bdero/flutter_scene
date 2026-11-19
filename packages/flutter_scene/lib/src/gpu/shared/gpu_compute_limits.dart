/// The active context's compute limits, all zero where compute is
/// unsupported.
final class GpuComputeLimits {
  const GpuComputeLimits({
    required this.maxWorkgroupInvocations,
    required this.maxWorkgroupSize,
    required this.maxWorkgroupCount,
    required this.maxSharedMemoryBytes,
    required this.minStorageBufferOffsetAlignment,
  });

  /// The limits of a context with no compute.
  static const GpuComputeLimits none = GpuComputeLimits(
    maxWorkgroupInvocations: 0,
    maxWorkgroupSize: (0, 0, 0),
    maxWorkgroupCount: (0, 0, 0),
    maxSharedMemoryBytes: 0,
    minStorageBufferOffsetAlignment: 0,
  );

  /// The most invocations one workgroup runs, across all three dimensions.
  final int maxWorkgroupInvocations;

  /// The largest `local_size` along each dimension.
  final (int, int, int) maxWorkgroupSize;

  /// The most workgroups one dispatch launches along each dimension.
  final (int, int, int) maxWorkgroupCount;

  /// The most workgroup shared memory a shader declares, in bytes.
  final int maxSharedMemoryBytes;

  /// The alignment a storage buffer binding's offset needs.
  final int minStorageBufferOffsetAlignment;

  @override
  String toString() =>
      'GpuComputeLimits(invocations: $maxWorkgroupInvocations, '
      'size: $maxWorkgroupSize, count: $maxWorkgroupCount, '
      'shared: $maxSharedMemoryBytes, '
      'storageAlignment: $minStorageBufferOffsetAlignment)';
}
