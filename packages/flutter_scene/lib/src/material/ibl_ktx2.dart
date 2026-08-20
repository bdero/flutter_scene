// Reads a pre-baked image-based-lighting cubemap out of a standard KTX2 file
// and lays it out the way the engine's prefiltered radiance expects.
//
// Pure data, no GPU: the parse, the roughness remap, and the atlas conversion
// all run on a background isolate and are testable headless. The upload lives
// in material/environment.dart.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_scene/src/material/diffuse_sh.dart';
import 'package:flutter_scene/src/render/radiance_layout.dart';
import 'package:flutter_scene/src/texture/half_float.dart';
import 'package:flutter_scene/src/texture/ktx2/dfd.dart';
import 'package:flutter_scene/src/texture/ktx2/ktx2.dart';
import 'package:flutter_scene/src/texture/supercompress/zstd.dart';
import 'package:vector_math/vector_math.dart';

// Vulkan formats an environment bake plausibly ships in. Block-compressed and
// Basis payloads are rejected: a GGX-prefiltered radiance chain is HDR, and a
// block codec would quantize it to nothing useful.
const int _vkFormatRgba8Unorm = 37; // VK_FORMAT_R8G8B8A8_UNORM
const int _vkFormatRgba8Srgb = 43; // VK_FORMAT_R8G8B8A8_SRGB
const int _vkFormatRgba16Sfloat = 97; // VK_FORMAT_R16G16B16A16_SFLOAT
const int _vkFormatRgba32Sfloat = 109; // VK_FORMAT_R32G32B32A32_SFLOAT
const int _vkFormatB10g11r11Ufloat = 122; // VK_FORMAT_B10G11R11_UFLOAT_PACK32
const int _vkFormatE5b9g9r9Ufloat = 123; // VK_FORMAT_E5B9G9R9_UFLOAT_PACK32

/// Bytes per texel of each format [decodeKtx2RadianceCube] accepts, or null.
int? _bytesPerTexel(int vkFormat) => switch (vkFormat) {
  _vkFormatRgba8Unorm || _vkFormatRgba8Srgb => 4,
  _vkFormatB10g11r11Ufloat || _vkFormatE5b9g9r9Ufloat => 4,
  _vkFormatRgba16Sfloat => 8,
  _vkFormatRgba32Sfloat => 16,
  _ => null,
};

/// A pre-baked radiance cubemap resampled onto the engine's layout: exactly
/// [kPrefilterBandCount] mip levels of six faces, half-float linear RGBA, ready
/// to upload slice by slice.
class ImportedRadianceCube {
  ImportedRadianceCube({
    required this.baseSize,
    required this.mips,
    this.diffuseSphericalHarmonics,
  });

  /// Face size of mip 0. Mip `i` is `baseSize >> i`.
  final int baseSize;

  /// `mips[level][face]` half-float RGBA texels, faces in KTX2/cube slice order
  /// (+X, -X, +Y, -Y, +Z, -Z).
  final List<List<Uint16List>> mips;

  /// Coefficients read from the file's [kDiffuseShKtx2Key] metadata, or null
  /// when it carries none.
  final List<Vector3>? diffuseSphericalHarmonics;
}

/// A pre-baked radiance cubemap flattened onto the legacy stacked-band
/// equirect atlas, for backends that cannot sample a mip chain.
class ImportedRadianceAtlas {
  ImportedRadianceAtlas({
    required this.width,
    required this.height,
    required this.pixels,
    this.diffuseSphericalHarmonics,
  });

  final int width;
  final int height;

  /// Half-float linear RGBA texels, row-major, band `b` occupying rows
  /// `[b * kPrefilterBandHeight, (b + 1) * kPrefilterBandHeight)`.
  final Uint16List pixels;

  /// See [ImportedRadianceCube.diffuseSphericalHarmonics].
  final List<Vector3>? diffuseSphericalHarmonics;
}

/// One decoded mip level: six faces of linear RGBA float texels.
typedef _RadianceLevel = ({int size, List<Float32List> faces});

/// Decodes a KTX2 cubemap whose mip chain is a GGX-prefiltered roughness
/// series into the engine's radiance cube layout.
///
/// Throws [Ktx2FormatException] for anything that is not a usable environment
/// file. See `EnvironmentMap.fromKtx2Bytes` for the accepted conventions.
ImportedRadianceCube decodeKtx2RadianceCube(Uint8List bytes) {
  final texture = readKtx2(bytes);
  final levels = _decodeLevels(texture);
  final baseSize = levels.first.size;
  final mips = <List<Uint16List>>[];
  for (var band = 0; band < kPrefilterBandCount; band++) {
    final resampled = _resampleBand(levels, band, baseSize >> band);
    mips.add([for (final face in resampled) floatPixelsToHalf(face)]);
  }
  return ImportedRadianceCube(
    baseSize: baseSize,
    mips: mips,
    diffuseSphericalHarmonics: _shFromKeyValues(texture),
  );
}

