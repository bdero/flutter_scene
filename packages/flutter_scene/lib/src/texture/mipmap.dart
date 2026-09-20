import 'dart:math' as math;
import 'dart:typed_data';

/// What a texture's pixels represent, which controls how mip levels are
/// downsampled so the result is correct (color must average in linear light,
/// normals must be averaged as vectors and renormalized).
///
/// {@category Assets and loading}
enum TextureContent {
  /// sRGB-encoded color (albedo, emissive). Averaged in linear light.
  color,

  /// Linear data (metallic-roughness, ambient occlusion). Averaged directly.
  data,

  /// A tangent-space normal map. Averaged as vectors and renormalized.
  normal,
}

/// The [TextureContent] named [name] (a serialized `TextureResource.content`),
/// falling back to [TextureContent.color] for an unknown name.
TextureContent textureContentFromName(String name) => switch (name) {
  'data' => TextureContent.data,
  'normal' => TextureContent.normal,
  _ => TextureContent.color,
};

/// One mip level's RGBA8888 pixels.
class MipLevel {
  MipLevel(this.width, this.height, this.pixels);

  final int width;
  final int height;
  final Uint8List pixels;
}

/// Builds the full mip chain (level 0 first) for RGBA8888 [pixels] of [width] x
/// [height], downsampling with a 2x2 box filter appropriate for [content].
///
/// Each level halves the previous (floored, min 1) until 1x1. The result is
/// suitable for uploading level by level to a mipmapped texture.
List<MipLevel> generateMipChain(
  Uint8List pixels,
  int width,
  int height,
  TextureContent content,
) {
  final levels = <MipLevel>[MipLevel(width, height, pixels)];
  var w = width;
  var h = height;
  var src = pixels;
  while (w > 1 || h > 1) {
    final nw = math.max(1, w >> 1);
    final nh = math.max(1, h >> 1);
    final dst = _downsample(src, w, h, nw, nh, content);
    levels.add(MipLevel(nw, nh, dst));
    src = dst;
    w = nw;
    h = nh;
  }
  return levels;
}

/// The number of mip levels for a [width] x [height] texture.
int mipLevelCountFor(int width, int height) =>
    (math.log(math.max(width, height)) / math.ln2).floor() + 1;

Uint8List _downsample(
  Uint8List src,
  int sw,
  int sh,
  int dw,
  int dh,
  TextureContent content,
) {
  final dst = Uint8List(dw * dh * 4);
  // The content switch is hoisted out of the per-texel loop: a mip chain of a
  // 2048x2048 texture walks ~1.4 M destination texels, so anything left inside
  // is paid a million times over.
  switch (content) {
    case TextureContent.color:
      _downsampleColor(src, sw, sh, dw, dh, dst);
    case TextureContent.data:
      _downsampleData(src, sw, sh, dw, dh, dst);
    case TextureContent.normal:
      _downsampleNormal(src, sw, sh, dw, dh, dst);
  }
  return dst;
}

// The first of the two source coordinates a destination coordinate covers,
// clamped to the source extent for an odd-sized level.
@pragma('vm:prefer-inline')
int _clampDouble(int coordinate, int extent) {
  final doubled = coordinate * 2;
  return doubled < extent ? doubled : extent - 1;
}

void _downsampleColor(
  Uint8List src,
  int sw,
  int sh,
  int dw,
  int dh,
  Uint8List dst,
) {
  for (var y = 0; y < dh; y++) {
    final y0 = _clampDouble(y, sh);
    final y1 = y0 + 1 < sh ? y0 + 1 : sh - 1;
    final row0 = y0 * sw;
    final row1 = y1 * sw;
    for (var x = 0; x < dw; x++) {
      final x0 = _clampDouble(x, sw);
      final x1 = x0 + 1 < sw ? x0 + 1 : sw - 1;
      final a = (row0 + x0) * 4;
      final b = (row0 + x1) * 4;
      final c = (row1 + x0) * 4;
      final d = (row1 + x1) * 4;
      final o = (y * dw + x) * 4;
      for (var ch = 0; ch < 3; ch++) {
        final avg =
            (_srgbToLinearTable[src[a + ch]] +
                _srgbToLinearTable[src[b + ch]] +
                _srgbToLinearTable[src[c + ch]] +
                _srgbToLinearTable[src[d + ch]]) *
            0.25;
        dst[o + ch] = _linearToSrgb(avg);
      }
      dst[o + 3] =
          ((src[a + 3] + src[b + 3] + src[c + 3] + src[d + 3]) + 2) ~/ 4;
    }
  }
}

