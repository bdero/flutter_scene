/// Fixed-function render state as one immutable value.
///
/// Flutter GPU sets this state per draw, the way Metal does. WebGPU bakes it
/// into a pipeline object instead, so a backend built on it has to key a
/// pipeline cache by exactly this tuple. Describing the state once, as a value
/// with equality, serves both: the Flutter GPU backend replays it onto a pass,
/// and a WebGPU backend uses it as a cache key.
///
/// Deliberately excludes viewport, scissor, stencil reference, and blend
/// constants. Those stay dynamic on every backend and do not belong in a
/// pipeline key.
///
/// This library imports the shim rather than being exported by it, which is
/// what lets one definition cover every backend without duplicating it per
/// backend or duplicating the state enums.
library;

import 'gpu.dart' as gpu;

/// How colours are combined with the destination, as a comparable value.
///
/// `gpu.ColorBlendEquation` is mutable and has reference equality, so it cannot
/// key a cache. This mirrors its fields and adds value equality.
class GpuBlendEquation {
  const GpuBlendEquation({
    this.colorBlendOperation = gpu.BlendOperation.add,
    this.sourceColorBlendFactor = gpu.BlendFactor.one,
    this.destinationColorBlendFactor = gpu.BlendFactor.oneMinusSourceAlpha,
    this.alphaBlendOperation = gpu.BlendOperation.add,
    this.sourceAlphaBlendFactor = gpu.BlendFactor.one,
    this.destinationAlphaBlendFactor = gpu.BlendFactor.oneMinusSourceAlpha,
  });

  final gpu.BlendOperation colorBlendOperation;
  final gpu.BlendFactor sourceColorBlendFactor;
  final gpu.BlendFactor destinationColorBlendFactor;
  final gpu.BlendOperation alphaBlendOperation;
  final gpu.BlendFactor sourceAlphaBlendFactor;
  final gpu.BlendFactor destinationAlphaBlendFactor;

  /// Straight alpha over the destination, the common transparency case.
  static const GpuBlendEquation alphaBlend = GpuBlendEquation();

  /// Adds source and destination, for additive effects.
  static const GpuBlendEquation additive = GpuBlendEquation(
    destinationColorBlendFactor: gpu.BlendFactor.one,
    destinationAlphaBlendFactor: gpu.BlendFactor.one,
  );

  /// A fresh mutable equation for the flutter_gpu call that needs one.
  gpu.ColorBlendEquation toGpu() => gpu.ColorBlendEquation(
    colorBlendOperation: colorBlendOperation,
    sourceColorBlendFactor: sourceColorBlendFactor,
    destinationColorBlendFactor: destinationColorBlendFactor,
    alphaBlendOperation: alphaBlendOperation,
    sourceAlphaBlendFactor: sourceAlphaBlendFactor,
    destinationAlphaBlendFactor: destinationAlphaBlendFactor,
  );

  @override
  bool operator ==(Object other) =>
      other is GpuBlendEquation &&
      other.colorBlendOperation == colorBlendOperation &&
      other.sourceColorBlendFactor == sourceColorBlendFactor &&
      other.destinationColorBlendFactor == destinationColorBlendFactor &&
      other.alphaBlendOperation == alphaBlendOperation &&
      other.sourceAlphaBlendFactor == sourceAlphaBlendFactor &&
      other.destinationAlphaBlendFactor == destinationAlphaBlendFactor;

  @override
  int get hashCode => Object.hash(
    colorBlendOperation,
    sourceColorBlendFactor,
    destinationColorBlendFactor,
    alphaBlendOperation,
    sourceAlphaBlendFactor,
    destinationAlphaBlendFactor,
  );

  @override
  String toString() =>
      'GpuBlendEquation(${colorBlendOperation.name}, '
      '${sourceColorBlendFactor.name} -> ${destinationColorBlendFactor.name})';
}

/// The fixed-function state a draw renders with.
///
/// Defaults match what the renderer sets for opaque geometry, so a state built
/// with no arguments is the common case rather than an arbitrary one.
class GpuPipelineState {
  const GpuPipelineState({
    this.cullMode = gpu.CullMode.backFace,
    this.windingOrder = gpu.WindingOrder.counterClockwise,
    this.primitiveType = gpu.PrimitiveType.triangle,
    this.depthWriteEnable = true,
    this.depthCompareOperation = gpu.CompareFunction.lessEqual,
    this.blend,
  });

  final gpu.CullMode cullMode;
  final gpu.WindingOrder windingOrder;
  final gpu.PrimitiveType primitiveType;
  final bool depthWriteEnable;
  final gpu.CompareFunction depthCompareOperation;

  /// How to blend with the destination, or null for no blending.
  final GpuBlendEquation? blend;

  /// Whether blending is on, which is what the flutter_gpu call takes.
  bool get colorBlendEnable => blend != null;

  /// A copy with the given fields replaced.
  GpuPipelineState copyWith({
    gpu.CullMode? cullMode,
    gpu.WindingOrder? windingOrder,
    gpu.PrimitiveType? primitiveType,
    bool? depthWriteEnable,
    gpu.CompareFunction? depthCompareOperation,
    GpuBlendEquation? blend,
    bool clearBlend = false,
  }) => GpuPipelineState(
    cullMode: cullMode ?? this.cullMode,
    windingOrder: windingOrder ?? this.windingOrder,
    primitiveType: primitiveType ?? this.primitiveType,
    depthWriteEnable: depthWriteEnable ?? this.depthWriteEnable,
    depthCompareOperation: depthCompareOperation ?? this.depthCompareOperation,
    blend: clearBlend ? null : (blend ?? this.blend),
  );

  /// Replays this state onto [pass].
  ///
  /// Backends that bake state into a pipeline object ignore this and use the
  /// value as a cache key instead.
  void applyTo(gpu.RenderPass pass) {
    pass.setCullMode(cullMode);
    pass.setWindingOrder(windingOrder);
    pass.setPrimitiveType(primitiveType);
    pass.setDepthWriteEnable(depthWriteEnable);
    pass.setDepthCompareOperation(depthCompareOperation);
    final blend = this.blend;
    pass.setColorBlendEnable(blend != null);
    if (blend != null) {
      pass.setColorBlendEquation(blend.toGpu());
    }
  }

  @override
  bool operator ==(Object other) =>
      other is GpuPipelineState &&
      other.cullMode == cullMode &&
      other.windingOrder == windingOrder &&
      other.primitiveType == primitiveType &&
      other.depthWriteEnable == depthWriteEnable &&
      other.depthCompareOperation == depthCompareOperation &&
      other.blend == blend;

  @override
  int get hashCode => Object.hash(
    cullMode,
    windingOrder,
    primitiveType,
    depthWriteEnable,
    depthCompareOperation,
    blend,
  );

  @override
  String toString() =>
      'GpuPipelineState(cull: ${cullMode.name}, winding: ${windingOrder.name}, '
      'primitive: ${primitiveType.name}, depthWrite: $depthWriteEnable, '
      'depthCompare: ${depthCompareOperation.name}, blend: $blend)';
}