/// Decodes a KTX2 cubemap (see [decodeKtx2RadianceCube]) and flattens it onto
/// the legacy stacked-band equirect atlas, resampling each roughness band
/// through the engine's equirect projection.
ImportedRadianceAtlas decodeKtx2RadianceAtlas(Uint8List bytes) {
  final texture = readKtx2(bytes);
  final levels = _decodeLevels(texture);
  const width = kPrefilterBandWidth;
  const bandHeight = kPrefilterBandHeight;
  const height = bandHeight * kPrefilterBandCount;
  final pixels = Uint16List(width * height * 4);
  for (var band = 0; band < kPrefilterBandCount; band++) {
    final size = math.max(1, levels.first.size >> band);
    final faces = _resampleBand(levels, band, size);
    for (var y = 0; y < bandHeight; y++) {
      for (var x = 0; x < width; x++) {
        final direction = equirectUvToDirection(
          (x + 0.5) / width,
          (y + 0.5) / bandHeight,
        );
        final coords = radianceCubeFaceCoords(direction);
        final rgba = _sampleFaceBilinear(
          faces[coords.face],
          size,
          coords.u,
          coords.v,
        );
        final o = ((band * bandHeight + y) * width + x) * 4;
        for (var c = 0; c < 4; c++) {
          pixels[o + c] = floatToHalfBits(rgba[c]);
        }
      }
    }
  }
  return ImportedRadianceAtlas(
    width: width,
    height: height,
    pixels: pixels,
    diffuseSphericalHarmonics: _shFromKeyValues(texture),
  );
}

/// Reads diffuse spherical harmonics out of a KTX2 file's key/value metadata,
/// or null when the file carries none.
List<Vector3>? readKtx2DiffuseSh(Uint8List bytes) =>
    _shFromKeyValues(readKtx2(bytes));

List<Vector3>? _shFromKeyValues(Ktx2Texture texture) {
  final value = texture.keyValues[kDiffuseShKtx2Key];
  if (value == null) return null;
  try {
    return parseDiffuseShSidecar(Uint8List.fromList(value));
  } on FormatException catch (e) {
    throw Ktx2FormatException('Bad $kDiffuseShKtx2Key metadata: ${e.message}');
  }
}

/// Validates the header and decodes every stored level to linear RGBA floats.
List<_RadianceLevel> _decodeLevels(Ktx2Texture texture) {
  if (texture.faceCount != 6) {
    throw Ktx2FormatException(
      'Environment KTX2 must be a cubemap (faceCount 6), got '
      '${texture.faceCount}',
    );
  }
  if (texture.layerCount > 1 || texture.pixelDepth > 1) {
    // TODO(ibl-cube-array): a cube array would let one file carry several
    // probes; it needs per-layer slicing here and a layered GPU texture.
    throw Ktx2FormatException(
      'Cube array and 3D environment files are not '
      'supported',
    );
  }
  final size = texture.pixelWidth;
  final height = math.max(1, texture.pixelHeight);
  if (size != height) {
    throw Ktx2FormatException('Cube faces must be square, got ${size}x$height');
  }
  if (size < kMinRadianceCubeSize) {
    // TODO(ibl-small-cube): a smaller bake could be accepted by upsampling the
    // base level, at the cost of inventing detail; today the requirement is
    // stated rather than papered over.
    throw Ktx2FormatException(
      'Environment cube faces must be at least '
      '${kMinRadianceCubeSize}x$kMinRadianceCubeSize to hold '
      '$kPrefilterBandCount roughness mips, got ${size}x$size',
    );
  }
  if (size > 8192 || (size & (size - 1)) != 0) {
    throw Ktx2FormatException('Face size $size must be a power of two <= 8192');
  }
  final bytesPerTexel = _bytesPerTexel(texture.vkFormat);
  if (bytesPerTexel == null) {
    throw Ktx2FormatException(
      'Unsupported environment format vkFormat ${texture.vkFormat}; use an '
      'uncompressed float, shared-exponent, or rgba8 cubemap',
    );
  }
  final srgb = texture.vkFormat == _vkFormatRgba8Srgb || _dfdSaysSrgb(texture);

  final levels = <_RadianceLevel>[];
  for (var level = 0; level < texture.levels.length; level++) {
    final levelSize = math.max(1, size >> level);
    final faceBytes = levelSize * levelSize * bytesPerTexel;
    final payload = _levelPayload(texture, level, faceBytes * 6);
    levels.add((
      size: levelSize,
      faces: [
        for (var face = 0; face < 6; face++)
          _decodeFace(
            Uint8List.sublistView(
              payload,
              face * faceBytes,
              (face + 1) * faceBytes,
            ),
            levelSize,
            texture.vkFormat,
            srgb,
          ),
      ],
    ));
  }
  return levels;
}

