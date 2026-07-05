import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_scene/src/splats/splat_data.dart';

/// The splat file formats the runtime loader understands.
/// {@category Geometry}
enum SplatFormat {
  /// An uncompressed Gaussian-splat PLY (binary little-endian), the training
  /// interchange layout: `x y z ... f_dc_* f_rest_* opacity scale_* rot_*`.
  ply,

  /// The compact 32-byte-per-splat `.splat` layout common in web pipelines:
  /// float position and scale, 8-bit color/opacity, 8-bit quaternion.
  splat,
}

/// Options applied while decoding a splat file.
class SplatDecodeOptions {
  const SplatDecodeOptions({
    this.alphaCullThreshold = 1.0 / 255.0,
    this.maxShDegree = 2,
  });

  /// Splats whose decoded opacity falls below this are dropped at load.
  final double alphaCullThreshold;

  /// The highest spherical-harmonic degree to keep (0 to 2). Coefficients
  /// beyond it are discarded at load, saving GPU memory.
  final int maxShDegree;
}

/// A decoded splat set together with its GPU-ready texel arrays.
///
/// Produced by [decodeSplats] (usually on a background isolate); consumed by
/// `GaussianSplats`, which uploads the texel arrays verbatim.
class PackedSplats {
  PackedSplats({
    required this.data,
    required this.paramsTexels,
    required this.paramsWidth,
    required this.paramsHeight,
    this.shTexels,
    this.shWidth = 0,
    this.shHeight = 0,
    this.shStride = 0,
  });

  /// The decoded splat arrays (kept for sorting, bounds, and readback).
  final SplatData data;

  /// RGBA32F texels for the parameter texture, [kParamsTexelsPerSplat]
  /// consecutive texels per splat:
  /// `pos.xyz, opacity | cov.xx,xy,xz,yy | cov.yz,zz,0,0 | color.rgb, 0`.
  final Float32List paramsTexels;

  /// Parameter texture dimensions. The width is a power of two so the
  /// per-splat texel groups never straddle a row.
  final int paramsWidth;
  final int paramsHeight;

  /// RGBA32F texels for the rest-SH texture ([shStride] texels per splat,
  /// one coefficient's `r, g, b` per texel), or null when the set carries
  /// no rest coefficients.
  final Float32List? shTexels;
  final int shWidth;
  final int shHeight;

  /// Texels per splat in the SH texture (4 for degree 1, 8 for degree 2;
  /// a power of two so groups never straddle rows).
  final int shStride;
}

/// Texels per splat in the parameter texture.
const int kParamsTexelsPerSplat = 4;

/// The widest data texture the packer will emit. 4096 is universally
/// supported by the backends flutter_scene ships on.
const int kMaxSplatTextureWidth = 4096;

/// The degree-0 spherical-harmonic basis constant.
const double kShC0 = 0.28209479177387814;

/// Decodes [bytes] as [format] and packs the result into GPU-ready texel
/// arrays. Pure and allocation-only, so it can run on a background isolate
/// (`compute`).
PackedSplats decodeSplats(
  Uint8List bytes,
  SplatFormat format, {
  SplatDecodeOptions options = const SplatDecodeOptions(),
}) {
  final data = switch (format) {
    SplatFormat.ply => parseSplatPly(bytes, options: options),
    SplatFormat.splat => parseSplatFile(bytes, options: options),
  };
  return packSplats(data);
}

/// The top-level `compute` entry point for [decodeSplats].
PackedSplats decodeSplatsForIsolate(
  ({
    Uint8List bytes,
    SplatFormat format,
    double alphaCullThreshold,
    int maxShDegree,
  })
  args,
) {
  return decodeSplats(
    args.bytes,
    args.format,
    options: SplatDecodeOptions(
      alphaCullThreshold: args.alphaCullThreshold,
      maxShDegree: args.maxShDegree,
    ),
  );
}

