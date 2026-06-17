/// Minimal Radiance RGBE (`.hdr`) decoder, enough to load an equirectangular
/// HDR environment map into linear float pixels for `EnvironmentMap`.
///
/// Supports the common new-style adaptive run-length encoding plus the
/// old-style RLE and flat (uncompressed) RGBE scanlines, for the standard
/// `32-bit_rle_rgbe` format written with a `-Y H +X W` resolution line (row 0
/// at the top, the equirect up pole). Other orientations and the XYZE color
/// format are rejected.
library;

import 'dart:typed_data';

/// A decoded HDR image: linear RGBA float pixels (alpha 1), row-major, row 0
/// at the top.
class DecodedHdr {
  DecodedHdr(this.pixels, this.width, this.height);

  /// `width * height * 4` linear floats, RGBA, row 0 at the top.
  final Float32List pixels;
  final int width;
  final int height;
}

/// Thrown when [decodeRadianceHdr] cannot parse [bytes] as a supported
/// Radiance HDR image.
class HdrFormatException implements Exception {
  HdrFormatException(this.message);
  final String message;
  @override
  String toString() => 'HdrFormatException: $message';
}

/// Decodes a Radiance `.hdr`/`.pic` RGBE image from [bytes].
///
/// When [maxWidth] is set and the source is wider, the image is box-downsampled
/// by an integer factor during decode (averaging in linear space) so a very
/// large panorama (e.g. 16K) never materializes at full resolution. A realtime
/// environment map does not need more than a few thousand pixels wide.
DecodedHdr decodeRadianceHdr(Uint8List bytes, {int? maxWidth}) {
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
    throw HdrFormatException('Not a Radiance HDR file (bad magic)');
  }
  // Header lines until a blank line; we only need the format.
  String? format;
  while (pos < bytes.length) {
    final line = readLine();
    if (line.isEmpty) break;
    if (line.startsWith('FORMAT=')) format = line.substring(7).trim();
  }
  if (format != null && format != '32-bit_rle_rgbe') {
    throw HdrFormatException('Unsupported HDR format "$format"');
  }

  final resolution = readLine();
  // Expect "-Y height +X width" (the standard top-down, left-right layout).
  final match = RegExp(r'^-Y\s+(\d+)\s+\+X\s+(\d+)$').firstMatch(resolution);
  if (match == null) {
    throw HdrFormatException('Unsupported HDR orientation "$resolution"');
  }
  final height = int.parse(match.group(1)!);
  final width = int.parse(match.group(2)!);
  if (width <= 0 || height <= 0) {
    throw HdrFormatException('Invalid HDR dimensions ${width}x$height');
  }

  // Integer box-downsample factor: every factor x factor source block averages
  // to one output texel. Output dimensions drop the partial trailing block.
  final factor = (maxWidth != null && maxWidth > 0 && width > maxWidth)
      ? (width + maxWidth - 1) ~/ maxWidth
      : 1;
  final outWidth = width ~/ factor;
  final outHeight = height ~/ factor;

  final pixels = Float32List(outWidth * outHeight * 4); // linear accumulator
  final scanline = Uint8List(width * 4); // RGBE for one source row

  for (var y = 0; y < height; y++) {
    pos = _readScanline(bytes, pos, scanline, width);
    final outY = y ~/ factor;
    if (outY >= outHeight) continue; // trailing partial block
    final rowOffset = outY * outWidth * 4;
    for (var x = 0; x < width; x++) {
      final outX = x ~/ factor;
      if (outX >= outWidth) continue;
      final e = scanline[x * 4 + 3];
      if (e == 0) continue;
      // RGBE -> linear float: component / 256 * 2^(exponent - 128).
      final scale = _ldexp(1.0, e - (128 + 8));
      final o = rowOffset + outX * 4;
      pixels[o] += scanline[x * 4 + 0] * scale;
      pixels[o + 1] += scanline[x * 4 + 1] * scale;
      pixels[o + 2] += scanline[x * 4 + 2] * scale;
    }
  }

  // Normalize the box sum and set opaque alpha (factor 1 is a plain copy).
  final norm = 1.0 / (factor * factor);
  for (var i = 0; i < pixels.length; i += 4) {
    pixels[i] *= norm;
    pixels[i + 1] *= norm;
    pixels[i + 2] *= norm;
    pixels[i + 3] = 1.0;
  }
  return DecodedHdr(pixels, outWidth, outHeight);
}

// Reads one RGBE scanline (width pixels) into [out], returning the new byte
// position. Dispatches on the new-style RLE marker; falls back to old-style
// RLE / flat reads.
int _readScanline(Uint8List bytes, int pos, Uint8List out, int width) {
  // New-style adaptive RLE: a 4-byte header of (2, 2, widthHi, widthLo) with
  // 8 <= width < 32768, then each of the four channels RLE-encoded separately.
  if (width >= 8 &&
      width < 32768 &&
      pos + 4 <= bytes.length &&
      bytes[pos] == 2 &&
      bytes[pos + 1] == 2 &&
      ((bytes[pos + 2] << 8) | bytes[pos + 3]) == width) {
    pos += 4;
    for (var channel = 0; channel < 4; channel++) {
      var x = 0;
      while (x < width) {
        if (pos >= bytes.length) {
          throw HdrFormatException('Truncated HDR scanline');
        }
        var count = bytes[pos++];
        if (count > 128) {
          // A run: (count - 128) copies of the next byte.
          count -= 128;
          final value = bytes[pos++];
          for (var i = 0; i < count; i++) {
            out[(x++) * 4 + channel] = value;
          }
        } else {
          // A dump: `count` literal bytes.
          for (var i = 0; i < count; i++) {
            out[(x++) * 4 + channel] = bytes[pos++];
          }
        }
      }
    }
    return pos;
  }

  // Old-style RLE / flat: read width RGBE pixels, expanding (1,1,1,n) runs that
  // repeat the previous pixel 2^(8*runCount) deep.
  var x = 0;
  var shift = 0;
  while (x < width) {
    if (pos + 4 > bytes.length) {
      throw HdrFormatException('Truncated HDR scanline');
    }
    final r = bytes[pos++];
    final g = bytes[pos++];
    final b = bytes[pos++];
    final e = bytes[pos++];
    if (r == 1 && g == 1 && b == 1) {
      // A repeat of the previous pixel, e << (8 * shift) times.
      final repeat = e << (8 * shift);
      final prev = (x - 1) * 4;
      for (var i = 0; i < repeat && x < width; i++) {
        out[x * 4 + 0] = out[prev + 0];
        out[x * 4 + 1] = out[prev + 1];
        out[x * 4 + 2] = out[prev + 2];
        out[x * 4 + 3] = out[prev + 3];
        x++;
      }
      shift++;
    } else {
      out[x * 4 + 0] = r;
      out[x * 4 + 1] = g;
      out[x * 4 + 2] = b;
      out[x * 4 + 3] = e;
      x++;
      shift = 0;
    }
  }
  return pos;
}

// 2^exp for an integer exponent, without dart:math (avoids importing it here).
double _ldexp(double mantissa, int exp) {
  var result = mantissa;
  if (exp > 0) {
    for (var i = 0; i < exp; i++) {
      result *= 2.0;
    }
  } else {
    for (var i = 0; i < -exp; i++) {
      result *= 0.5;
    }
  }
  return result;
}