bool _dfdSaysSrgb(Ktx2Texture texture) {
  try {
    return readDataFormat(texture).isSrgb;
  } on Ktx2FormatException {
    return false;
  }
}

/// A level's decompressed bytes, undoing container supercompression.
Uint8List _levelPayload(Ktx2Texture texture, int level, int expectedBytes) {
  final stored = texture.levels[level].data;
  final Uint8List raw;
  switch (texture.supercompression) {
    case Ktx2Supercompression.none:
      raw = stored;
    case Ktx2Supercompression.zstandard:
      raw = zstdDecompress(
        stored,
        texture.levels[level].uncompressedByteLength,
      );
    case Ktx2Supercompression.zlib:
    case Ktx2Supercompression.basisLz:
      // TODO(ibl-zlib): zlib supercompression needs an inflate; zstd is what
      // the Khronos IBL tooling emits, so it is the one that ships.
      throw Ktx2FormatException(
        'Unsupported environment supercompression '
        '${texture.supercompression.name}',
      );
  }
  if (raw.length < expectedBytes) {
    throw Ktx2FormatException(
      'Level $level holds ${raw.length} bytes, expected $expectedBytes',
    );
  }
  return raw;
}

/// Decodes one face's texels to linear RGBA floats.
Float32List _decodeFace(Uint8List bytes, int size, int vkFormat, bool srgb) {
  final texels = size * size;
  final out = Float32List(texels * 4);
  final data = ByteData.sublistView(bytes);
  switch (vkFormat) {
    case _vkFormatRgba8Unorm:
    case _vkFormatRgba8Srgb:
      for (var i = 0; i < texels; i++) {
        for (var c = 0; c < 3; c++) {
          final v = bytes[i * 4 + c] / 255.0;
          out[i * 4 + c] = srgb ? _srgbToLinear(v) : v;
        }
        out[i * 4 + 3] = bytes[i * 4 + 3] / 255.0;
      }
    case _vkFormatRgba16Sfloat:
      for (var i = 0; i < texels * 4; i++) {
        out[i] = halfBitsToDouble(data.getUint16(i * 2, Endian.little));
      }
    case _vkFormatRgba32Sfloat:
      for (var i = 0; i < texels * 4; i++) {
        out[i] = data.getFloat32(i * 4, Endian.little);
      }
    case _vkFormatE5b9g9r9Ufloat:
      for (var i = 0; i < texels; i++) {
        _decodeRgb9e5(data.getUint32(i * 4, Endian.little), out, i * 4);
        out[i * 4 + 3] = 1.0;
      }
    case _vkFormatB10g11r11Ufloat:
      for (var i = 0; i < texels; i++) {
        _decodeR11g11b10(data.getUint32(i * 4, Endian.little), out, i * 4);
        out[i * 4 + 3] = 1.0;
      }
  }
  for (var i = 0; i < out.length; i++) {
    if (!out[i].isFinite) out[i] = 0.0;
  }
  return out;
}

double _srgbToLinear(double c) =>
    c <= 0.04045 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();

/// Unpacks a shared-exponent RGB9E5 word. The 5-bit exponent is biased by 15
/// and the mantissas are 9-bit unsigned, so the value is `m * 2^(e - 24)`. The
/// shifts stay under 32 bits, which dart2js needs.
void _decodeRgb9e5(int word, Float32List out, int offset) {
  final exponent = (word >>> 27) & 0x1f;
  final scale = math.pow(2.0, exponent - 24).toDouble();
  out[offset] = (word & 0x1ff) * scale;
  out[offset + 1] = ((word >>> 9) & 0x1ff) * scale;
  out[offset + 2] = ((word >>> 18) & 0x1ff) * scale;
}

/// Unpacks a packed B10G11R11 word: unsigned 11/11/10-bit floats with 5-bit
/// exponents, R in the low bits.
void _decodeR11g11b10(int word, Float32List out, int offset) {
  out[offset] = _unsignedFloat(word & 0x7ff, 6);
  out[offset + 1] = _unsignedFloat((word >>> 11) & 0x7ff, 6);
  out[offset + 2] = _unsignedFloat((word >>> 22) & 0x3ff, 5);
}

