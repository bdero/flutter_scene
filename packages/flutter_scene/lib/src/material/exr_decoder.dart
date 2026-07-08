/// OpenEXR (`.exr`) decode to linear float pixels for [EnvironmentMap].
///
/// EXR carries the full compression and pixel-type matrix (ZIP, PIZ, half,
/// float, and so on), so this delegates to `package:image`, which handles them,
/// rather than reimplementing the format. EXR is scene-linear, so the channel
/// values are used as linear radiance directly.
library;

import 'dart:typed_data';

import 'package:flutter_scene/src/material/equirect_image.dart';
import 'package:flutter_scene/src/material/hdr_decoder.dart' show DecodedHdr;
import 'package:image/image.dart' as img;

/// Thrown when [decodeOpenExr] cannot parse the bytes as an OpenEXR image.
/// {@category Assets and loading}
class ExrFormatException implements Exception {
  ExrFormatException(this.message);
  final String message;
  @override
  String toString() => 'ExrFormatException: $message';
}

/// Decodes an OpenEXR image from [bytes] to linear RGBA float pixels (alpha 1),
/// row-major, row 0 at the top (the equirect up pole).
///
/// Only 16-bit half-float channels are supported (the common format for HDRI
/// panoramas); a 32-bit-float or uint EXR throws with a clear message rather
/// than decoding to garbage. TODO(exr-float): support 32-bit-float channels
/// (the underlying decoder reads them as 16 bits; needs an upstream fix or a
/// custom float path).
///
/// When [maxWidth] is set and the source is wider, the result is
/// box-downsampled by an integer factor (averaged in linear space) so a very
/// large panorama is not kept at full resolution. Alpha is discarded (set to
/// 1); an environment map is opaque.
/// {@category Assets and loading}
DecodedHdr decodeOpenExr(Uint8List bytes, {int? maxWidth}) {
  _requireHalfChannels(bytes);
  final image = img.decodeExr(bytes);
  if (image == null) {
    throw ExrFormatException('Not a decodable OpenEXR image');
  }
  final width = image.width;
  final height = image.height;
  // package:image decodes top-down (row 0 = top), matching the equirect up-pole
  // convention, so the scanline order is preserved.
  final pixels = Float32List(width * height * 4);
  var i = 0;
  // The iterator reuses one Pixel, so this stays allocation-light.
  // TODO(exr-perf): read the float image buffer directly if this is a hot path.
  for (final pixel in image) {
    pixels[i] = pixel.r.toDouble();
    pixels[i + 1] = pixel.g.toDouble();
    pixels[i + 2] = pixel.b.toDouble();
    pixels[i + 3] = 1.0;
    i += 4;
  }
  final decoded = DecodedHdr(pixels, width, height);
  if (maxWidth == null || width <= maxWidth) return decoded;
  return boxDownsampleEquirect(decoded, maxWidth);
}

// Rejects an EXR whose channels are not 16-bit half, since the underlying
// decoder mis-reads 32-bit-float and uint channels. Best-effort: parses only
// the channel list, and stays silent if the header does not parse cleanly (the
// decoder then reports any real problem).
void _requireHalfChannels(Uint8List bytes) {
  var pos = 8; // skip the 4-byte magic and 4-byte version.
  String readString() {
    final start = pos;
    while (pos < bytes.length && bytes[pos] != 0) {
      pos++;
    }
    final value = String.fromCharCodes(bytes, start, pos);
    pos++; // the terminating null.
    return value;
  }

  int readInt32() {
    final value =
        bytes[pos] |
        (bytes[pos + 1] << 8) |
        (bytes[pos + 2] << 16) |
        (bytes[pos + 3] << 24);
    pos += 4;
    return value;
  }

  try {
    while (pos < bytes.length) {
      final name = readString();
      if (name.isEmpty) return; // end of header, no channel list seen.
      readString(); // attribute type.
      final size = readInt32();
      if (name != 'channels') {
        pos += size; // skip other attributes.
        continue;
      }
      final end = pos + size;
      while (pos < end) {
        final channelName = readString();
        if (channelName.isEmpty) break;
        final pixelType = readInt32(); // 0 uint, 1 half, 2 float.
        pos += 12; // pLinear + 3 reserved + xSampling + ySampling.
        if (pixelType != 1) {
          throw ExrFormatException(
            'Only 16-bit half-float EXR channels are supported; re-export the '
            'image with half channels (found pixel type $pixelType).',
          );
        }
      }
      return;
    }
  } on RangeError {
    // A header we could not parse; let the decoder surface any real error.
  }
}
