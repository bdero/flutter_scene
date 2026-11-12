/// Covers Texture2D.fromImage: it uploads the chain Texture2D.fromPixels
/// would, and builds that chain on a background isolate so the calling
/// isolate keeps running its event loop meanwhile.
library;

import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_scene/src/texture/mipmap.dart';
import 'package:flutter_scene/src/texture/mipmap_async.dart';
import 'package:flutter_scene/src/texture/texture2d.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/gpu_available.dart';

// Opaque pixels that differ from texel to texel, so a wrong level or a
// reordered row shows up in a comparison.
Uint8List _pattern(int width, int height) {
  final pixels = Uint8List(width * height * 4);
  for (var i = 0; i < width * height; i++) {
    pixels[i * 4] = (i * 7) & 0xff;
    pixels[i * 4 + 1] = (i * 13 + 5) & 0xff;
    pixels[i * 4 + 2] = (i ~/ width * 3) & 0xff;
    pixels[i * 4 + 3] = 0xff;
  }
  return pixels;
}

Future<ui.Image> _image(Uint8List pixels, int width, int height) {
  final completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    pixels,
    width,
    height,
    ui.PixelFormat.rgba8888,
    completer.complete,
  );
  return completer.future;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the background chain matches the synchronous one', () async {
    for (final content in TextureContent.values) {
      final pixels = _pattern(24, 10);
      final expected = generateMipChain(pixels, 24, 10, content);
      final actual = await generateMipChainAsync(pixels, 24, 10, content);
      expect(actual, hasLength(expected.length));
      for (var level = 0; level < expected.length; level++) {
        expect(actual[level].width, expected[level].width);
        expect(actual[level].height, expected[level].height);
        expect(actual[level].pixels, expected[level].pixels);
      }
    }
  });

  group('Texture2D.fromImage', () {
    if (!gpuAvailable()) {
      // ignore: avoid_print
      print('GPU unavailable - skipping.');
      return;
    }

    test('uploads the chain fromPixels uploads', () async {
      final pixels = _pattern(64, 32);
      final image = await _image(pixels, 64, 32);
      addTearDown(image.dispose);

      final texture = await Texture2D.fromImage(image);
      expect(texture.gpuTexture.width, 64);
      expect(texture.gpuTexture.height, 32);
      expect(
        texture.gpuTexture.mipLevelCount,
        Texture2D.fromPixels(pixels, 64, 32).gpuTexture.mipLevelCount,
      );

      const unmipped = TextureSampling(mipmaps: false);
      final single = await Texture2D.fromImage(image, sampling: unmipped);
      expect(single.gpuTexture.mipLevelCount, 1);
    });

    test('keeps the calling isolate running while the chain builds', () async {
      const size = 2048;
      final pixels = _pattern(size, size);
      final image = await _image(pixels, size, size);
      addTearDown(image.dispose);

      // What building this chain costs an isolate that does it itself.
      final build = Stopwatch()..start();
      generateMipChain(pixels, size, size, TextureContent.color);
      build.stop();

      // The longest stretch the event loop went unserved during the load.
      final sinceTurn = Stopwatch()..start();
      var longestStall = Duration.zero;
      var loading = true;
      void turn() {
        if (sinceTurn.elapsed > longestStall) longestStall = sinceTurn.elapsed;
        sinceTurn.reset();
        if (loading) Timer.run(turn);
      }

      Timer.run(turn);
      await Texture2D.fromImage(image);
      loading = false;
      turn();

      expect(longestStall, lessThan(build.elapsed * 0.5));
    });
  });
}