/// Parses a binary little-endian Gaussian-splat PLY.
///
/// Recognizes the training layout's properties by name (`x`, `f_dc_0`,
/// `f_rest_*`, `opacity`, `scale_*`, `rot_*`); other float properties are
/// skipped by stride. Applies the training-space transforms: `exp` on
/// scales, sigmoid on opacity, `0.5 + C0 * f_dc` on the base color, and
/// quaternion normalization.
SplatData parseSplatPly(
  Uint8List bytes, {
  SplatDecodeOptions options = const SplatDecodeOptions(),
}) {
  final header = _parsePlyHeader(bytes);
  final props = header.properties;

  int require(String name) {
    final offset = props[name];
    if (offset == null) {
      throw FormatException('Splat PLY is missing property "$name".');
    }
    return offset;
  }

  final xOff = require('x'), yOff = require('y'), zOff = require('z');
  final dc0 = require('f_dc_0'),
      dc1 = require('f_dc_1'),
      dc2 = require('f_dc_2');
  final opacityOff = require('opacity');
  final s0 = require('scale_0'),
      s1 = require('scale_1'),
      s2 = require('scale_2');
  final r0 = require('rot_0'),
      r1 = require('rot_1'),
      r2 = require('rot_2'),
      r3 = require('rot_3');

  // The f_rest count determines the file's SH degree. The PLY stores rest
  // coefficients channel-major (all R coefficients, then G, then B).
  var fileRest = 0;
  while (props.containsKey('f_rest_$fileRest')) {
    fileRest++;
  }
  final restPerChannel = fileRest ~/ 3;
  final fileDegree = switch (restPerChannel) {
    0 => 0,
    3 => 1,
    8 => 2,
    15 => 3,
    _ => throw FormatException(
      'Splat PLY has an unexpected f_rest count ($fileRest).',
    ),
  };
  final degree = math.min(math.min(fileDegree, options.maxShDegree), 2);
  final keptRest = SplatData.shRestCoeffCount(degree);

  final stride = header.strideInBytes;
  final view = ByteData.sublistView(bytes, header.dataOffset);
  final total = header.vertexCount;
  if (view.lengthInBytes < total * stride) {
    throw FormatException('Splat PLY is truncated.');
  }

  // First pass: count survivors of the alpha cull so the arrays allocate
  // exactly once.
  var kept = 0;
  for (var i = 0; i < total; i++) {
    final op = _sigmoid(
      view.getFloat32(i * stride + opacityOff, Endian.little),
    );
    if (op >= options.alphaCullThreshold) kept++;
  }

  final out = SplatData.zeroed(kept, shDegree: degree);
  final sh = out.sh;
  final restBase = sh != null ? require('f_rest_0') : 0;
  var w = 0;
  for (var i = 0; i < total; i++) {
    final base = i * stride;
    final opacity = _sigmoid(view.getFloat32(base + opacityOff, Endian.little));
    if (opacity < options.alphaCullThreshold) continue;

    final p = w * 3;
    out.positions[p] = view.getFloat32(base + xOff, Endian.little);
    out.positions[p + 1] = view.getFloat32(base + yOff, Endian.little);
    out.positions[p + 2] = view.getFloat32(base + zOff, Endian.little);

    out.scales[p] = math.exp(view.getFloat32(base + s0, Endian.little));
    out.scales[p + 1] = math.exp(view.getFloat32(base + s1, Endian.little));
    out.scales[p + 2] = math.exp(view.getFloat32(base + s2, Endian.little));

    out.colors[p] = 0.5 + kShC0 * view.getFloat32(base + dc0, Endian.little);
    out.colors[p + 1] =
        0.5 + kShC0 * view.getFloat32(base + dc1, Endian.little);
    out.colors[p + 2] =
        0.5 + kShC0 * view.getFloat32(base + dc2, Endian.little);

    // rot_0 is the scalar (w) in the training layout; store x, y, z, w.
    final qw = view.getFloat32(base + r0, Endian.little);
    final qx = view.getFloat32(base + r1, Endian.little);
    final qy = view.getFloat32(base + r2, Endian.little);
    final qz = view.getFloat32(base + r3, Endian.little);
    final qn = math.sqrt(qw * qw + qx * qx + qy * qy + qz * qz);
    final inv = qn > 0 ? 1.0 / qn : 0.0;
    final q = w * 4;
    out.rotations[q] = qx * inv;
    out.rotations[q + 1] = qy * inv;
    out.rotations[q + 2] = qz * inv;
    out.rotations[q + 3] = qw * inv;

    out.opacities[w] = opacity;

    if (sh != null) {
      final shOut = w * keptRest * 3;
      for (var c = 0; c < keptRest; c++) {
        for (var ch = 0; ch < 3; ch++) {
          // Channel-major in the file: coefficient c of channel ch is at
          // rest index ch * restPerChannel + c.
          sh[shOut + c * 3 + ch] = view.getFloat32(
            base + restBase + (ch * restPerChannel + c) * 4,
            Endian.little,
          );
        }
      }
    }
    w++;
  }
  return out;
}

