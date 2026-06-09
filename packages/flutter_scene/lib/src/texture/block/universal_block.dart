// A pure-Dart 4x4 LDR block codec, the transcode-friendly intermediate that
// rides inside KTX2 and is decoded (or transcoded to a GPU block format) at
// load time.
//
// This is flutter_scene's own block format, not Basis UASTC. It keeps UASTC's
// architecture (one 16-byte 4x4 block that transcodes to the device's family
// at load) but a layout we both encode and decode, so every layer is
// round-trip testable without external reference vectors. The format is
// deliberately simple: two RGBA8 endpoints and a 4-bit weight per texel along
// the endpoint line.
//
// Block layout (128 bits, little-endian byte order):
//   bytes 0..3   endpoint 0 = R, G, B, A
//   bytes 4..7   endpoint 1 = R, G, B, A
//   bytes 8..15  sixteen 4-bit weights, texel 0 in the low nibble of byte 8
//
// A texel is reconstructed as lerp(endpoint0, endpoint1, weight / 15) per
// channel. Color and alpha share one weight; uncorrelated alpha loses
// precision.
// TODO(texture-compression): add a second (alpha) endpoint line for textures
// whose alpha is uncorrelated with color, the way BC7/UASTC partition modes do.

import 'dart:math' as math;
import 'dart:typed_data';

/// Edge length of a block in texels.
const int kBlockDim = 4;

/// Bytes per encoded block (1 byte per texel, a 4x compression of rgba8).
const int kBlockBytes = 16;

const int _texelsPerBlock = kBlockDim * kBlockDim;
const int _weightLevels = 16; // 4-bit weights

/// Encodes [width] x [height] rgba8 pixels to packed 4x4 blocks. Dimensions
/// need not be multiples of four; edge texels are replicated to fill the last
/// partial blocks.
Uint8List encodeUniversalBlocks(Uint8List rgba, int width, int height) {
  if (rgba.length < width * height * 4) {
    throw ArgumentError('rgba is too small for ${width}x$height');
  }
  final blocksX = (width + kBlockDim - 1) ~/ kBlockDim;
  final blocksY = (height + kBlockDim - 1) ~/ kBlockDim;
  final out = Uint8List(blocksX * blocksY * kBlockBytes);

  final texel = Int32List(_texelsPerBlock * 4);
  for (var by = 0; by < blocksY; by++) {
    for (var bx = 0; bx < blocksX; bx++) {
      // Gather the block, clamping coordinates into the image for partial
      // blocks at the right/bottom edges.
      for (var ty = 0; ty < kBlockDim; ty++) {
        final sy = _clamp(by * kBlockDim + ty, height - 1);
        for (var tx = 0; tx < kBlockDim; tx++) {
          final sx = _clamp(bx * kBlockDim + tx, width - 1);
          final src = (sy * width + sx) * 4;
          final dst = (ty * kBlockDim + tx) * 4;
          texel[dst] = rgba[src];
          texel[dst + 1] = rgba[src + 1];
          texel[dst + 2] = rgba[src + 2];
          texel[dst + 3] = rgba[src + 3];
        }
      }
      _encodeBlock(texel, out, (by * blocksX + bx) * kBlockBytes);
    }
  }
  return out;
}

