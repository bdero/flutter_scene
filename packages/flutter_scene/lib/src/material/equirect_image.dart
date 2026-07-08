/// Format detection and unified decode for equirectangular image sources
/// loaded into an [EnvironmentMap]: Radiance HDR, OpenEXR, or a standard
/// low-dynamic-range image.
library;

import 'dart:typed_data';

import 'package:flutter_scene/src/material/exr_decoder.dart';
import 'package:flutter_scene/src/material/hdr_decoder.dart';

/// The container of an equirectangular image, detected from its bytes.
/// {@category Assets and loading}
enum EquirectImageFormat {
  /// Radiance `.hdr` (RGBE), decoded to linear float.
  radianceHdr,

  /// OpenEXR `.exr`, decoded to linear float.
  openExr,

  /// A standard sRGB image (PNG, JPEG, and so on), decoded by the platform
  /// image codec and interpreted as sRGB.
  ldr,
}

/// Detects the [EquirectImageFormat] of [bytes] from its magic number.
/// {@category Assets and loading}
EquirectImageFormat detectEquirectImageFormat(Uint8List bytes) {
  // Radiance files start with "#?" (e.g. "#?RADIANCE" or "#?RGBE").
  if (bytes.length >= 2 && bytes[0] == 0x23 && bytes[1] == 0x3f) {
    return EquirectImageFormat.radianceHdr;
  }
  // OpenEXR magic number 20000630, little-endian: 0x76 0x2f 0x31 0x01.
  if (bytes.length >= 4 &&
      bytes[0] == 0x76 &&
      bytes[1] == 0x2f &&
      bytes[2] == 0x31 &&
      bytes[3] == 0x01) {
    return EquirectImageFormat.openExr;
  }
  return EquirectImageFormat.ldr;
}

/// Decodes a high-dynamic-range equirectangular image ([EquirectImageFormat.radianceHdr]
/// or [EquirectImageFormat.openExr]) from [bytes] to linear float pixels, or
/// returns null for a low-dynamic-range image (the caller decodes those with
/// the platform image codec as sRGB).
///
/// [maxWidth] box-downsamples a source wider than it during decode. Runs pure
/// on the CPU, so it is safe to call on a background isolate.
/// {@category Assets and loading}
DecodedHdr? decodeEquirectHdrImage(Uint8List bytes, {int? maxWidth}) {
  switch (detectEquirectImageFormat(bytes)) {
    case EquirectImageFormat.radianceHdr:
      return decodeRadianceHdr(bytes, maxWidth: maxWidth);
    case EquirectImageFormat.openExr:
      return decodeOpenExr(bytes, maxWidth: maxWidth);
    case EquirectImageFormat.ldr:
      return null;
  }
}

/// Box-downsamples an equirect [source] by the smallest integer factor that
/// brings its width to at most [maxWidth], averaging in linear space
/// (longitude wraps, latitude clamps at the poles). Returns [source] unchanged
/// when it is already narrow enough.
DecodedHdr boxDownsampleEquirect(DecodedHdr source, int maxWidth) {
  if (source.width <= maxWidth) return source;
  final factor = (source.width / maxWidth).ceil();
  final dw = source.width ~/ factor;
  final dh = source.height ~/ factor;
  final out = Float32List(dw * dh * 4);
  final inverseArea = 1.0 / (factor * factor);
  final src = source.pixels;
  for (var y = 0; y < dh; y++) {
    for (var x = 0; x < dw; x++) {
      var r = 0.0, g = 0.0, b = 0.0;
      for (var sy = 0; sy < factor; sy++) {
        var si = ((y * factor + sy) * source.width + x * factor) * 4;
        for (var sx = 0; sx < factor; sx++) {
          r += src[si];
          g += src[si + 1];
          b += src[si + 2];
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
  return DecodedHdr(out, dw, dh);
}
