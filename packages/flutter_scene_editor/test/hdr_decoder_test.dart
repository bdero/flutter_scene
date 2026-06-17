import 'dart:typed_data';

import 'package:flutter_scene_editor/src/io/hdr_decoder.dart';
import 'package:flutter_test/flutter_test.dart';

// Builds a Radiance HDR byte stream from a header plus raw scanline bytes.
Uint8List _hdr(int width, int height, List<int> scanlineBytes) {
  final header = '#?RADIANCE\nFORMAT=32-bit_rle_rgbe\n\n-Y $height +X $width\n';
  return Uint8List.fromList([...header.codeUnits, ...scanlineBytes]);
}

void main() {
  // RGBE (128,128,128,128) decodes to linear 0.5: 128 * 2^(128 - 136) = 0.5.
  test('decodes flat (uncompressed) scanlines', () {
    // width 4 (< 8) takes the flat/old-style path; four literal pixels.
    final bytes = _hdr(4, 1, [
      for (var i = 0; i < 4; i++) ...[128, 128, 128, 128],
    ]);
    final hdr = decodeRadianceHdr(bytes);
    expect(hdr.width, 4);
    expect(hdr.height, 1);
    for (var x = 0; x < 4; x++) {
      expect(hdr.pixels[x * 4 + 0], closeTo(0.5, 1e-6));
      expect(hdr.pixels[x * 4 + 1], closeTo(0.5, 1e-6));
      expect(hdr.pixels[x * 4 + 2], closeTo(0.5, 1e-6));
      expect(hdr.pixels[x * 4 + 3], 1.0);
    }
  });

  test('decodes new-style adaptive RLE scanlines', () {
    // width 8 with the (2,2,0,8) header; each channel is one run of 8.
    final bytes = _hdr(8, 1, [
      2, 2, 0, 8, // new-style RLE header
      for (var channel = 0; channel < 4; channel++) ...[128 + 8, 128],
    ]);
    final hdr = decodeRadianceHdr(bytes);
    expect(hdr.width, 8);
    for (var x = 0; x < 8; x++) {
      expect(hdr.pixels[x * 4 + 0], closeTo(0.5, 1e-6));
      expect(hdr.pixels[x * 4 + 2], closeTo(0.5, 1e-6));
    }
  });

  test('box-downsamples to maxWidth during decode', () {
    // A 4x4 flat image of linear 0.5, downsampled by factor 2 to 2x2 (each
    // output is the average of a 2x2 block, still 0.5).
    final bytes = _hdr(4, 4, [
      for (var i = 0; i < 16; i++) ...[128, 128, 128, 128],
    ]);
    final hdr = decodeRadianceHdr(bytes, maxWidth: 2);
    expect(hdr.width, 2);
    expect(hdr.height, 2);
    for (var i = 0; i < hdr.width * hdr.height; i++) {
      expect(hdr.pixels[i * 4 + 0], closeTo(0.5, 1e-6));
      expect(hdr.pixels[i * 4 + 3], 1.0);
    }
  });

  test('a zero exponent decodes to black', () {
    final bytes = _hdr(1, 1, [200, 200, 200, 0]);
    final hdr = decodeRadianceHdr(bytes);
    expect(hdr.pixels[0], 0.0);
    expect(hdr.pixels[1], 0.0);
    expect(hdr.pixels[2], 0.0);
  });

  test('rejects a non-Radiance file', () {
    expect(
      () => decodeRadianceHdr(Uint8List.fromList('not hdr'.codeUnits)),
      throwsA(isA<HdrFormatException>()),
    );
  });
}
