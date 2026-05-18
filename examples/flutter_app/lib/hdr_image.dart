// A decoder for Radiance HDR (`.hdr`, RGBE) equirectangular images.
//
// flutter_scene's EnvironmentMap.fromEquirectHdr wants linear-radiance
// RGBA float pixels; Flutter's built-in image codecs do not handle the
// Radiance format, so this fills the gap. Decodes the new-style adaptive
// RLE scanlines (and a flat / old-RLE fallback), converts RGBE mantissas
// to linear float radiance, and box-downsamples to a manageable size.

import 'dart:math' as math;
import 'dart:typed_data';

/// A decoded equirectangular HDR image: linear-radiance RGBA float pixels,
/// row-major, [width] by [height] (row 0 at the top).
class HdrImage {
  HdrImage(this.width, this.height, this.pixels)
    : assert(pixels.length == width * height * 4);

  final int width;
  final int height;

  /// Linear radiance, four floats per pixel (alpha is always 1.0).
  final Float32List pixels;
}

/// Decodes a Radiance HDR file and box-downsamples it so its width is at
/// most [maxWidth]. Suitable to run in an isolate via `compute`.
HdrImage loadHdrEnvironment(Uint8List bytes) {
  return _downsample(decodeRadianceHdr(bytes), 1024);
}

/// 2^(e - 136) for every possible RGBE exponent byte, the per-pixel scale
/// that turns an RGBE mantissa into linear radiance.
final Float64List _exponentScale = Float64List.fromList(
  List<double>.generate(256, (e) => math.pow(2.0, e - 136).toDouble()),
);

/// Decodes a Radiance HDR (`.hdr`) file to linear-radiance float pixels.
///
/// Supports the standard `32-bit_rle_rgbe` format in the common `-Y +X`
/// orientation, with new-style adaptive RLE scanlines plus a flat /
/// old-RLE fallback.
HdrImage decodeRadianceHdr(Uint8List bytes) {
  var pos = 0;

  String readLine() {
    final sb = StringBuffer();
    while (pos < bytes.length) {
      final c = bytes[pos++];
      if (c == 0x0a) break; // newline
      sb.writeCharCode(c);
    }
    return sb.toString();
  }

  final magic = readLine();
  if (!magic.startsWith('#?')) {
    throw const FormatException('Not a Radiance HDR file');
  }
  var format = '';
  while (true) {
    final line = readLine();
    if (line.isEmpty) break; // a blank line ends the header
    if (line.startsWith('FORMAT=')) format = line.substring(7).trim();
  }
  if (format.isNotEmpty && format != '32-bit_rle_rgbe') {
    throw FormatException('Unsupported HDR format: $format');
  }

  final resolution = readLine().trim().split(RegExp(r'\s+'));
  if (resolution.length != 4 ||
      resolution[0] != '-Y' ||
      resolution[2] != '+X') {
    throw FormatException(
      'Unsupported HDR orientation: ${resolution.join(' ')}',
    );
  }
  final height = int.parse(resolution[1]);
  final width = int.parse(resolution[3]);

  final pixels = Float32List(width * height * 4);
  final scanline = Uint8List(width * 4); // one row of raw RGBE

  for (var y = 0; y < height; y++) {
    pos = _readScanline(bytes, pos, scanline, width);
    // Radiance `-Y` files store rows top-down (row 0 = up pole), but
    // flutter_scene's equirect convention is row 0 = down pole (what
    // EnvironmentMap.studio emits and the SH projection expects), so
    // write each scanline into the vertically-mirrored destination row.
    final rowBase = (height - 1 - y) * width * 4;
    for (var x = 0; x < width; x++) {
      final si = x * 4;
      final exponent = scanline[si + 3];
      final di = rowBase + si;
      if (exponent != 0) {
        final scale = _exponentScale[exponent];
        pixels[di] = scanline[si] * scale;
        pixels[di + 1] = scanline[si + 1] * scale;
        pixels[di + 2] = scanline[si + 2] * scale;
      }
      pixels[di + 3] = 1.0;
    }
  }
  return HdrImage(width, height, pixels);
}