/// Decodes packed 4x4 blocks back to [width] x [height] rgba8 pixels, dropping
/// the replicated edge texels of partial blocks.
Uint8List decodeUniversalBlocksToRgba8(
  Uint8List blocks,
  int width,
  int height,
) {
  final blocksX = (width + kBlockDim - 1) ~/ kBlockDim;
  final blocksY = (height + kBlockDim - 1) ~/ kBlockDim;
  if (blocks.length < blocksX * blocksY * kBlockBytes) {
    throw ArgumentError('blocks is too small for ${width}x$height');
  }
  final out = Uint8List(width * height * 4);
  final texel = Int32List(_texelsPerBlock * 4);
  for (var by = 0; by < blocksY; by++) {
    for (var bx = 0; bx < blocksX; bx++) {
      _decodeBlock(blocks, (by * blocksX + bx) * kBlockBytes, texel);
      for (var ty = 0; ty < kBlockDim; ty++) {
        final dy = by * kBlockDim + ty;
        if (dy >= height) break;
        for (var tx = 0; tx < kBlockDim; tx++) {
          final dx = bx * kBlockDim + tx;
          if (dx >= width) continue;
          final src = (ty * kBlockDim + tx) * 4;
          final dst = (dy * width + dx) * 4;
          out[dst] = texel[src];
          out[dst + 1] = texel[src + 1];
          out[dst + 2] = texel[src + 2];
          out[dst + 3] = texel[src + 3];
        }
      }
    }
  }
  return out;
}

int _clamp(int value, int max) => value < 0
    ? 0
    : value > max
    ? max
    : value;

int _round8(double v) => v < 0
    ? 0
    : v > 255
    ? 255
    : (v + 0.5).floor();

/// Fits two endpoints along the block's principal color axis, then picks the
/// nearest weight for each texel and refines the endpoints once by least
/// squares.
void _encodeBlock(Int32List texel, Uint8List out, int offset) {
  // Mean of the 16 texels.
  final mean = Float64List(4);
  for (var i = 0; i < _texelsPerBlock; i++) {
    for (var c = 0; c < 4; c++) {
      mean[c] += texel[i * 4 + c];
    }
  }
  for (var c = 0; c < 4; c++) {
    mean[c] /= _texelsPerBlock;
  }

  // Principal axis by power iteration on the covariance (without forming the
  // full 4x4 matrix): v <- sum_i (d_i . v) d_i.
  var vx = 1.0, vy = 1.0, vz = 1.0, vw = 0.0;
  for (var iter = 0; iter < 8; iter++) {
    var ax = 0.0, ay = 0.0, az = 0.0, aw = 0.0;
    for (var i = 0; i < _texelsPerBlock; i++) {
      final dx = texel[i * 4] - mean[0];
      final dy = texel[i * 4 + 1] - mean[1];
      final dz = texel[i * 4 + 2] - mean[2];
      final dw = texel[i * 4 + 3] - mean[3];
      final dot = dx * vx + dy * vy + dz * vz + dw * vw;
      ax += dot * dx;
      ay += dot * dy;
      az += dot * dz;
      aw += dot * dw;
    }
    final len = math.sqrt(ax * ax + ay * ay + az * az + aw * aw);
    if (len < 1e-9) break; // solid block; axis is irrelevant
    vx = ax / len;
    vy = ay / len;
    vz = az / len;
    vw = aw / len;
  }

  // Project onto the axis; endpoints are the extreme projections.
  var minT = double.infinity, maxT = double.negativeInfinity;
  for (var i = 0; i < _texelsPerBlock; i++) {
    final t =
        (texel[i * 4] - mean[0]) * vx +
        (texel[i * 4 + 1] - mean[1]) * vy +
        (texel[i * 4 + 2] - mean[2]) * vz +
        (texel[i * 4 + 3] - mean[3]) * vw;
    if (t < minT) minT = t;
    if (t > maxT) maxT = t;
  }

  final e0 = Float64List(4), e1 = Float64List(4);
  for (var c = 0; c < 4; c++) {
    final axis = [vx, vy, vz, vw][c];
    e0[c] = mean[c] + minT * axis;
    e1[c] = mean[c] + maxT * axis;
  }

  // One least-squares refinement: solve the endpoints that minimize error for
  // the weights chosen against the current endpoints.
  final weights = Int32List(_texelsPerBlock);
  _chooseWeights(texel, e0, e1, weights);
  _refineEndpoints(texel, weights, e0, e1);
  _chooseWeights(texel, e0, e1, weights);

  out[offset] = _round8(e0[0]);
  out[offset + 1] = _round8(e0[1]);
  out[offset + 2] = _round8(e0[2]);
  out[offset + 3] = _round8(e0[3]);
  out[offset + 4] = _round8(e1[0]);
  out[offset + 5] = _round8(e1[1]);
  out[offset + 6] = _round8(e1[2]);
  out[offset + 7] = _round8(e1[3]);
  // Re-pick weights against the quantized endpoints actually stored, so the
  // decoder and encoder agree.
  final q0 = Float64List(4), q1 = Float64List(4);
  for (var c = 0; c < 4; c++) {
    q0[c] = out[offset + c].toDouble();
    q1[c] = out[offset + 4 + c].toDouble();
  }
  _chooseWeights(texel, q0, q1, weights);
  for (var i = 0; i < _texelsPerBlock; i++) {
    final byte = offset + 8 + (i >> 1);
    if (i.isEven) {
      out[byte] = weights[i];
    } else {
      out[byte] |= weights[i] << 4;
    }
  }
}

