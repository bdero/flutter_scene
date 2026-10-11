import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:flutter_scene/gpu.dart' as gpu;
import 'package:vector_math/vector_math.dart';
import 'package:web/web.dart' as web;

// The IWER bundle, loaded by web/index.html as a classic script.
extension type _Iwer._(JSObject _) implements JSObject {
  @JS('XRDevice')
  external JSFunction get xrDevice;
  external JSObject get metaQuest3;
}

extension type _XrDevice._(JSObject _) implements JSObject {
  external _Vector3 get position;
  external _Quaternion get quaternion;
  external void installRuntime(JSObject options);
}

extension type _Vector3._(JSObject _) implements JSObject {
  external void set(num x, num y, num z);
}

extension type _Quaternion._(JSObject _) implements JSObject {
  external void set(num x, num y, num z, num w);
}

_XrDevice? _device;

bool get emulatedXrSupported => globalContext.has('IWER');

/// Installs a stereo Quest 3 emulation over `navigator.xr` (forced, since
/// desktop Chrome exposes an inert native `navigator.xr`) and moves its head
/// to the given pose. Repeated calls only move the head.
Future<void> installEmulatedXr({
  required Vector3 position,
  required Quaternion orientation,
}) async {
  var device = _device;
  if (device == null) {
    final iwer = globalContext['IWER'] as _Iwer?;
    if (iwer == null) {
      throw StateError(
        'IWER is not loaded; web/index.html must include '
        'third_party/iwer/iwer.min.js.',
      );
    }
    final options = JSObject()..['stereoEnabled'] = true.toJS;
    device = _device =
        iwer.xrDevice.callAsConstructor<JSObject>(iwer.metaQuest3, options)
            as _XrDevice;
    device.installRuntime(JSObject()..['forceInstall'] = true.toJS);
  }
  device.position.set(position.x, position.y, position.z);
  device.quaternion.set(
    orientation.x,
    orientation.y,
    orientation.z,
    orientation.w,
  );
}

/// The emulator sizes its layer to the window's CSS pixels.
({int width, int height}) emulatedLayerSize() =>
    (width: web.window.innerWidth, height: web.window.innerHeight);

web.WebGL2RenderingContext get _gl => switch (gpu.nativeGraphicsContext) {
  final web.WebGL2RenderingContext gl => gl,
  _ => throw StateError('The web backend has no WebGL2 context.'),
};

({Object framebuffer, Object texture}) createBackendFramebuffer(
  int width,
  int height,
) {
  final gl = _gl;
  final texture = gl.createTexture()!;
  gl.bindTexture(web.WebGL2RenderingContext.TEXTURE_2D, texture);
  gl.texStorage2D(
    web.WebGL2RenderingContext.TEXTURE_2D,
    1,
    web.WebGL2RenderingContext.RGBA8,
    width,
    height,
  );
  final framebuffer = gl.createFramebuffer()!;
  gl.bindFramebuffer(web.WebGL2RenderingContext.FRAMEBUFFER, framebuffer);
  gl.framebufferTexture2D(
    web.WebGL2RenderingContext.FRAMEBUFFER,
    web.WebGL2RenderingContext.COLOR_ATTACHMENT0,
    web.WebGL2RenderingContext.TEXTURE_2D,
    texture,
    0,
  );
  gl.bindFramebuffer(web.WebGL2RenderingContext.FRAMEBUFFER, null);
  return (framebuffer: framebuffer, texture: texture);
}

Uint8List readBackendFramebuffer(Object framebuffer, int width, int height) {
  final gl = _gl;
  final rows = Uint8List(width * height * 4);
  gl.bindFramebuffer(
    web.WebGL2RenderingContext.READ_FRAMEBUFFER,
    framebuffer as web.WebGLFramebuffer,
  );
  gl.readPixels(
    0,
    0,
    width,
    height,
    web.WebGL2RenderingContext.RGBA,
    web.WebGL2RenderingContext.UNSIGNED_BYTE,
    rows.toJS,
  );
  gl.bindFramebuffer(web.WebGL2RenderingContext.READ_FRAMEBUFFER, null);
  // GL reads bottom-up.
  final stride = width * 4;
  final flipped = Uint8List(rows.length);
  for (var y = 0; y < height; y++) {
    flipped.setRange(
      y * stride,
      (y + 1) * stride,
      rows,
      (height - 1 - y) * stride,
    );
  }
  return flipped;
}

void deleteBackendFramebuffer(({Object framebuffer, Object texture}) target) {
  final gl = _gl;
  gl.deleteFramebuffer(target.framebuffer as web.WebGLFramebuffer);
  gl.deleteTexture(target.texture as web.WebGLTexture);
}
