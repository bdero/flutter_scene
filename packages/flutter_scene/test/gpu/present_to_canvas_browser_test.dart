// A texture presented to a DOM canvas arrives upright and unchanged, on
// whichever web backend the build selects.
//
//   flutter test --platform chrome test/gpu/present_to_canvas_browser_test.dart
//
// ignore_for_file: implementation_imports
@TestOn('browser')
library;

import 'dart:js_interop';
import 'dart:typed_data';

import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_test/flutter_test.dart';
import 'package:web/web.dart' as web;

const _width = 8;
const _height = 4;

// The top row red, the rest green, all opaque.
ByteData _texels() {
  final bytes = Uint8List(_width * _height * 4);
  for (var y = 0; y < _height; y++) {
    for (var x = 0; x < _width; x++) {
      final i = (y * _width + x) * 4;
      bytes[i] = y == 0 ? 255 : 0;
      bytes[i + 1] = y == 0 ? 0 : 255;
      bytes[i + 3] = 255;
    }
  }
  return ByteData.sublistView(bytes);
}

// The canvas's pixels, read through a 2D canvas.
Uint8List _readCanvas(web.HTMLCanvasElement canvas) {
  final reader = web.OffscreenCanvas(canvas.width, canvas.height);
  final context =
      reader.getContext('2d')! as web.OffscreenCanvasRenderingContext2D
        ..drawImage(canvas, 0, 0);
  final data = context.getImageData(0, 0, canvas.width, canvas.height).data;
  return Uint8List.fromList(data.toDart);
}

List<int> _pixel(Uint8List pixels, int x, int y) {
  final i = (y * _width + x) * 4;
  return pixels.sublist(i, i + 4);
}

void main() {
  setUpAll(() async {
    await gpu.initializeGpuBackend();
  });

  test('presentToCanvas shows a texture upright at its size', () async {
    final texture = gpu.gpuContext.createTexture(
      gpu.StorageMode.devicePrivate,
      _width,
      _height,
    );
    addTearDown(() => gpu.gpuHost.releaseTexture(texture));
    texture.overwrite(_texels());

    final canvas =
        web.document.createElement('canvas') as web.HTMLCanvasElement;
    web.document.body!.append(canvas);
    addTearDown(() => canvas.remove());

    gpu.gpuHost.presentToCanvas(texture, canvas);
    expect(canvas.width, _width);
    expect(canvas.height, _height);

    final pixels = _readCanvas(canvas);
    expect(_pixel(pixels, 0, 0), [255, 0, 0, 255]);
    expect(_pixel(pixels, _width - 1, 0), [255, 0, 0, 255]);
    expect(_pixel(pixels, 0, _height - 1), [0, 255, 0, 255]);
    expect(_pixel(pixels, _width - 1, _height - 1), [0, 255, 0, 255]);
  });

  test('textureToPlatformImage returns an ImageBitmap', () async {
    final texture = gpu.gpuContext.createTexture(
      gpu.StorageMode.devicePrivate,
      _width,
      _height,
    );
    addTearDown(() => gpu.gpuHost.releaseTexture(texture));
    texture.overwrite(_texels());

    final bitmap = gpu.gpuHost.textureToPlatformImage(texture);
    expect(bitmap, isNotNull);
    final image = bitmap! as web.ImageBitmap;
    expect(image.width, _width);
    expect(image.height, _height);
    expect((bitmap as JSObject).instanceOfString('ImageBitmap'), isTrue);
    image.close();
  });
}
