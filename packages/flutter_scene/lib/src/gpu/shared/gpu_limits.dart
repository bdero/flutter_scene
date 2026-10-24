/// How large the resources a device allocates can be, as opposed to which
/// features its backend has.
///
/// `GpuCapabilities` answers what a backend can do and
/// never touches a context. Limits are the device's numbers, so reading them
/// needs the context to exist; read them once the scene's static resources are
/// initialized, where a feature sizes its textures, not per frame.
library;

/// The texture limits of the active GPU device.
///
/// A size limit is null when the backend does not report it. Callers that
/// need a number then fall back to the guaranteed minimum of the API they
/// target (4096 texels and 256 layers cover every backend flutter_scene runs
/// on).
class GpuLimits {
  const GpuLimits({
    required this.maxTextureSize,
    required this.maxArrayLayers,
    required this.max3DTextureSize,
    required this.maxSamplersPerStage,
    required this.supportsTextureArrays,
    required this.supports3DTextures,
    required this.supportsFloat32Filtering,
  });

  /// The largest width or height of a 2D or 2D-array texture.
  final int? maxTextureSize;

  /// The most layers a 2D-array texture can have.
  final int? maxArrayLayers;

  /// The largest width, height or depth of a 3D texture. Null where 3D
  /// textures are not supported at all ([supports3DTextures]).
  final int? max3DTextureSize;

  /// The most textures one shader stage can sample.
  final int? maxSamplersPerStage;

  /// 2D-array textures can be created, uploaded and sampled as
  /// `sampler2DArray`.
  final bool supportsTextureArrays;

  /// 3D textures can be created, uploaded and sampled as `sampler3D`.
  final bool supports3DTextures;

  /// `r32Float` and `r32g32b32a32Float` textures filter linearly. Where false,
  /// they sample with nearest filtering only.
  final bool supportsFloat32Filtering;

  /// Whether a [width] x [height] 2D-array texture of [layers] layers can be
  /// allocated, so callers can test a size before allocating.
  bool fitsTextureArray(int width, int height, int layers) {
    final size = maxTextureSize;
    final maxLayers = maxArrayLayers;
    return supportsTextureArrays &&
        (size == null || (width <= size && height <= size)) &&
        (maxLayers == null || layers <= maxLayers);
  }

  /// Whether a [width] x [height] x [depth] 3D texture can be allocated.
  bool fitsTexture3D(int width, int height, int depth) {
    final size = max3DTextureSize;
    return supports3DTextures &&
        (size == null || (width <= size && height <= size && depth <= size));
  }

  @override
  String toString() =>
      'GpuLimits(maxTextureSize: $maxTextureSize, '
      'maxArrayLayers: $maxArrayLayers, max3DTextureSize: $max3DTextureSize, '
      'maxSamplersPerStage: $maxSamplersPerStage, '
      'supportsTextureArrays: $supportsTextureArrays, '
      'supports3DTextures: $supports3DTextures, '
      'supportsFloat32Filtering: $supportsFloat32Filtering)';
}

/// Where a [GpuWorkTiming] got its number, which says what it covers.
enum GpuTimingSource {
  /// The GPU's own clock (timer or timestamp queries): GPU execution only.
  gpuTimer,

  /// Wall time from submission until the backend reported the work finished
  /// on the GPU. Includes submission latency, so time enough work that it
  /// dominates.
  completion,

  /// Wall time until a blocking wait on the GPU returned. Like [completion],
  /// plus the round trip of the wait itself.
  blockingWait,
}

/// How long a batch of GPU work took, from [timeGpuWork].
class GpuWorkTiming {
  const GpuWorkTiming(this.elapsed, this.source);

  final Duration elapsed;
  final GpuTimingSource source;

  @override
  String toString() =>
      'GpuWorkTiming(${elapsed.inMicroseconds} us, ${source.name})';
}
