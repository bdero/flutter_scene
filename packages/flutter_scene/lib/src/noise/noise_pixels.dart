// Bakes a configured noise field into pixels, for materials that would
// rather sample one texture than evaluate several octaves per fragment.
// Pure CPU work with no engine imports, usable from build hooks, CLI tools,
// and background isolates; the GPU upload half lives in noise_texture.dart.

import 'dart:typed_data';

import 'package:flutter_scene/src/noise/fast_noise_lite.dart';

/// Evaluates [noise] over a [width] x [height] grid into grayscale RGBA8888
/// pixels (straight alpha 255).
///
/// The sample for pixel (px, py) is taken at
/// `(originX + px * cellSize, originY + py * cellSize)` through
/// [FastNoiseLite.getNoise2] (so the instance's frequency and fractal
/// settings apply), remapped from [-1, 1] to [0, 255]. Pair with
/// `bakeNoiseTexture` for the GPU upload.
/// {@category Noise}
Uint8List bakeNoisePixels(
  FastNoiseLite noise, {
  required int width,
  required int height,
  double originX = 0.0,
  double originY = 0.0,
  double cellSize = 1.0,
}) {
  final pixels = Uint8List(width * height * 4);
  var o = 0;
  for (var py = 0; py < height; py++) {
    final y = originY + py * cellSize;
    for (var px = 0; px < width; px++) {
      final v = noise.getNoise2(originX + px * cellSize, y);
      final byte = ((v * 0.5 + 0.5).clamp(0.0, 1.0) * 255.0).round();
      pixels[o] = byte;
      pixels[o + 1] = byte;
      pixels[o + 2] = byte;
      pixels[o + 3] = 255;
      o += 4;
    }
  }
  return pixels;
}
