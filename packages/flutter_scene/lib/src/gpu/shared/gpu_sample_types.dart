/// The texture and sampler binding types a WebGPU bind group layout states up
/// front, and where each one comes from.
///
/// WebGPU (https://www.w3.org/TR/webgpu/#bind-group-layout-creation) needs, per
/// texture binding, a sample type and view dimension, and per sampler binding,
/// whether it filters. Neither impellerc's reflection nor a Tint-translated
/// `sampler2D` says which, and the right answer for the sample type depends on
/// the texture bound at draw time (a depth target or an `r32Float` data texture
/// is unfilterable where an `rgba16Float` one is not). So the shader supplies
/// the shape ([wgslTextureShape]) and the bound resources supply the rest
/// ([resolveSampleSlot]), and [GpuSampleSignature] folds the per-draw part into
/// a pipeline cache key.
///
/// Pure data, so it is testable without a browser.
library;

/// `GPUTextureSampleType`.
enum GpuTextureSampleType {
  float('float'),
  unfilterableFloat('unfilterable-float'),
  depth('depth'),
  sint('sint'),
  uint('uint');

  const GpuTextureSampleType(this.webGpuName);
  final String webGpuName;
}

/// `GPUTextureViewDimension`, for the dimensions the engine samples.
enum GpuTextureViewDimension {
  d2('2d'),
  d2Array('2d-array'),
  cube('cube'),
  d3('3d');

  const GpuTextureViewDimension(this.webGpuName);
  final String webGpuName;
}

/// `GPUSamplerBindingType`.
enum GpuSamplerBindingType {
  filtering('filtering'),
  nonFiltering('non-filtering'),
  comparison('comparison');

  const GpuSamplerBindingType(this.webGpuName);
  final String webGpuName;
}

/// The scalar a WGSL texture type returns.
enum WgslTextureScalar { f32, i32, u32 }

/// What a WGSL texture declaration fixes about its binding, independent of the
/// texture bound to it.
typedef WgslTextureShape = ({
  GpuTextureViewDimension viewDimension,
  WgslTextureScalar scalar,
  bool depth,
  bool multisampled,
});

/// Reads the shape out of a declared WGSL texture type such as
/// `texture_2d<f32>`, `texture_cube<f32>`, or `texture_depth_2d`. Null when
/// [type] is not a sampled texture type.
WgslTextureShape? wgslTextureShape(String type) {
  final match = _textureType.firstMatch(type.replaceAll(' ', ''));
  if (match == null) return null;
  final multisampled = match.group(1) != null;
  final depth = match.group(2) != null;
  final dimension = switch (match.group(3)!) {
    '2d' => GpuTextureViewDimension.d2,
    '2d_array' => GpuTextureViewDimension.d2Array,
    'cube' => GpuTextureViewDimension.cube,
    '3d' => GpuTextureViewDimension.d3,
    _ => null,
  };
  if (dimension == null) return null;
  final scalar = switch (match.group(4)) {
    'i32' => WgslTextureScalar.i32,
    'u32' => WgslTextureScalar.u32,
    _ => WgslTextureScalar.f32,
  };
  return (
    viewDimension: dimension,
    scalar: scalar,
    depth: depth,
    multisampled: multisampled,
  );
}

final _textureType = RegExp(
  r'^texture_(multisampled_)?(depth_)?(2d_array|2d|cube_array|cube|3d)(?:<(f32|i32|u32)>)?$',
);

/// The facts about a texture format that decide how it may be sampled.
typedef GpuFormatSampling = ({
  /// A depth or depth-stencil format.
  bool depth,

  /// A 32-bit float color format, filterable only with `float32-filterable`.
  bool float32,
});

/// The resolved binding types for one texture and its paired sampler.
typedef GpuSampleSlot = ({
  GpuTextureSampleType sampleType,
  GpuSamplerBindingType samplerType,

  /// The bound sampler filters but the texture cannot be filtered, so the
  /// backend must bind a nearest-filtering copy of it. WebGPU rejects the
  /// draw otherwise; GL returns zeros and Metal filters, so nearest is the
  /// closest a conformant backend can get.
  bool samplerDowngraded,
});

/// Resolves the binding types for a texture declared as [shape], with a
/// texture of [format] and a sampler that [samplerFilters] bound to it.
///
/// Depth textures are sampled as plain floats (the engine has no comparison
/// samplers), which WebGPU allows only as `unfilterable-float` with a
/// non-filtering sampler. [float32Filterable] is whether the device was created
/// with the `float32-filterable` feature.
GpuSampleSlot resolveSampleSlot({
  required WgslTextureShape shape,
  required GpuFormatSampling format,
  required bool samplerFilters,
  required bool float32Filterable,
}) {
  if (shape.depth) {
    // A texture_depth_* declaration only arises from a shadow sampler.
    return (
      sampleType: GpuTextureSampleType.depth,
      samplerType: GpuSamplerBindingType.comparison,
      samplerDowngraded: false,
    );
  }
  switch (shape.scalar) {
    case WgslTextureScalar.i32:
      return (
        sampleType: GpuTextureSampleType.sint,
        samplerType: GpuSamplerBindingType.nonFiltering,
        samplerDowngraded: samplerFilters,
      );
    case WgslTextureScalar.u32:
      return (
        sampleType: GpuTextureSampleType.uint,
        samplerType: GpuSamplerBindingType.nonFiltering,
        samplerDowngraded: samplerFilters,
      );
    case WgslTextureScalar.f32:
      break;
  }
  final filterable =
      !format.depth &&
      (!format.float32 || float32Filterable) &&
      !shape.multisampled;
  if (filterable) {
    return (
      sampleType: GpuTextureSampleType.float,
      samplerType: samplerFilters
          ? GpuSamplerBindingType.filtering
          : GpuSamplerBindingType.nonFiltering,
      samplerDowngraded: false,
    );
  }
  return (
    sampleType: GpuTextureSampleType.unfilterableFloat,
    samplerType: GpuSamplerBindingType.nonFiltering,
    samplerDowngraded: samplerFilters,
  );
}

