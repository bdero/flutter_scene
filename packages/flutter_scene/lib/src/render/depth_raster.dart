import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show internal;
import 'package:vector_math/vector_math.dart';

import 'package:flutter_scene/src/camera.dart';
import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;

/// Depth-buffer steps one `Material.depthLayer` moves a surface toward the
/// camera, scaled up where float rounding of the vertex transform grows (see
/// `DepthRoundingSteps` in depth_bias.glsl).
const int kDepthLayerSteps = 8;

/// Pixels of a surface's own depth gradient one `Material.depthLayer` moves
/// it toward the camera, on top of [kDepthLayerSteps]. Rasterizer snapping
/// and interpolation perturb depth by a fraction of a pixel's worth of the
/// gradient (under a thirty-second on Apple GPUs), which on a grazing surface
/// outweighs any count of steps; on screen a layer moves nothing by more than
/// this share of a pixel.
const double kDepthLayerPixels = 0.25;

/// Depth-buffer steps one automatic tie-break rank moves a surface away from
/// the camera (see `Scene.coplanarTieBreak`).
const int kTieBreakSteps = 4;

/// Pixels of depth gradient one automatic tie-break rank moves a surface
/// away from the camera.
const double kTieBreakPixels = 1.0 / 16.0;

/// Distinct tie-break ranks: three by material times three by instance, so
/// a pair that differs in either never lands on one depth.
const int kTieBreakRanks = 9;

/// Depth-buffer steps and pixels of depth gradient one unit of a probe nudge
/// moves a surface (see `Scene.probeDepthConflicts`). A pair nudged apart by
/// one unit each fights when closer than twice this, half a tie-break rank.
const double kDepthNudgeSteps = 1.0;
const double kDepthNudgePixels = 1.0 / 64.0;

/// The largest `Material.depthLayer` magnitude.
const int kMaxDepthLayer = 8;

// A step of 24-bit depth (and of standard float depth past twice the near
// plane, where its exponent is fixed).
const double _kUnormStep = 1.0 / 16777216.0;

// A float32 ulp relative to the value, at its widest.
const double _kFloatRelativeStep = 1.0 / 8388608.0;

/// How one view's camera passes rasterize depth.
///
/// Every pass that draws into a camera depth buffer derives its clear value,
/// compare functions, and projection from the same [DepthRaster], so the
/// passes that share a depth attachment always agree. Shadow maps keep the
/// standard mapping and do not use this.
@internal
class DepthRaster {
  const DepthRaster({
    this.reversed = false,
    this.near,
    this.floatDepth = false,
    this.tieBreak = false,
  });

  /// The standard mapping (near 0, far 1) with the projection's own planes.
  static const DepthRaster standard = DepthRaster();

  /// Whether depth is reversed, 1 at the near plane and 0 at the far plane.
  /// With float depth this spreads precision evenly over distance.
  final bool reversed;

  /// A near plane fitted to visible content, replacing a perspective
  /// projection's own near when rasterizing. Null keeps the projection's.
  final double? near;

  /// Whether the depth attachment stores float32 depth rather than 24-bit
  /// unorm, which decides how a layer offset is expressed.
  final bool floatDepth;

  /// Whether materials without an explicit layer get an automatic rank, so
  /// exactly coplanar surfaces of different materials resolve to a stable
  /// winner instead of flickering.
  final bool tieBreak;

  /// The depth-stencil format of the camera depth attachments this raster
  /// draws into ([depthStencilFormatFor]).
  gpu.PixelFormat get depthStencilFormat =>
      depthStencilFormatFor(reversed: reversed);

  /// The depth-stencil format of camera passes with [reversed] depth: the
  /// backend's format for reversed depth (float where that gains precision),
  /// else the context default that shadow maps and masks also use.
  static gpu.PixelFormat depthStencilFormatFor({required bool reversed}) =>
      reversed
      ? gpu.reversedDepthStencilFormat
      : gpu.gpuContext.defaultDepthStencilFormat;

  /// The value a camera depth attachment clears to (the far plane).
  double get clearDepth => reversed ? 0.0 : 1.0;

  /// The clip-space depth over w of the far plane.
  double get farClipDepth => reversed ? 0.0 : 1.0;