// Decodes one scanline of [width] RGBE pixels into [out], returning the
// new read position. Picks new-style adaptive RLE when the scanline
// header marks it, otherwise falls back to flat / old-RLE pixels.
int _readScanline(Uint8List bytes, int pos, Uint8List out, int width) {
  if (width >= 8 && width <= 0x7fff) {
    final r = bytes[pos];
    final g = bytes[pos + 1];
    final b = bytes[pos + 2];
    final e = bytes[pos + 3];
    if (r == 2 && g == 2 && (b & 0x80) == 0) {
      if (((b << 8) | e) != width) {
        throw const FormatException('HDR scanline width mismatch');
      }
      pos += 4;
      // Each of the four channels is RLE-encoded across the whole
      // scanline: a count above 128 is a run of (count - 128) copies of
      // the next byte, otherwise it is that many literal bytes.
      for (var c = 0; c < 4; c++) {
        var x = 0;
        while (x < width) {
          var count = bytes[pos++];
          if (count > 128) {
            count -= 128;
            final value = bytes[pos++];
            for (var k = 0; k < count; k++) {
              out[(x++) * 4 + c] = value;
            }
          } else {
            for (var k = 0; k < count; k++) {
              out[(x++) * 4 + c] = bytes[pos++];
            }
          }
        }
      }
      return pos;
    }
  }
  return _readFlatScanline(bytes, pos, out, width);
}

// Reads a scanline stored as flat RGBE quads, honoring old-style RLE
// where a (1, 1, 1, n) quad repeats the previous pixel.
int _readFlatScanline(Uint8List bytes, int pos, Uint8List out, int width) {
  var x = 0;
  var runShift = 0;
  while (x < width) {
    final r = bytes[pos];
    final g = bytes[pos + 1];
    final b = bytes[pos + 2];
    final e = bytes[pos + 3];
    pos += 4;
    if (r == 1 && g == 1 && b == 1 && x > 0) {
      final count = e << (runShift * 8);
      final prev = (x - 1) * 4;
      for (var k = 0; k < count && x < width; k++) {
        final o = x * 4;
        out[o] = out[prev];
        out[o + 1] = out[prev + 1];
        out[o + 2] = out[prev + 2];
        out[o + 3] = out[prev + 3];
        x++;
      }
      runShift++;
    } else {
      final o = x * 4;
      out[o] = r;
      out[o + 1] = g;
      out[o + 2] = b;
      out[o + 3] = e;
      x++;
      runShift = 0;
    }
  }
  return pos;
}

// Box-downsamples [src] by an integer factor so its width does not exceed
// [maxWidth]. Averaging is done in linear radiance, which is correct for
// HDR data. Returns [src] unchanged when it is already small enough.
HdrImage _downsample(HdrImage src, int maxWidth) {
  if (src.width <= maxWidth) return src;
  final factor = (src.width / maxWidth).ceil();
  final dw = src.width ~/ factor;
  final dh = src.height ~/ factor;
  final out = Float32List(dw * dh * 4);
  final inverseArea = 1.0 / (factor * factor);
  for (var y = 0; y < dh; y++) {
    for (var x = 0; x < dw; x++) {
      var r = 0.0, g = 0.0, b = 0.0;
      for (var sy = 0; sy < factor; sy++) {
        var si = ((y * factor + sy) * src.width + x * factor) * 4;
        for (var sx = 0; sx < factor; sx++) {
          r += src.pixels[si];
          g += src.pixels[si + 1];
          b += src.pixels[si + 2];
          si += 4;
        }
      }
      final di = (y * dw + x) * 4;
      out[di] = r * inverseArea;
      out[di + 1] = g * inverseArea;
      out[di + 2] = b * inverseArea;
      out[di + 3] = 1.0;
    }
  }
  return HdrImage(dw, dh, out);
}