/// Parses the 32-byte-per-splat `.splat` layout.
///
/// Colors and opacity are 8-bit (color already includes the degree-0 SH
/// term); the quaternion is 8-bit with the scalar first, matching the
/// training PLY's `rot_*` order. The format carries no rest SH.
SplatData parseSplatFile(
  Uint8List bytes, {
  SplatDecodeOptions options = const SplatDecodeOptions(),
}) {
  const stride = 32;
  if (bytes.length % stride != 0) {
    throw FormatException('.splat data length is not a multiple of 32.');
  }
  final total = bytes.length ~/ stride;
  final view = ByteData.sublistView(bytes);

  var kept = 0;
  for (var i = 0; i < total; i++) {
    if (bytes[i * stride + 27] / 255.0 >= options.alphaCullThreshold) kept++;
  }

  final out = SplatData.zeroed(kept);
  var w = 0;
  for (var i = 0; i < total; i++) {
    final base = i * stride;
    final opacity = bytes[base + 27] / 255.0;
    if (opacity < options.alphaCullThreshold) continue;

    final p = w * 3;
    out.positions[p] = view.getFloat32(base, Endian.little);
    out.positions[p + 1] = view.getFloat32(base + 4, Endian.little);
    out.positions[p + 2] = view.getFloat32(base + 8, Endian.little);
    out.scales[p] = view.getFloat32(base + 12, Endian.little);
    out.scales[p + 1] = view.getFloat32(base + 16, Endian.little);
    out.scales[p + 2] = view.getFloat32(base + 20, Endian.little);
    out.colors[p] = bytes[base + 24] / 255.0;
    out.colors[p + 1] = bytes[base + 25] / 255.0;
    out.colors[p + 2] = bytes[base + 26] / 255.0;
    out.opacities[w] = opacity;

    final qw = (bytes[base + 28] - 128) / 128.0;
    final qx = (bytes[base + 29] - 128) / 128.0;
    final qy = (bytes[base + 30] - 128) / 128.0;
    final qz = (bytes[base + 31] - 128) / 128.0;
    final qn = math.sqrt(qw * qw + qx * qx + qy * qy + qz * qz);
    final inv = qn > 0 ? 1.0 / qn : 0.0;
    final q = w * 4;
    out.rotations[q] = qx * inv;
    out.rotations[q + 1] = qy * inv;
    out.rotations[q + 2] = qz * inv;
    out.rotations[q + 3] = qw * inv;
    w++;
  }
  return out;
}