/// Decodes an unsigned float with a 5-bit exponent (bias 15) and
/// [mantissaBits] of mantissa.
double _unsignedFloat(int bits, int mantissaBits) {
  final mantissaMask = (1 << mantissaBits) - 1;
  final exponent = bits >>> mantissaBits;
  final mantissa = bits & mantissaMask;
  final unit = 1 << mantissaBits;
  if (exponent == 0) {
    return mantissa / unit * math.pow(2.0, -14).toDouble();
  }
  if (exponent == 0x1f) return mantissa == 0 ? double.infinity : double.nan;
  return (unit + mantissa) / unit * math.pow(2.0, exponent - 15).toDouble();
}

/// Resamples the source chain onto engine roughness band [band] at face size
/// [size].
///
/// The source's own convention is linear roughness per level
/// (`roughness = level / (levelCount - 1)`), so a chain with exactly
/// [kPrefilterBandCount] levels maps one-to-one. Any other length is
/// interpolated between the two source levels bracketing the band's roughness,
/// each box-resampled to the band's face size first.
List<Float32List> _resampleBand(
  List<_RadianceLevel> levels,
  int band,
  int size,
) {
  final faceSize = math.max(1, size);
  final position = radianceBandRoughness(band) * (levels.length - 1);
  final low = position.floor().clamp(0, levels.length - 1);
  final high = math.min(low + 1, levels.length - 1);
  final t = position - low;
  final lowFaces = [
    for (final face in levels[low].faces)
      _resampleFace(face, levels[low].size, faceSize),
  ];
  if (t <= 0.0 || high == low) return lowFaces;
  final highFaces = [
    for (final face in levels[high].faces)
      _resampleFace(face, levels[high].size, faceSize),
  ];
  for (var face = 0; face < lowFaces.length; face++) {
    final a = lowFaces[face];
    final b = highFaces[face];
    for (var i = 0; i < a.length; i++) {
      a[i] = a[i] + (b[i] - a[i]) * t;
    }
  }
  return lowFaces;
}

/// Box-resamples a square RGBA float face from [from] to [to] texels a side.
/// Downsampling averages the covered source texels; upsampling reads the
/// nearest source texel bilinearly.
Float32List _resampleFace(Float32List face, int from, int to) {
  if (from == to) return Float32List.fromList(face);
  final out = Float32List(to * to * 4);
  if (to < from) {
    final step = from ~/ to;
    final inverse = 1.0 / (step * step);
    for (var y = 0; y < to; y++) {
      for (var x = 0; x < to; x++) {
        final o = (y * to + x) * 4;
        for (var sy = 0; sy < step; sy++) {
          final row = (y * step + sy) * from;
          for (var sx = 0; sx < step; sx++) {
            final s = (row + x * step + sx) * 4;
            for (var c = 0; c < 4; c++) {
              out[o + c] += face[s + c];
            }
          }
        }
        for (var c = 0; c < 4; c++) {
          out[o + c] *= inverse;
        }
      }
    }
    return out;
  }
  for (var y = 0; y < to; y++) {
    for (var x = 0; x < to; x++) {
      final rgba = _sampleFaceBilinear(
        face,
        from,
        (x + 0.5) / to,
        (y + 0.5) / to,
      );
      final o = (y * to + x) * 4;
      for (var c = 0; c < 4; c++) {
        out[o + c] = rgba[c];
      }
    }
  }
  return out;
}

/// Bilinearly samples a square RGBA float [face] of [size] texels a side at
/// ([u], [v]) in `[0, 1]`, clamping at the edges.
Float32List _sampleFaceBilinear(
  Float32List face,
  int size,
  double u,
  double v,
) {
  final fx = (u * size - 0.5).clamp(0.0, size - 1.0);
  final fy = (v * size - 0.5).clamp(0.0, size - 1.0);
  final x0 = fx.floor();
  final y0 = fy.floor();
  final x1 = math.min(x0 + 1, size - 1);
  final y1 = math.min(y0 + 1, size - 1);
  final tx = fx - x0;
  final ty = fy - y0;
  final i00 = (y0 * size + x0) * 4;
  final i01 = (y0 * size + x1) * 4;
  final i10 = (y1 * size + x0) * 4;
  final i11 = (y1 * size + x1) * 4;
  final out = Float32List(4);
  for (var c = 0; c < 4; c++) {
    final top = face[i00 + c] + (face[i01 + c] - face[i00 + c]) * tx;
    final bottom = face[i10 + c] + (face[i11 + c] - face[i10 + c]) * tx;
    out[c] = top + (bottom - top) * ty;
  }
  return out;
}
