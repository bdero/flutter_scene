// ignore_for_file: implementation_imports
@TestOn('browser')
library;

import 'dart:js_interop';
import 'dart:typed_data';
import 'dart:ui' show Color;

import 'package:flutter_scene/scene.dart';
import 'package:flutter_scene/src/gpu/external_targets.dart';
import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' hide Colors;
import 'package:web/web.dart' as web;

// Reads the 8x8 RGBA pixels of [framebuffer] back through the shim's own
// context. Into a JS array, since dart2wasm's `toJS` hands GL a copy.
Uint8List _readBack(web.WebGL2RenderingContext gl, web.WebGLFramebuffer fbo) {
  final pixels = JSUint8Array.withLength(8 * 8 * 4);
  gl.bindFramebuffer(web.WebGL2RenderingContext.READ_FRAMEBUFFER, fbo);
  gl.readPixels(
    0,
    0,
    8,
    8,
    web.WebGL2RenderingContext.RGBA,
    web.WebGL2RenderingContext.UNSIGNED_BYTE,
    pixels,
  );
  gl.bindFramebuffer(web.WebGL2RenderingContext.READ_FRAMEBUFFER, null);
  return pixels.toDart;
}

// A GL texture with an RGBA8 8x8 store and a framebuffer around it.
({web.WebGLTexture texture, web.WebGLFramebuffer fbo}) _glTarget(
  web.WebGL2RenderingContext gl,
) {
  final texture = gl.createTexture()!;
  gl.bindTexture(web.WebGL2RenderingContext.TEXTURE_2D, texture);
  gl.texStorage2D(
    web.WebGL2RenderingContext.TEXTURE_2D,
    1,
    web.WebGL2RenderingContext.RGBA8,
    8,
    8,
  );
  final fbo = gl.createFramebuffer()!;
  gl.bindFramebuffer(web.WebGL2RenderingContext.FRAMEBUFFER, fbo);
  gl.framebufferTexture2D(
    web.WebGL2RenderingContext.FRAMEBUFFER,
    web.WebGL2RenderingContext.COLOR_ATTACHMENT0,
    web.WebGL2RenderingContext.TEXTURE_2D,
    texture,
    0,
  );
  gl.bindFramebuffer(web.WebGL2RenderingContext.FRAMEBUFFER, null);
  return (texture: texture, fbo: fbo);
}

// Presents [frame] the way a renderer does, on a buffer submitted after.
void _present(gpu.GpuSurfaceFrame frame) {
  final commandBuffer = gpu.gpuContext.createCommandBuffer();
  frame.present(commandBuffer);
  commandBuffer.submit();
}

void _clearInto(gpu.Texture target, Vector4 color) {
  final commandBuffer = gpu.gpuContext.createCommandBuffer();
  commandBuffer.createRenderPass(
    gpu.RenderTarget.singleColor(
      gpu.ColorAttachment(texture: target, clearValue: color),
    ),
  );
  commandBuffer.submit();
}