void _downsampleData(
  Uint8List src,
  int sw,
  int sh,
  int dw,
  int dh,
  Uint8List dst,
) {
  for (var y = 0; y < dh; y++) {
    final y0 = _clampDouble(y, sh);
    final y1 = y0 + 1 < sh ? y0 + 1 : sh - 1;
    final row0 = y0 * sw;
    final row1 = y1 * sw;
    for (var x = 0; x < dw; x++) {
      final x0 = _clampDouble(x, sw);
      final x1 = x0 + 1 < sw ? x0 + 1 : sw - 1;
      final a = (row0 + x0) * 4;
      final b = (row0 + x1) * 4;
      final c = (row1 + x0) * 4;
      final d = (row1 + x1) * 4;
      final o = (y * dw + x) * 4;
      for (var ch = 0; ch < 4; ch++) {
        dst[o + ch] =
            ((src[a + ch] + src[b + ch] + src[c + ch] + src[d + ch]) + 2) ~/ 4;
      }
    }
  }
}

void _downsampleNormal(
  Uint8List src,
  int sw,
  int sh,
  int dw,
  int dh,
  Uint8List dst,
) {
  for (var y = 0; y < dh; y++) {
    final y0 = _clampDouble(y, sh);
    final y1 = y0 + 1 < sh ? y0 + 1 : sh - 1;
    final row0 = y0 * sw;
    final row1 = y1 * sw;
    for (var x = 0; x < dw; x++) {
      final x0 = _clampDouble(x, sw);
      final x1 = x0 + 1 < sw ? x0 + 1 : sw - 1;
      final a = (row0 + x0) * 4;
      final b = (row0 + x1) * 4;
      final c = (row1 + x0) * 4;
      final d = (row1 + x1) * 4;
      final o = (y * dw + x) * 4;
      // Unrolled: the `for (final p in [a, b, c, d])` this replaces allocated a
      // four-element list per destination texel.
      var nx = src[a] / 127.5 - 1.0;
      var ny = src[a + 1] / 127.5 - 1.0;
      var nz = src[a + 2] / 127.5 - 1.0;
      nx += src[b] / 127.5 - 1.0;
      ny += src[b + 1] / 127.5 - 1.0;
      nz += src[b + 2] / 127.5 - 1.0;
      nx += src[c] / 127.5 - 1.0;
      ny += src[c + 1] / 127.5 - 1.0;
      nz += src[c + 2] / 127.5 - 1.0;
      nx += src[d] / 127.5 - 1.0;
      ny += src[d + 1] / 127.5 - 1.0;
      nz += src[d + 2] / 127.5 - 1.0;
      final len = math.sqrt(nx * nx + ny * ny + nz * nz);
      if (len > 1e-6) {
        nx /= len;
        ny /= len;
        nz /= len;
      } else {
        nx = 0.0;
        ny = 0.0;
        nz = 1.0;
      }
      dst[o] = _encodeUnit(nx);
      dst[o + 1] = _encodeUnit(ny);
      dst[o + 2] = _encodeUnit(nz);
      dst[o + 3] = 255;
    }
  }
}

// sRGB decode of every possible byte, so the color path costs a table lookup
// instead of a `pow` per channel per texel. Same values as _srgbToLinear.
final Float64List _srgbToLinearTable = Float64List.fromList([
  for (var byte = 0; byte < 256; byte++) _srgbToLinear(byte),
]);

double _srgbToLinear(int byte) {
  final c = byte / 255.0;
  return c <= 0.04045
      ? c / 12.92
      : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
}

int _linearToSrgb(double linear) {
  final c = linear <= 0.0031308
      ? linear * 12.92
      : 1.055 * math.pow(linear, 1 / 2.4).toDouble() - 0.055;
  return (c * 255.0).round().clamp(0, 255);
}

// Maps a [-1, 1] component to a [0, 255] byte.
int _encodeUnit(double v) => ((v + 1.0) * 127.5).round().clamp(0, 255);
