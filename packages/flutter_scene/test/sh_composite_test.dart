// Covers the diffuse-SH composite pass: both source textures land in the
// right rows and column order is preserved, so the lit shader's single
// sh_coefficients sampler reads the primary in row 0 and the cross-fade
// secondary in row 1. GPU-gated like the other render suites.

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_scene/scene.dart';
import 'package:flutter_test/flutter_test.dart';

// ignore: implementation_imports
import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
// ignore: implementation_imports
import 'package:flutter_scene/src/render/sh_composite.dart';

bool _gpuAvailable() {
  try {
    Scene();
    return true;
  } catch (_) {
    return false;
  }
}

// Minimal float32 to float16 bit conversion for the small positive values
// used here (no subnormals, infinities, or NaNs).
int _halfBits(double value) {
  final bits = Float32List.fromList([value]).buffer.asUint32List()[0];
  final exponent = ((bits >> 23) & 0xFF) - 127 + 15;
  final mantissa = (bits >> 13) & 0x3FF;
  if (value == 0) return 0;
  return ((exponent & 0x1F) << 10) | mantissa;
}

// A 9x1 RGBA16F coefficient texture with texel i = (red, i / 16, 0, 1).
gpu.Texture _shSource(double red) {
  final texture = gpu.gpuContext.createTexture(
    gpu.StorageMode.hostVisible,
    9,
    1,
    format: gpu.PixelFormat.r16g16b16a16Float,
  );
  final half = Uint16List(9 * 4);
  for (var i = 0; i < 9; i++) {
    half[i * 4] = _halfBits(red);
    half[i * 4 + 1] = _halfBits(i / 16.0);
    half[i * 4 + 2] = 0;
    half[i * 4 + 3] = _halfBits(1.0);
  }
  texture.overwrite(ByteData.sublistView(half));
  return texture;
}

void main() {
  if (!_gpuAvailable()) {
    test(
      'sh composite (skipped: no GPU device)',
      () {},
      skip: 'Requires a GPU device.',
    );
    return;
  }

  test('composite places primary in row 0 and secondary in row 1', () async {
    await Scene.initializeStaticResources();

    final primary = _shSource(0.25);
    final secondary = _shSource(0.75);
    // An 8-bit readable target; the copy is value-preserving for values in
    // [0, 1], and 8-bit quantization is far finer than the 0.5 row contrast.
    final target = gpu.gpuContext.createTexture(
      gpu.StorageMode.devicePrivate,
      9,
      2,
      format: gpu.PixelFormat.r8g8b8a8UNormInt,
      enableRenderTargetUsage: true,
      enableShaderReadUsage: true,
    );
    encodeShComposite(target, primary, secondary);

    final ui.Image image = target.asImage();
    final bytes = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    int red(int x, int y) => bytes.getUint8((y * 9 + x) * 4);
    int green(int x, int y) => bytes.getUint8((y * 9 + x) * 4 + 1);

    for (var x = 0; x < 9; x++) {
      expect(red(x, 0), closeTo(64, 3), reason: 'row 0 red at texel $x');
      expect(red(x, 1), closeTo(191, 3), reason: 'row 1 red at texel $x');
      // Column order preserved in both rows (green ramps with the texel
      // index).
      final ramp = ((x / 16.0) * 255.0).round();
      expect(green(x, 0), closeTo(ramp, 3), reason: 'row 0 green at $x');
      expect(green(x, 1), closeTo(ramp, 3), reason: 'row 1 green at $x');
    }
  });
}
