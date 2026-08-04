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

  /// Which fields differ from [previous].
  ///
  /// A null [previous] means nothing is known about the pass, so every field
  /// counts as changed.
  GpuPipelineStateDelta diffFrom(GpuPipelineState? previous) {
    if (previous == null) return const GpuPipelineStateDelta.everything();
    return GpuPipelineStateDelta(
      cullMode: previous.cullMode != cullMode,
      windingOrder: previous.windingOrder != windingOrder,
      primitiveType: previous.primitiveType != primitiveType,
      depthWriteEnable: previous.depthWriteEnable != depthWriteEnable,
      depthCompareOperation:
          previous.depthCompareOperation != depthCompareOperation,
      blend: previous.blend != blend,
    );
  }

  /// Issues only the calls [delta] marks as changed.
  void applyDeltaTo(gpu.RenderPass pass, GpuPipelineStateDelta delta) {
    if (delta.cullMode) pass.setCullMode(cullMode);
    if (delta.windingOrder) pass.setWindingOrder(windingOrder);
    if (delta.primitiveType) pass.setPrimitiveType(primitiveType);
    if (delta.depthWriteEnable) pass.setDepthWriteEnable(depthWriteEnable);
    if (delta.depthCompareOperation) {
      pass.setDepthCompareOperation(depthCompareOperation);
    }
    if (delta.blend) {
      final blend = this.blend;
      pass.setColorBlendEnable(blend != null);
      if (blend != null) pass.setColorBlendEquation(blend.toGpu());
    }
  }

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

/// Which fields of a [GpuPipelineState] differ from another.
///
/// Separated from applying them so the decision is pure data, testable without
/// a render pass, and reusable by a backend that wants to know whether a state
/// change forces a new pipeline object rather than a new call.
class GpuPipelineStateDelta {
  const GpuPipelineStateDelta({
    this.cullMode = false,
    this.windingOrder = false,
    this.primitiveType = false,
    this.depthWriteEnable = false,
    this.depthCompareOperation = false,
    this.blend = false,
  });

  /// Everything differs, which is the case against an unknown pass.
  const GpuPipelineStateDelta.everything()
    : cullMode = true,
      windingOrder = true,
      primitiveType = true,
      depthWriteEnable = true,
      depthCompareOperation = true,
      blend = true;

  final bool cullMode;
  final bool windingOrder;
  final bool primitiveType;
  final bool depthWriteEnable;
  final bool depthCompareOperation;
  final bool blend;

  /// Nothing changed, so no calls are needed.
  bool get isEmpty =>
      !cullMode &&
      !windingOrder &&
      !primitiveType &&
      !depthWriteEnable &&
      !depthCompareOperation &&
      !blend;

  /// How many fields changed, for diagnostics and benchmarks.
  int get length =>
      (cullMode ? 1 : 0) +
      (windingOrder ? 1 : 0) +
      (primitiveType ? 1 : 0) +
      (depthWriteEnable ? 1 : 0) +
      (depthCompareOperation ? 1 : 0) +
      (blend ? 1 : 0);

  @override
  String toString() => 'GpuPipelineStateDelta($length changed)';
}

/// Tracks the state a pass is currently in, so only changes are re-issued.
///
/// Flutter GPU keeps this state on the pass, so re-issuing an unchanged setter
/// is wasted work. A backend that bakes state into pipeline objects instead
/// reads [current] to key its cache.
///
/// Anything that sets state on the pass without going through [apply] must be
/// followed by [invalidate], or the next apply will skip a call that is
/// actually needed.
class GpuPipelineStateTracker {
  GpuPipelineState? _current;

  /// The state the pass is believed to be in, or null when unknown.
  GpuPipelineState? get current => _current;

  /// Total setter calls issued, for benchmarking the memo's effectiveness.
  int get callsIssued => _callsIssued;
  int _callsIssued = 0;

  /// What [next] would change, without changing anything.
  GpuPipelineStateDelta deltaFor(GpuPipelineState next) =>
      next.diffFrom(_current);

  /// Issues only the calls needed to put [pass] into [next].
  void apply(gpu.RenderPass pass, GpuPipelineState next) {
    final delta = deltaFor(next);
    if (delta.isEmpty) return;
    next.applyDeltaTo(pass, delta);
    _callsIssued += delta.length;
    _current = next;
  }

  /// Forgets what the pass is in, after something else set state on it.
  void invalidate() => _current = null;

  /// Forgets the state and the call count, when starting a new pass.
  void reset() {
    _current = null;
    _callsIssued = 0;
  }
}