/// Packs [data] into the RGBA32F texel arrays the splat shaders fetch.
///
/// The 3D covariance is precomputed here (`M = R * S`, `Sigma = M * Mt`) so
/// the vertex shader fetches six floats instead of rebuilding it from the
/// quaternion and scales per vertex.
PackedSplats packSplats(SplatData data) {
  final count = data.count;
  final paramsWidth = _textureWidthFor(count * kParamsTexelsPerSplat);
  final paramsHeight = math.max(
    1,
    ((count * kParamsTexelsPerSplat) / paramsWidth).ceil(),
  );
  _checkTextureHeight(paramsHeight, 'parameter');
  final params = Float32List(paramsWidth * paramsHeight * 4);

  for (var i = 0; i < count; i++) {
    final p = i * 3, q = i * 4;
    final sx = data.scales[p], sy = data.scales[p + 1], sz = data.scales[p + 2];
    final x = data.rotations[q],
        y = data.rotations[q + 1],
        z = data.rotations[q + 2],
        w = data.rotations[q + 3];

    // Rotation matrix from the unit quaternion, columns scaled by S.
    final m00 = (1 - 2 * (y * y + z * z)) * sx;
    final m01 = (2 * (x * y - w * z)) * sy;
    final m02 = (2 * (x * z + w * y)) * sz;
    final m10 = (2 * (x * y + w * z)) * sx;
    final m11 = (1 - 2 * (x * x + z * z)) * sy;
    final m12 = (2 * (y * z - w * x)) * sz;
    final m20 = (2 * (x * z - w * y)) * sx;
    final m21 = (2 * (y * z + w * x)) * sy;
    final m22 = (1 - 2 * (x * x + y * y)) * sz;

    final covXX = m00 * m00 + m01 * m01 + m02 * m02;
    final covXY = m00 * m10 + m01 * m11 + m02 * m12;
    final covXZ = m00 * m20 + m01 * m21 + m02 * m22;
    final covYY = m10 * m10 + m11 * m11 + m12 * m12;
    final covYZ = m10 * m20 + m11 * m21 + m12 * m22;
    final covZZ = m20 * m20 + m21 * m21 + m22 * m22;

    final o = i * kParamsTexelsPerSplat * 4;
    params[o] = data.positions[p];
    params[o + 1] = data.positions[p + 1];
    params[o + 2] = data.positions[p + 2];
    params[o + 3] = data.opacities[i];
    params[o + 4] = covXX;
    params[o + 5] = covXY;
    params[o + 6] = covXZ;
    params[o + 7] = covYY;
    params[o + 8] = covYZ;
    params[o + 9] = covZZ;
    // o+10, o+11 reserved.
    params[o + 12] = data.colors[p];
    params[o + 13] = data.colors[p + 1];
    params[o + 14] = data.colors[p + 2];
    // o+15 reserved.
  }

  Float32List? shTexels;
  var shWidth = 0, shHeight = 0, shStride = 0;
  final sh = data.sh;
  if (sh != null && data.shDegree > 0) {
    final coeffs = SplatData.shRestCoeffCount(data.shDegree);
    // Pad the per-splat group to a power of two so groups never straddle a
    // row of the power-of-two-wide texture.
    shStride = coeffs <= 4 ? 4 : 8;
    shWidth = _textureWidthFor(count * shStride);
    shHeight = math.max(1, ((count * shStride) / shWidth).ceil());
    _checkTextureHeight(shHeight, 'spherical-harmonics');
    shTexels = Float32List(shWidth * shHeight * 4);
    for (var i = 0; i < count; i++) {
      final src = i * coeffs * 3;
      final dst = i * shStride * 4;
      for (var c = 0; c < coeffs; c++) {
        shTexels[dst + c * 4] = sh[src + c * 3];
        shTexels[dst + c * 4 + 1] = sh[src + c * 3 + 1];
        shTexels[dst + c * 4 + 2] = sh[src + c * 3 + 2];
      }
    }
  }

  return PackedSplats(
    data: data,
    paramsTexels: params,
    paramsWidth: paramsWidth,
    paramsHeight: paramsHeight,
    shTexels: shTexels,
    shWidth: shWidth,
    shHeight: shHeight,
    shStride: shStride,
  );
}

/// Sniffs [bytes] for a PLY magic, falling back to [fallback].
SplatFormat sniffSplatFormat(Uint8List bytes, {SplatFormat? fallback}) {
  if (bytes.length >= 4 &&
      bytes[0] == 0x70 && // p
      bytes[1] == 0x6C && // l
      bytes[2] == 0x79 && // y
      (bytes[3] == 0x0A || bytes[3] == 0x0D)) {
    return SplatFormat.ply;
  }
  return fallback ?? SplatFormat.splat;
}

double _sigmoid(double x) => 1.0 / (1.0 + math.exp(-x));

