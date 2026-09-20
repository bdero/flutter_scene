import 'dart:typed_data';

import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_scene/src/material/dfg_lut_data.dart';

/// Builds the split-sum "environment BRDF" (DFG) lookup texture used by the PBR
/// specular image-based lighting: for each `(n·v, roughness)` it stores the
/// scale (R) and bias (G) that combine as `F0 * scale + bias` (Karis 2013).
///
/// The terms are precomputed by importance-sampling the GGX BRDF and shipped
/// as `assets/dfg.bin` ([dfgHalfData]); integrating them at load time (what
/// happens when the asset is missing) costs a few hundred milliseconds of CPU.
/// Either way they are stored as
/// **RGBA16F** rather than an 8-bit asset. The DFG terms are smooth ramps in
/// `[0, 1]`; 8 bits of precision visibly bands the specular energy (most
/// obvious as radial stepping on large glossy surfaces), while half-float is
/// filterable on every backend (half-float linear filtering is core in
/// GLES 3.0 / WebGL2, unlike 32-bit float) and removes the stepping.
///
/// The texture is sampled linearly, clamped, with the standard convention
/// `texture(brdf_lut, vec2(n·v, roughness))` (V axis is roughness, 0 at the
/// smooth end).
/// When [ltcHalfData] is provided (the two fitted 64x64 RGBA half-float
/// linearly-transformed-cosine tables, concatenated), the texture becomes a
/// three-tile atlas: the DFG terms in x [0, size), the LTC inverse-matrix
/// fit in [size, 2*size), and the LTC magnitude/Fresnel fit in
/// [2*size, 3*size). The shader helpers in `material_engine_lighting.glsl`
/// remap each consumer's UV into its tile.
///
/// The LTC tables are the fitted data from "Real-Time Polygonal-Light
/// Shading with Linearly Transformed Cosines", Eric Heitz, Jonathan Dupuy,
/// Stephen Hill and David Neubelt, ACM TOG (Proc. SIGGRAPH 2016) 35(4),
/// 2016, https://eheitzresearch.wordpress.com/415-2/, redistributed per the
/// authors' license (copyright (c) 2017 Eric Heitz, Jonathan Dupuy, Stephen
/// Hill and David Neubelt).
gpu.Texture buildBrdfLutTexture({
  int size = kDfgLutSize,
  int sampleCount = kDfgLutSampleCount,
  Uint16List? ltcHalfData,
  Uint16List? dfgHalfData,
}) {
  final tiles = ltcHalfData != null ? 3 : 1;
  final width = size * tiles;
  final halfData = Uint16List(width * size * 4);
  // The DFG terms come from the shipped `assets/dfg.bin` when the caller read
  // it; integrating them here (the fallback) costs 4.19 M Monte-Carlo samples
  // on whatever isolate this runs on.
  final dfg =
      dfgHalfData ?? buildDfgLutHalfData(size: size, sampleCount: sampleCount);
  if (dfg.length != size * size * 4) {
    throw ArgumentError(
      'DFG table data must hold ${size * size * 4} half floats, '
      'got ${dfg.length}.',
    );
  }
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      final src = (y * size + x) * 4;
      final dst = (y * width + x) * 4;
      for (var c = 0; c < 4; c++) {
        halfData[dst + c] = dfg[src + c];
      }
    }
  }
  if (ltcHalfData != null) {
    final expected = size * size * 4 * 2;
    if (ltcHalfData.length != expected) {
      throw ArgumentError(
        'LTC table data must hold $expected half floats, '
        'got ${ltcHalfData.length}.',
      );
    }
    for (var tile = 0; tile < 2; tile++) {
      for (var y = 0; y < size; y++) {
        for (var x = 0; x < size; x++) {
          final src = (tile * size * size + y * size + x) * 4;
          final dst = (y * width + (tile + 1) * size + x) * 4;
          for (var c = 0; c < 4; c++) {
            halfData[dst + c] = ltcHalfData[src + c];
          }
        }
      }
    }
  }

  final texture = gpu.gpuContext.createTexture(
    gpu.StorageMode.hostVisible,
    width,
    size,
    format: gpu.PixelFormat.r16g16b16a16Float,
  );
  texture.overwrite(ByteData.sublistView(halfData));
  return texture;
}