  /// The compare function that passes a fragment at or nearer than the
  /// stored depth.
  gpu.CompareFunction get nearerOrEqual => reversed
      ? gpu.CompareFunction.greaterEqual
      : gpu.CompareFunction.lessEqual;

  /// [function], written for the standard mapping, translated to this one.
  /// Ordering comparisons flip under reversed depth; equality and the
  /// constant functions do not.
  gpu.CompareFunction compare(gpu.CompareFunction function) {
    if (!reversed) return function;
    return switch (function) {
      gpu.CompareFunction.less => gpu.CompareFunction.greater,
      gpu.CompareFunction.lessEqual => gpu.CompareFunction.greaterEqual,
      gpu.CompareFunction.greater => gpu.CompareFunction.less,
      gpu.CompareFunction.greaterEqual => gpu.CompareFunction.lessEqual,
      _ => function,
    };
  }

  /// Writes the clip-space offset that moves a surface [steps] depth-buffer
  /// steps toward the camera into [out] at [index], as a pair the vertex
  /// stage applies as `z * (1 + out[index]) + out[index + 1] * w`.
  ///
  /// Reversed float depth has constant relative precision, so it scales z.
  /// 24-bit depth and standard float depth have a constant step in window
  /// depth past twice the near plane, so they add a multiple of w.
  void writeOffset(double steps, Float32List out, int index) {
    if (steps == 0.0) {
      out[index] = 0.0;
      out[index + 1] = 0.0;
    } else if (reversed && floatDepth) {
      out[index] = steps * _kFloatRelativeStep;
      out[index + 1] = 0.0;
    } else {
      out[index] = 0.0;
      out[index + 1] = (reversed ? steps : -steps) * _kUnormStep;
    }
  }

  /// The slope-scaled offset that moves a surface [pixels] of its own depth
  /// gradient toward the camera, for a view whose window depth changes by
  /// [pixelSlope] per pixel per unit of the vertex stage's `DepthSlope` (see
  /// [pixelDepthSlope]).
  double slopeOffset(double pixels, double pixelSlope) =>
      (reversed ? pixels : -pixels) * pixelSlope;

  /// The view-space size of one depth-buffer step at planar [distance] for a
  /// perspective projection whose near plane is [near].
  double worldStepAt(double distance, double near) {
    if (reversed && floatDepth) return distance * _kFloatRelativeStep;
    return distance * distance * _kUnormStep / near;
  }

  @override
  bool operator ==(Object other) =>
      other is DepthRaster &&
      other.reversed == reversed &&
      other.near == near &&
      other.floatDepth == floatDepth &&
      other.tieBreak == tieBreak;

  @override
  int get hashCode => Object.hash(reversed, near, floatDepth, tieBreak);
}

/// The clip-space depth offset of the draw being encoded, read by geometry
/// `bind` implementations when they pack their vertex uniforms.
///
/// `[0]` and `[1]` are the material's offset (its layer and tie-break rank)
/// as [DepthRaster.writeOffset] writes it. `[2]` and `[3]` are the offset of
/// one per-instance tie-break rank, which the vertex stage multiplies by a
/// rank hashed from the instance's position (zero when the tie-break is off).
/// Encoders set it right before binding each draw.
@internal
final Float32List currentDrawDepthOffset = Float32List(4);

/// The slope-scaled depth offsets of the draw being encoded, read with
/// [currentDrawDepthOffset], as [DepthRaster.slopeOffset] writes them: `[0]`
/// the material's layer, `[1]` one per-instance tie-break rank, `[2]` the
/// material's tie-break rank. The vertex stage caps the slope it scales the
/// tie-break by lower than a layer's.
@internal
final Float32List currentDrawDepthSlope = Float32List(4);

/// The far plane's clip depth over w for the pass being encoded (1 standard,
/// 0 reversed), for vertex stages that cull past it themselves (splats).
@internal
double currentRasterFarClipDepth = 1.0;

