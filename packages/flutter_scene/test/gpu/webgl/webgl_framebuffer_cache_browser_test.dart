// The WebGL2 backend keeps a render target's framebuffer across frames, even
// when a frame renders to more targets than the cache's capacity once held.
//
//   flutter test --platform chrome \
//     test/gpu/webgl/webgl_framebuffer_cache_browser_test.dart
//   flutter test --platform chrome --wasm \
//     test/gpu/webgl/webgl_framebuffer_cache_browser_test.dart
//
// ignore_for_file: implementation_imports
@TestOn('browser')
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter_scene/src/gpu/web/_gpu.dart' as gpu;
import 'package:flutter_test/flutter_test.dart';

/// Counts calls to the named `WebGL2RenderingContext` methods.
class _GlCallCounter {
  _GlCallCounter(List<String> names) {
    final prototype =
        (globalContext['WebGL2RenderingContext'] as JSObject)['prototype']
            as JSObject;
    for (final name in names) {
      counts[name] = 0;
      final original = prototype[name] as JSFunction;
      _restore.add(() => prototype[name] = original);
      prototype[name] = ((JSObject self, [JSAny? a]) {
        counts[name] = counts[name]! + 1;
        return original.callAsFunction(self, a);
      }).toJSCaptureThis;
    }
  }

  final Map<String, int> counts = {};
  final List<void Function()> _restore = [];

  void reset() => counts.updateAll((_, _) => 0);

  void dispose() {
    for (final restore in _restore) {
      restore();
    }
  }
}

void main() {
  if (gpu.useWebGpuBackend) {
    test('needs the WebGL2 shim', () {
      markTestSkipped('The shim is WebGPU in this build.');
    });
    return;
  }

  test('a frame with many render targets reuses their framebuffers', () async {
    await gpu.initializeGpuBackend();
    final counter = _GlCallCounter([
      'createFramebuffer',
      'checkFramebufferStatus',
    ]);
    addTearDown(counter.dispose);

    // More distinct targets than the cache used to hold before emptying.
    final targets = [
      for (var i = 0; i < 100; i++)
        gpu.gpuContext.createTexture(gpu.StorageMode.devicePrivate, 4, 4),
    ];
    void renderFrame() {
      final commands = gpu.gpuContext.createCommandBuffer();
      for (final target in targets) {
        commands.createRenderPass(
          gpu.RenderTarget.singleColor(gpu.ColorAttachment(texture: target)),
        );
      }
      commands.submit();
    }

    renderFrame();
    expect(counter.counts['createFramebuffer'], targets.length);

    counter.reset();
    for (var frame = 0; frame < 3; frame++) {
      renderFrame();
    }
    expect(counter.counts, {
      'createFramebuffer': 0,
      'checkFramebufferStatus': 0,
    });

    // Releasing a target drops its framebuffer, so a new one is built.
    gpu.gpuHost.releaseTexture(targets.first);
    targets.first = gpu.gpuContext.createTexture(
      gpu.StorageMode.devicePrivate,
      4,
      4,
    );
    renderFrame();
    expect(counter.counts['createFramebuffer'], 1);

    targets.forEach(gpu.gpuHost.releaseTexture);
  });
}
