// The WebGPU skeleton end to end: device, a clear-only pass, and the
// synchronous handoff to a ui.Image.
//
//   flutter test --platform chrome test/gpu/webgpu/webgpu_skeleton_browser_test.dart
//   flutter test --platform chrome --wasm test/gpu/webgpu/webgpu_skeleton_browser_test.dart
//
// The first runs under CanvasKit, the second under Skwasm. Skips (with the
// probe's reason printed) where the browser exposes no WebGPU device.
//
// ignore_for_file: implementation_imports
@TestOn('browser')
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_scene/src/gpu/webgpu/webgpu_device.dart';
import 'package:flutter_scene/src/gpu/webgpu/webgpu_presenter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late WebGpuProbe probe;

  setUpAll(() async {
    probe = await WebGpuDevice.request(allowFallbackAdapter: true);
    // ignore: avoid_print
    print('WEBGPU_PROBE $probe');
  });

  Future<Uint8List> pixels(ui.Image image) async {
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    return data!.buffer.asUint8List();
  }

  test(
    'a cleared frame reaches Flutter synchronously, frame after frame',
    () async {
      if (!probe.available) {
        markTestSkipped('$probe');
        return;
      }
      final presenter = WebGpuPresenter(probe.device!);
      // Distinct colors so a stale or reused canvas texture shows up.
      const colors = [
        (0.25, 0.5, 0.75, 1.0),
        (1.0, 0.0, 0.0, 1.0),
        (0.0, 1.0, 0.0, 1.0),
      ];
      for (final (r, g, b, a) in colors) {
        final image = presenter.clearToImageSync(16, 8, r: r, g: g, b: b, a: a);
        expect(image.width, 16);
        expect(image.height, 8);
        final rgba = await pixels(image);
        for (final i in [0, (rgba.length ~/ 4 - 1) * 4]) {
          expect(rgba[i], closeTo(r * 255, 1.5));
          expect(rgba[i + 1], closeTo(g * 255, 1.5));
          expect(rgba[i + 2], closeTo(b * 255, 1.5));
          expect(rgba[i + 3], closeTo(a * 255, 1.5));
        }
        image.dispose();
      }
      // A resize reconfigures the canvas.
      final resized = presenter.clearToImageSync(5, 3, r: 0, g: 0, b: 1, a: 1);
      expect((resized.width, resized.height), (5, 3));
      expect((await pixels(resized))[2], closeTo(255, 1.5));
      presenter.dispose();
      // ignore: avoid_print
      print('WEBGPU_PRESENT ok (${presenter.format})');
    },
  );
}