/// Sets [currentDrawDepthOffset] and [currentDrawDepthSlope] for a draw with
/// a material's [layer] and tie-break [rank] under [raster], plus [nudge]
/// units of [kDepthNudgeSteps] and [kDepthNudgePixels] (the depth conflict
/// probe's margin test). [pixelSlope] is the view's (see [pixelDepthSlope]);
/// zero leaves out the slope-scaled offset, for passes that must match the
/// position-only velocity pass.
///
/// The tie-break pushes a layer-0 surface back by its rank, three per
/// material rank plus its instance rank (which the vertex stage adds), so
/// positive layers stay in front of every rank and negative layers are moved
/// back past the deepest one.
@internal
void setCurrentDrawDepthOffset(
  DepthRaster raster,
  int layer,
  int rank, {
  double pixelSlope = 0.0,
  double nudge = 0.0,
}) {
  currentRasterFarClipDepth = raster.farClipDepth;
  final tie = raster.tieBreak && layer == 0;
  final below = raster.tieBreak && layer < 0 ? kTieBreakRanks - 1.0 : 0.0;
  final materialRanks = tie ? rank * 3.0 : 0.0;
  raster.writeOffset(
    layer * kDepthLayerSteps -
        (below + materialRanks) * kTieBreakSteps +
        nudge * kDepthNudgeSteps,
    currentDrawDepthOffset,
    0,
  );
  raster.writeOffset(
    tie ? -kTieBreakSteps.toDouble() : 0.0,
    currentDrawDepthOffset,
    2,
  );
  currentDrawDepthSlope[0] = raster.slopeOffset(
    layer * kDepthLayerPixels -
        below * kTieBreakPixels +
        nudge * kDepthNudgePixels,
    pixelSlope,
  );
  currentDrawDepthSlope[1] = raster.slopeOffset(
    tie ? -kTieBreakPixels : 0.0,
    pixelSlope,
  );
  currentDrawDepthSlope[2] = raster.slopeOffset(
    -materialRanks * kTieBreakPixels,
    pixelSlope,
  );
}

/// How much window depth changes per pixel of screen distance per unit of
/// the vertex stage's `DepthSlope`, for a view rasterizing with [projection]
/// (its raster projection matrix) into a target [height] pixels tall: the
/// depth row's constant over the focal length in pixels for perspective, the
/// depth scale times world units per pixel for orthographic.
@internal
double pixelDepthSlope(Matrix4 projection, double height) {
  final s = projection.storage;
  final focal = s[5].abs() * height * 0.5;
  if (!(focal > 0.0)) return 0.0;
  final perspective = s[11] != 0.0;
  return (perspective ? s[14] : s[10]).abs() / focal;
}

/// The world size of one pixel for a view rasterizing with [projection] into
/// a target [height] pixels tall: per unit of planar view depth (one over the
/// focal length in pixels) for perspective, in world units for orthographic.
@internal
double pixelWorldScale(Matrix4 projection, double height) {
  final focal = projection.storage[5].abs() * height * 0.5;
  return focal > 0.0 ? 1.0 / focal : 0.0;
}

/// Clears [currentDrawDepthOffset], for passes that never offset depth
/// (shadow maps).
@internal
void clearCurrentDrawDepthOffset() {
  currentRasterFarClipDepth = 1.0;
  currentDrawDepthOffset.fillRange(0, 4, 0.0);
  currentDrawDepthSlope.fillRange(0, 4, 0.0);
}

/// [matrix] with its depth row reversed (`row2 := row3 - row2`), so clip
/// depth over w becomes `1 - z/w`. Exact for any projection whose depth
/// range is `[0, 1]`, including an oblique near-plane clip.
@internal
Matrix4 reverseDepthRow(Matrix4 matrix) {
  final s = matrix.storage;
  return Matrix4.copy(
    matrix,
  )..setRow(2, Vector4(s[3] - s[2], s[7] - s[6], s[11] - s[10], s[15] - s[14]));
}

/// The projection a camera pass rasterizes with: [projection] resolved for a
/// view of [viewportSize] under [raster] (reversed depth, fitted near).
///
/// Built-in projections are rebuilt in double precision; any other is read
/// back and its depth row reversed.
@internal
Matrix4 rasterProjectionMatrix(
  CameraProjection projection,
  ui.Size viewportSize,
  DepthRaster raster, {
  Vector2? jitter,
}) {
  final built = buildRasterProjectionMatrix(
    projection,
    viewportSize,
    reversed: raster.reversed,
    near: raster.near,
    jitter: jitter,
  );
  if (built != null) return built;
  final matrix = projection.getProjectionMatrixForViewport(
    viewportSize,
    jitter: jitter,
  );
  return raster.reversed ? reverseDepthRow(matrix) : matrix;
}
