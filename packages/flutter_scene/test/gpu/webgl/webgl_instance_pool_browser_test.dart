// The instance-data pool uploads typed lists straight to typed vertex buffers
// on the WebGL2 backend, with no byte-wise copy under dart2wasm.
//
//   flutter test --platform chrome \
//     test/gpu/webgl/webgl_instance_pool_browser_test.dart
//   flutter test --platform chrome --wasm \
//     test/gpu/webgl/webgl_instance_pool_browser_test.dart
//
// ignore_for_file: implementation_imports
@TestOn('browser')
library;

import 'dart:typed_data';

import 'package:flutter_scene/src/gpu/web/_gpu.dart' as gpu;
import 'package:flutter_scene/src/gpu/web/webgl/_webgl.dart';
import 'package:flutter_scene/src/render/frame_transients.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web/web.dart' as web;

void main() {
  if (gpu.useWebGpuBackend) {
    test('needs the WebGL2 shim', () {
      markTestSkipped('The shim is WebGPU in this build.');
    });
    return;
  }

  test('a typed emplacement lands in the buffer as written', () async {
    await gpu.initializeGpuBackend();
    final tracker = GpuSubmissionTracker();
    final pool = ImmediatePoolTransients(tracker, vertexData: true);
    final data = Float32List.fromList([for (var i = 0; i < 100; i++) i * 0.25]);
    final gl = (gpu.gpuContext as WebGlContext).gl;

    final view = pool.emplaceTyped(data);
    expect(view.lengthInBytes, data.lengthInBytes);
    expect(view.offsetInBytes, 0);
    expect(gl.getError(), web.WebGL2RenderingContext.NO_ERROR);

    final id = tracker.record();
    pool.beginFrame();
    tracker.complete(id);
    final recycled = pool.emplaceTyped(data);
    expect(identical(recycled.buffer, view.buffer), isTrue);
    expect(pool.bufferCount, 1);
  });
}
