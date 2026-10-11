// ignore_for_file: implementation_imports
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_scene/src/gpu/external_targets.dart';
import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';
import 'package:web/web.dart' as web;

// Reads the 8x8 RGBA pixels of [framebuffer] back through the shim's own
// context.
Uint8List _readBack(web.WebGL2RenderingContext gl, web.WebGLFramebuffer fbo) {
  final pixels = Uint8List(8 * 8 * 4);
  gl.bindFramebuffer(web.WebGL2RenderingContext.READ_FRAMEBUFFER, fbo);
  gl.readPixels(
    0,
    0,
    8,
    8,
    web.WebGL2RenderingContext.RGBA,
    web.WebGL2RenderingContext.UNSIGNED_BYTE,
    pixels.toJS,
  );
  gl.bindFramebuffer(web.WebGL2RenderingContext.READ_FRAMEBUFFER, null);
  return pixels;
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
  test('Flutter GPU reports no external targets', () {
    expect(externalColorTargetsSupported, isFalse);
    expect(nativeGraphicsContext, isNull);
    expect(
      () => wrapExternalColorTarget(Object(), width: 1, height: 1),
      throwsUnsupportedError,
    );
  }, skip: kIsWeb);

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
  }, skip: !kIsWeb);
}