/// The smallest power-of-two width (at least 4, at most
/// [kMaxSplatTextureWidth]) that keeps the texture roughly square.
int _textureWidthFor(int texels) {
  var width = 4;
  while (width < kMaxSplatTextureWidth && width * width < texels) {
    width *= 2;
  }
  return width;
}

void _checkTextureHeight(int height, String label) {
  if (height > kMaxSplatTextureWidth) {
    // TODO(splats): split giant sets across multiple textures instead of
    // rejecting them; 4096x4096 holds ~4.2M splats per texture today.
    throw ArgumentError(
      'Splat set is too large for one $label texture '
      '(height $height exceeds $kMaxSplatTextureWidth rows).',
    );
  }
}

class _PlyHeader {
  _PlyHeader({
    required this.vertexCount,
    required this.strideInBytes,
    required this.dataOffset,
    required this.properties,
  });

  final int vertexCount;
  final int strideInBytes;
  final int dataOffset;

  /// Byte offset of each float property within a vertex record.
  final Map<String, int> properties;
}

_PlyHeader _parsePlyHeader(Uint8List bytes) {
  // The header is ASCII, terminated by "end_header\n".
  final headerEnd = _indexOfSequence(bytes, 'end_header\n'.codeUnits);
  if (headerEnd < 0) {
    throw FormatException('PLY header is missing end_header.');
  }
  final dataOffset = headerEnd + 'end_header\n'.length;
  final header = String.fromCharCodes(bytes.sublist(0, headerEnd));
  final lines = header.split(RegExp(r'\r?\n'));

  if (lines.isEmpty || lines.first.trim() != 'ply') {
    throw FormatException('Not a PLY file.');
  }

  var vertexCount = -1;
  var inVertexElement = false;
  var stride = 0;
  final properties = <String, int>{};
  var sawFormat = false;

  const sizes = {
    'float': 4,
    'float32': 4,
    'double': 8,
    'float64': 8,
    'char': 1,
    'int8': 1,
    'uchar': 1,
    'uint8': 1,
    'short': 2,
    'int16': 2,
    'ushort': 2,
    'uint16': 2,
    'int': 4,
    'int32': 4,
    'uint': 4,
    'uint32': 4,
  };

  for (final raw in lines.skip(1)) {
    final line = raw.trim();
    if (line.isEmpty || line.startsWith('comment')) continue;
    final parts = line.split(RegExp(r'\s+'));
    switch (parts[0]) {
      case 'format':
        if (parts.length < 2 || parts[1] != 'binary_little_endian') {
          throw FormatException(
            'Only binary little-endian splat PLYs are supported '
            '(got "${parts.length > 1 ? parts[1] : ''}").',
          );
        }
        sawFormat = true;
      case 'element':
        inVertexElement = parts.length >= 3 && parts[1] == 'vertex';
        if (inVertexElement) {
          vertexCount = int.parse(parts[2]);
        } else if (vertexCount >= 0) {
          // Properties of a later element would corrupt the stride; the
          // vertex element must come first (it does in training output).
          break;
        }
      case 'property':
        if (!inVertexElement) continue;
        if (parts[1] == 'list') {
          throw FormatException('List properties are not supported.');
        }
        final size = sizes[parts[1]];
        if (size == null) {
          throw FormatException('Unknown PLY property type "${parts[1]}".');
        }
        if (size == 4 && (parts[1] == 'float' || parts[1] == 'float32')) {
          properties[parts[2]] = stride;
        }
        stride += size;
    }
  }
  if (!sawFormat || vertexCount < 0) {
    throw FormatException('PLY header is missing format or vertex element.');
  }
  return _PlyHeader(
    vertexCount: vertexCount,
    strideInBytes: stride,
    dataOffset: dataOffset,
    properties: properties,
  );
}

int _indexOfSequence(Uint8List haystack, List<int> needle) {
  final limit = math.min(haystack.length - needle.length, 64 * 1024);
  outer:
  for (var i = 0; i <= limit; i++) {
    for (var j = 0; j < needle.length; j++) {
      if (haystack[i + j] != needle[j]) continue outer;
    }
    return i;
  }
  return -1;
}
