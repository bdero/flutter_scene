import 'dart:math' as math;
import 'dart:typed_data';

import 'package:vector_math/vector_math.dart' as vm;

/// How a splat file's colors relate to the renderer's linear HDR pipeline.
///
/// Captured splats are usually trained against display-referred (sRGB
/// encoded) images, so their colors must be decoded to linear before they
/// enter the scene's linear HDR pipeline. Procedurally constructed splats
/// whose colors are already linear skip the decode.
/// {@category Gaussian splatting}
enum SplatColorSpace {
  /// Colors are sRGB encoded (the trained-capture convention). The renderer
  /// decodes them to linear after evaluating spherical harmonics.
  displayReferred,

  /// Colors are already linear; no decode is applied.
  linear,
}

/// The CPU-side contents of a Gaussian splat set as flat, index-parallel
/// arrays (one entry per splat).
///
/// The seam between the file parsers, procedural construction, and the
/// renderer. Parsers produce a [SplatData], and `GaussianSplats` packs one
/// into GPU textures.
/// {@category Gaussian splatting}
class SplatData {
  /// Wraps existing arrays without copying. Every array's length must match
  /// [count] times its per-splat stride.
  SplatData({
    required this.count,
    required this.positions,
    required this.scales,
    required this.rotations,
    required this.colors,
    required this.opacities,
    this.sh,
    this.shDegree = 0,
  }) : assert(positions.length == count * 3),
       assert(scales.length == count * 3),
       assert(rotations.length == count * 4),
       assert(colors.length == count * 3),
       assert(opacities.length == count),
       assert(shDegree >= 0 && shDegree <= 2),
       assert(
         (shDegree == 0) == (sh == null),
         'sh must be provided exactly when shDegree > 0',
       ),
       assert(
         sh == null || sh.length == count * shRestCoeffCount(shDegree) * 3,
       );

  /// Allocates a zero-filled splat set for [count] splats, for callers that
  /// fill the arrays in place (procedural construction).
  factory SplatData.zeroed(int count, {int shDegree = 0}) {
    return SplatData(
      count: count,
      positions: Float32List(count * 3),
      scales: Float32List(count * 3),
      rotations: Float32List(count * 4),
      colors: Float32List(count * 3),
      opacities: Float32List(count),
      sh: shDegree > 0
          ? Float32List(count * shRestCoeffCount(shDegree) * 3)
          : null,
      shDegree: shDegree,
    );
  }

  /// The number of splats.
  final int count;

  /// Splat centers in local space, `x, y, z` per splat.
  final Float32List positions;

  /// Per-axis Gaussian standard deviations in local units (already linear;
  /// parsers apply the training log-space `exp`), `x, y, z` per splat.
  final Float32List scales;

  /// Unit orientation quaternions, `x, y, z, w` per splat.
  final Float32List rotations;

  /// Base RGB color per splat, the evaluated degree-0 spherical-harmonic
  /// term, in the file's [SplatColorSpace].
  final Float32List colors;

  /// Opacity in [0, 1] per splat (parsers apply the training sigmoid).
  final Float32List opacities;

  /// Rest (degree >= 1) spherical-harmonic coefficients, or null when
  /// [shDegree] is 0.
  ///
  /// Per splat, [shRestCoeffCount] coefficients of `r, g, b`, ordered by band
  /// then by the standard 3DGS basis order within a band.
  final Float32List? sh;

  /// The highest spherical-harmonic degree carried by [sh] (0, 1, or 2).
  final int shDegree;

  /// Rest (beyond degree 0) SH coefficients per splat and channel, 0 at
  /// [degree] 0, 3 at 1, 8 at 2.
  static int shRestCoeffCount(int degree) => (degree + 1) * (degree + 1) - 1;

  /// Computes the axis-aligned bounds of the splat centers, each padded by
  /// [sigmaPadding] times the splat's largest axis scale so the visible
  /// footprint stays inside the box.
  vm.Aabb3? computeBounds({double sigmaPadding = 3.0}) {
    if (count == 0) return null;
    var minX = double.infinity, minY = double.infinity, minZ = double.infinity;
    var maxX = double.negativeInfinity,
        maxY = double.negativeInfinity,
        maxZ = double.negativeInfinity;
    for (var i = 0; i < count; i++) {
      final o = i * 3;
      final r =
          sigmaPadding *
          math.max(
            scales[o].abs(),
            math.max(scales[o + 1].abs(), scales[o + 2].abs()),
          );
      final x = positions[o], y = positions[o + 1], z = positions[o + 2];
      if (x - r < minX) minX = x - r;
      if (y - r < minY) minY = y - r;
      if (z - r < minZ) minZ = z - r;
      if (x + r > maxX) maxX = x + r;
      if (y + r > maxY) maxY = y + r;
      if (z + r > maxZ) maxZ = z + r;
    }
    return vm.Aabb3.minMax(
      vm.Vector3(minX, minY, minZ),
      vm.Vector3(maxX, maxY, maxZ),
    );
  }
}