/// Resolves the compact 3-bit signature code ([sampleSlotCode]) for [shape]
/// and a bound texture's format/sampler flags without allocating a
/// [GpuSampleSlot] record.
@pragma('vm:prefer-inline')
@pragma('wasm:prefer-inline')
int resolveSampleSlotCode({
  required WgslTextureShape shape,
  required bool formatDepth,
  required bool formatFloat32,
  required bool samplerFilters,
  required bool float32Filterable,
}) {
  if (shape.depth) return 3;
  switch (shape.scalar) {
    case WgslTextureScalar.i32:
      return 4;
    case WgslTextureScalar.u32:
      return 5;
    case WgslTextureScalar.f32:
      break;
  }
  final filterable =
      !formatDepth &&
      (!formatFloat32 || float32Filterable) &&
      !shape.multisampled;
  if (filterable) {
    return samplerFilters ? 0 : 1;
  }
  return 2;
}

/// The 3-bit code [GpuSampleSignature] packs for [slot] (`0..5`).
int sampleSlotCode(GpuSampleSlot slot) => switch (slot.sampleType) {
  GpuTextureSampleType.float =>
    slot.samplerType == GpuSamplerBindingType.filtering ? 0 : 1,
  GpuTextureSampleType.unfilterableFloat => 2,
  GpuTextureSampleType.depth => 3,
  GpuTextureSampleType.sint => 4,
  GpuTextureSampleType.uint => 5,
};

/// Reconstructs the layout-relevant [GpuSampleSlot] from a [sampleSlotCode].
GpuSampleSlot sampleSlotFromCode(int code) => switch (code) {
  0 => (
    sampleType: GpuTextureSampleType.float,
    samplerType: GpuSamplerBindingType.filtering,
    samplerDowngraded: false,
  ),
  1 => (
    sampleType: GpuTextureSampleType.float,
    samplerType: GpuSamplerBindingType.nonFiltering,
    samplerDowngraded: false,
  ),
  2 => (
    sampleType: GpuTextureSampleType.unfilterableFloat,
    samplerType: GpuSamplerBindingType.nonFiltering,
    samplerDowngraded: false,
  ),
  3 => (
    sampleType: GpuTextureSampleType.depth,
    samplerType: GpuSamplerBindingType.comparison,
    samplerDowngraded: false,
  ),
  4 => (
    sampleType: GpuTextureSampleType.sint,
    samplerType: GpuSamplerBindingType.nonFiltering,
    samplerDowngraded: false,
  ),
  5 => (
    sampleType: GpuTextureSampleType.uint,
    samplerType: GpuSamplerBindingType.nonFiltering,
    samplerDowngraded: false,
  ),
  _ => throw RangeError.range(code, 0, 5, 'code'),
};

/// The per-draw part of a pipeline's bind group layouts, packed into one int.
///
/// A shader's declarations fix everything about its layouts except each
/// texture slot's resolved [GpuSampleSlot], which depends on what is bound.
/// Two draws of the same shader with equal signatures can share a pipeline and
/// its layouts. A resolved slot is one of six valid combinations, three bits
/// each, so up to ten texture slots fit in a 32-bit lane; wider layouts spill
/// into [overflow]. In practice nearly every draw of a material repeats
/// the same signature, so the extra cache axis rarely misses.
final class GpuSampleSignature {
  factory GpuSampleSignature(Iterable<GpuSampleSlot> slotsInLayoutOrder) {
    var first = 0;
    var lane = 0;
    var shift = 0;
    var hasOverflow = false;
    List<int>? extra;
    for (final slot in slotsInLayoutOrder) {
      if (shift == 30) {
        if (!hasOverflow) {
          first = lane;
          hasOverflow = true;
        } else {
          (extra ??= <int>[]).add(lane);
        }
        lane = 0;
        shift = 0;
      }
      lane |= sampleSlotCode(slot) << shift;
      shift += 3;
    }
    if (!hasOverflow) {
      return GpuSampleSignature.fromLanes(lane);
    }
    return GpuSampleSignature.fromLanes(
      first,
      List<int>.unmodifiable(<int>[...?extra, lane]),
    );
  }

  /// Builds a signature from pre-packed 30-bit lanes without allocating an
  /// overflow list when ten or fewer textures are sampled.
  GpuSampleSignature.fromLanes(this.primary, [this.overflow = const []])
    : hashCode = overflow.isEmpty
          ? primary.hashCode
          : Object.hash(primary, Object.hashAll(overflow));

  /// The first 30 bits, enough for every built-in material.
  final int primary;

  /// Lanes past the first, empty for layouts of ten or fewer textures.
  final List<int> overflow;

  @override
  final int hashCode;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! GpuSampleSignature ||
        other.primary != primary ||
        other.overflow.length != overflow.length) {
      return false;
    }
    for (var i = 0; i < overflow.length; i++) {
      if (other.overflow[i] != overflow[i]) return false;
    }
    return true;
  }
}