void main() {
  // A scene listens for memory pressure through the binding.
  TestWidgetsFlutterBinding.ensureInitialized();

  group('web external targets', () {
    test('a wrapped framebuffer takes a render pass', () async {
      await gpu.initializeGpuBackend();
      expect(externalColorTargetsSupported, isTrue);
      final gl = nativeGraphicsContext! as web.WebGL2RenderingContext;
      final glTarget = _glTarget(gl);
      final target = wrapExternalColorTarget(
        glTarget.fbo,
        width: 8,
        height: 8,
        kind: gpu.ExternalTargetHandleKind.framebuffer,
      );
      expect(target.enableRenderTargetUsage, isTrue);
      expect(target.enableShaderReadUsage, isFalse);
      _clearInto(target, Vector4(1.0, 0.5, 0.0, 1.0));
      final pixels = _readBack(gl, glTarget.fbo);
      expect(pixels[0], 255);
      expect(pixels[1], inInclusiveRange(126, 129));
      expect(pixels[2], 0);
      expect(pixels[3], 255);
    });

    test('a wrapped texture attaches to the shim\'s own framebuffer', () async {
      await gpu.initializeGpuBackend();
      final gl = nativeGraphicsContext! as web.WebGL2RenderingContext;
      final glTarget = _glTarget(gl);
      final target = wrapExternalColorTarget(
        glTarget.texture,
        width: 8,
        height: 8,
        kind: gpu.ExternalTargetHandleKind.texture,
      );
      expect(target.enableShaderReadUsage, isTrue);
      _clearInto(target, Vector4(0.0, 0.0, 1.0, 1.0));
      final pixels = _readBack(gl, glTarget.fbo);
      expect(pixels[0], 0);
      expect(pixels[1], 0);
      expect(pixels[2], 255);
      expect(pixels[3], 255);
    });
  });

  group('web image surfaces', () {
    test('a presented frame becomes the current image', () async {
      await gpu.initializeGpuBackend();
      final surface = gpu.gpuContext.createImageSurface(8, 8);
      expect(surface.currentImage, isNull);
      final frame = surface.acquireNextFrame();
      expect(frame.colorTexture.width, 8);
      _clearInto(frame.colorTexture, Vector4(0.0, 1.0, 0.0, 1.0));
      final commandBuffer = gpu.gpuContext.createCommandBuffer();
      expect(frame.present(commandBuffer), gpu.GpuPresentStatus.success);
      commandBuffer.submit();
      final image = surface.currentImage!;
      expect((image.width, image.height), (8, 8));
      image.dispose();
      // A second read is its own handle onto the same frame.
      surface.currentImage!.dispose();
      expect(() => frame.present(commandBuffer), throwsStateError);
      // Discarding after a present changes nothing.
      frame.discard();
      expect(surface.currentImage, isNotNull);
    });

    test('never hands out the image on show, and reuses the rest', () async {
      await gpu.initializeGpuBackend();
      final surface = gpu.gpuContext.createImageSurface(8, 8);
      final first = surface.acquireNextFrame();
      _present(first);
      final second = surface.acquireNextFrame();
      expect(
        identical(second.colorTexture, first.colorTexture),
        isFalse,
        reason: 'the presented image was handed out again',
      );
      second.discard();
      // The discarded texture is free again; the shown one still is not.
      final third = surface.acquireNextFrame();
      expect(identical(third.colorTexture, second.colorTexture), isTrue);
      expect(surface.debugBackingTextureCount, 2);
      _present(third);
      final fourth = surface.acquireNextFrame();
      expect(identical(fourth.colorTexture, first.colorTexture), isTrue);
      fourth.discard();
      expect(surface.debugBackingTextureCount, 2);
    });

    test('resizes between frames only', () async {
      await gpu.initializeGpuBackend();
      final surface = gpu.gpuContext.createImageSurface(8, 8);
      final held = surface.acquireNextFrame();
      expect(() => surface.resize(16, 4), throwsStateError);
      held.discard();
      surface.resize(16, 4);
      final frame = surface.acquireNextFrame();
      expect((frame.colorTexture.width, frame.colorTexture.height), (16, 4));
      frame.discard();
      expect(surface.debugBackingTextureCount, 1);
      expect(() => surface.resize(0, 4), throwsArgumentError);
    });
  });

  group('surface frame targets', () {
    // No shader bundle is served to this test, so a scene never becomes
    // ready and every frame is skipped, which is the path under test.
    test('a skipped frame hands its lease back', () async {
      await gpu.initializeGpuBackend();
      final surface = gpu.gpuContext.createImageSurface(8, 8);
      final frame = surface.acquireNextFrame();
      final target = ExternalRenderTarget.surfaceFrame(frame);
      expect(target.surfaceFrame, same(frame));
      expect((target.width, target.height), (8, 8));
      expect(target.isSpent, isFalse);

      final scene = Scene();
      final completion = scene.renderViewsToTargets([
        RenderViewGroup([
          RenderView(camera: PerspectiveCamera(), externalTarget: target),
        ]),
      ]);
      expect(completion.skipped, isTrue);
      expect(target.isSpent, isTrue);
      expect(target.presentStatus, isNull);
      expect(surface.currentImage, isNull);
      // The surface got its image back.
      final again = surface.acquireNextFrame();
      expect(identical(again.colorTexture, frame.colorTexture), isTrue);
      again.discard();

      // A spent target does not render again.
      expect(
        () => scene.renderViewsToTargets([
          RenderViewGroup([
            RenderView(camera: PerspectiveCamera(), externalTarget: target),
          ]),
        ]),
        throwsStateError,
      );
    });

    test('a call that throws hands its lease back', () async {
      await gpu.initializeGpuBackend();
      final surface = gpu.gpuContext.createImageSurface(8, 8);
      final target = ExternalRenderTarget.surfaceFrame(
        surface.acquireNextFrame(),
      );
      expect(
        () => Scene().renderViewsToTargets([
          RenderViewGroup([
            RenderView(camera: PerspectiveCamera(), externalTarget: target),
            RenderView(camera: PerspectiveCamera()),
          ]),
        ]),
        throwsArgumentError,
      );
      expect(target.isSpent, isTrue);
      expect(target.presentStatus, isNull);
    });

    test('reports an sRGB format and carries a background', () async {
      await gpu.initializeGpuBackend();
      final plain = ExternalRenderTarget.allocate(width: 4, height: 4);
      expect(plain.encodesSrgb, isFalse);
      expect(plain.backgroundColor, isNull);
      expect(plain.isSpent, isFalse);
      final srgb = ExternalRenderTarget.texture(
        gpu.gpuContext.createTexture(
          gpu.StorageMode.devicePrivate,
          4,
          4,
          format: gpu.PixelFormat.r8g8b8a8UNormIntSRGB,
        ),
        backgroundColor: const Color(0xFF000000),
      );
      expect(srgb.encodesSrgb, isTrue);
      expect(srgb.backgroundColor, const Color(0xFF000000));
    });
  });
}
