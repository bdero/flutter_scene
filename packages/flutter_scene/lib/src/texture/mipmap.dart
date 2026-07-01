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
  for (var y = 0; y < dh; y++) {
    // Map each destination texel to a 2x2 (edge-clamped) block of the source.
    final y0 = math.min(y * 2, sh - 1);
    final y1 = math.min(y0 + 1, sh - 1);
    for (var x = 0; x < dw; x++) {
      final x0 = math.min(x * 2, sw - 1);
      final x1 = math.min(x0 + 1, sw - 1);
      final a = (y0 * sw + x0) * 4;
      final b = (y0 * sw + x1) * 4;
      final c = (y1 * sw + x0) * 4;
      final d = (y1 * sw + x1) * 4;
      final o = (y * dw + x) * 4;
      switch (content) {
        case TextureContent.color:
          for (var ch = 0; ch < 3; ch++) {
            final avg =
                (_srgbToLinear(src[a + ch]) +
                    _srgbToLinear(src[b + ch]) +
                    _srgbToLinear(src[c + ch]) +
                    _srgbToLinear(src[d + ch])) *
                0.25;
            dst[o + ch] = _linearToSrgb(avg);
          }
          dst[o + 3] =
              ((src[a + 3] + src[b + 3] + src[c + 3] + src[d + 3]) + 2) ~/ 4;
        case TextureContent.data:
          for (var ch = 0; ch < 4; ch++) {
            dst[o + ch] =
                ((src[a + ch] + src[b + ch] + src[c + ch] + src[d + ch]) + 2) ~/
                4;
          }
        case TextureContent.normal:
          var nx = 0.0, ny = 0.0, nz = 0.0;
          for (final p in [a, b, c, d]) {
            nx += src[p] / 127.5 - 1.0;
            ny += src[p + 1] / 127.5 - 1.0;
            nz += src[p + 2] / 127.5 - 1.0;
          }
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
  return dst;
}

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
