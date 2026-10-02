// Locates where a WebGPU frame loses its pixels on the way into Flutter, on a
// browser where the synchronous handoff reads back zeros. Each test checks one
// link of the chain and prints its result, so the CI log names the broken one.
//
//   flutter test --platform chrome test/gpu/webgpu/webgpu_handoff_diagnostic_browser_test.dart
//
// ignore_for_file: implementation_imports, avoid_print
@TestOn('browser')
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:ui_web' as ui_web;

import 'package:flutter_scene/src/gpu/webgpu/webgpu_device.dart';
import 'package:flutter_scene/src/gpu/webgpu/webgpu_interop.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web/web.dart' as web;

const _w = 4;
const _h = 4;

JSObject _obj(Map<String, Object?> fields) => fields.jsify()! as JSObject;

void main() {
  late WebGpuProbe probe;

  setUpAll(() async {
    probe = await WebGpuDevice.request(allowFallbackAdapter: true);
    print('DIAG probe $probe');
  });

  /// Renders a clear into a canvas configured for WebGPU and returns it.
  web.OffscreenCanvas clearedCanvas(WebGpuDevice d, {bool copySrc = false}) {
    final canvas = web.OffscreenCanvas(_w, _h);
    final ctx = canvas.getContext('webgpu')! as GPUCanvasContext;
    final config = _obj({
      'device': d.device,
      'format': d.preferredCanvasFormat,
      'alphaMode': 'premultiplied',
      // COPY_SRC (0x01) | RENDER_ATTACHMENT (0x10)
      if (copySrc) 'usage': 0x11,
    });
    ctx.callMethod('configure'.toJS, config);
    final target = ctx.getCurrentTexture();
    final encoder = d.device.createCommandEncoder();
    encoder
        .beginRenderPass(
          GPURenderPassDescriptor(
            colorAttachments: [
              GPURenderPassColorAttachment(
                view: target.createView(),
                clearValue: GPUColorDict(r: 0.25, g: 0.5, b: 0.75, a: 1),
                loadOp: 'clear',
                storeOp: 'store',
              ),
            ].toJS,
          ),
        )
        .end();
    d.device.queue.submit([encoder.finish()].toJS);
    return canvas;
  }

  String firstPixel(Uint8List rgba) =>
      '${rgba[0]},${rgba[1]},${rgba[2]},${rgba[3]}';

  test('1. WebGPU itself renders the clear (buffer readback)', () async {
    if (!probe.available) return markTestSkipped('$probe');
    final d = probe.device!;
    final texture =
        d.device.callMethod(
              'createTexture'.toJS,
              _obj({
                'size': [_w, _h],
                'format': 'rgba8unorm',
                // RENDER_ATTACHMENT | COPY_SRC
                'usage': 0x11,
              }),
            )
            as GPUTexture;
    final buffer =
        d.device.callMethod(
              'createBuffer'.toJS,
              _obj({
                'size': 256 * _h,
                // MAP_READ (0x1) | COPY_DST (0x8)
                'usage': 0x9,
              }),
            )
            as JSObject;
    final encoder = d.device.createCommandEncoder();
    encoder
        .beginRenderPass(
          GPURenderPassDescriptor(
            colorAttachments: [
              GPURenderPassColorAttachment(
                view: texture.createView(),
                clearValue: GPUColorDict(r: 0.25, g: 0.5, b: 0.75, a: 1),
                loadOp: 'clear',
                storeOp: 'store',
              ),
            ].toJS,
          ),
        )
        .end();
    (encoder as JSObject).callMethod(
      'copyTextureToBuffer'.toJS,
      _obj({'texture': texture}),
      _obj({'buffer': buffer, 'bytesPerRow': 256}),
      [_w, _h].jsify(),
    );
    d.device.queue.submit([encoder.finish()].toJS);
    // GPUMapMode.READ
    await (buffer.callMethod('mapAsync'.toJS, 1.toJS) as JSPromise).toDart;
    final mapped =
        (buffer.callMethod('getMappedRange'.toJS) as JSArrayBuffer).toDart;
    final rgba = Uint8List.fromList(mapped.asUint8List(0, 4));
    print('DIAG 1 buffer readback ${firstPixel(rgba)}');
    expect(rgba[0], closeTo(64, 1.5));
  });

  test('2. The transferred bitmap carries the pixels (2D canvas)', () async {
    if (!probe.available) return markTestSkipped('$probe');
    final bitmap = clearedCanvas(probe.device!).transferToImageBitmap();
    final readback = web.OffscreenCanvas(_w, _h);
    final ctx2d =
        readback.getContext('2d')! as web.OffscreenCanvasRenderingContext2D;
    ctx2d.drawImage(bitmap, 0, 0);
    final data = ctx2d.getImageData(0, 0, _w, _h).data.toDart;
    final rgba = Uint8List.fromList(data.buffer.asUint8List(0, 4));
    print('DIAG 2 bitmap via 2d canvas ${firstPixel(rgba)}');
    expect(rgba[0], closeTo(64, 1.5));
  });

  test('3. The synchronous bitmap handoff to Flutter', () async {
    if (!probe.available) return markTestSkipped('$probe');
    final bitmap = clearedCanvas(probe.device!).transferToImageBitmap();
    final image = ui_web.createImageFromImageBitmap(bitmap as JSAny);
    final data = await (image as ui.Image).toByteData(
      format: ui.ImageByteFormat.rawRgba,
    );
    final rgba = data!.buffer.asUint8List();
    print('DIAG 3 createImageFromImageBitmap ${firstPixel(rgba)}');
    expect(rgba[0], closeTo(64, 1.5));
  });

  test('4. The async texture-source handoff to Flutter', () async {
    if (!probe.available) return markTestSkipped('$probe');
    final canvas = clearedCanvas(probe.device!);
    final image = await ui_web.createImageFromTextureSource(
      canvas as JSAny,
      width: _w,
      height: _h,
    );
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final rgba = data!.buffer.asUint8List();
    print('DIAG 4 createImageFromTextureSource ${firstPixel(rgba)}');
    expect(rgba[0], closeTo(64, 1.5));
  });
}