void _decodeBlock(Uint8List blocks, int offset, Int32List texel) {
  final e0 = [
    blocks[offset],
    blocks[offset + 1],
    blocks[offset + 2],
    blocks[offset + 3],
  ];
  final e1 = [
    blocks[offset + 4],
    blocks[offset + 5],
    blocks[offset + 6],
    blocks[offset + 7],
  ];
  for (var i = 0; i < _texelsPerBlock; i++) {
    final byte = blocks[offset + 8 + (i >> 1)];
    final w = i.isEven ? byte & 0x0F : (byte >> 4) & 0x0F;
    for (var c = 0; c < 4; c++) {
      // Rounded fixed-point lerp: e0 + (e1 - e0) * w / 15.
      final value = e0[c] * (_weightLevels - 1 - w) + e1[c] * w;
      texel[i * 4 + c] =
          (value + (_weightLevels - 1) ~/ 2) ~/ (_weightLevels - 1);
    }
  }
}

/// Picks, per texel, the weight whose reconstruction is closest to the source.
void _chooseWeights(
  Int32List texel,
  Float64List e0,
  Float64List e1,
  Int32List weights,
) {
  for (var i = 0; i < _texelsPerBlock; i++) {
    var bestW = 0;
    var bestErr = double.infinity;
    for (var w = 0; w < _weightLevels; w++) {
      final f = w / (_weightLevels - 1);
      var err = 0.0;
      for (var c = 0; c < 4; c++) {
        final recon = e0[c] + (e1[c] - e0[c]) * f;
        final d = recon - texel[i * 4 + c];
        err += d * d;
      }
      if (err < bestErr) {
        bestErr = err;
        bestW = w;
      }
    }
    weights[i] = bestW;
  }
}

/// Least-squares endpoint fit for fixed weights: minimizes sum over texels of
/// |e0 + (e1 - e0) f_i - color_i|^2 for each channel independently.
void _refineEndpoints(
  Int32List texel,
  Int32List weights,
  Float64List e0,
  Float64List e1,
) {
  var sff = 0.0, sgg = 0.0, sfg = 0.0;
  for (var i = 0; i < _texelsPerBlock; i++) {
    final f = weights[i] / (_weightLevels - 1);
    final g = 1.0 - f;
    sff += f * f;
    sgg += g * g;
    sfg += f * g;
  }
  final det = sgg * sff - sfg * sfg;
  if (det.abs() < 1e-9) return; // all weights equal; keep current endpoints
  for (var c = 0; c < 4; c++) {
    var bf = 0.0, bg = 0.0;
    for (var i = 0; i < _texelsPerBlock; i++) {
      final f = weights[i] / (_weightLevels - 1);
      final g = 1.0 - f;
      final value = texel[i * 4 + c].toDouble();
      bf += f * value;
      bg += g * value;
    }
    // Solve [sgg sfg; sfg sff] [e0; e1] = [bg; bf].
    e0[c] = (sff * bg - sfg * bf) / det;
    e1[c] = (sgg * bf - sfg * bg) / det;
  }
}
