import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_scene/src/shaders.dart';
import 'package:vector_math/vector_math.dart';

// TEMPORARY render-to-texture Y-flip workaround for the OpenGL ES backend.
//
// flutter_scene (like Impeller's Metal and Vulkan backends) assumes
// render-to-texture content is stored top-down. Impeller's OpenGL ES backend
// stores it bottom-up, and the upstream fix that makes GLES match
// (flutter/flutter#186556) is not yet in the engines we build against. So on
// GLES, flutter_scene must absorb the difference itself: negate gl_Position.y
// in every offscreen pass (storing top-down) and invert cull winding to
// compensate (the Y negation reverses screen-space winding).
//
// Flutter GPU exposes no backend query, and capability flags don't reliably
// separate GLES from Vulkan (both use standard formats; offscreen-MSAA support
// is true on GLES3/llvmpipe). So instead of guessing, [probeBackendYFlip]
// measures the orientation directly: it renders a known top/bottom pattern to
// an offscreen texture and reads it back. The web (WebGL2) shim does its own
// equivalent flip at the shim layer, so the probe measures top-down there too
// and this workaround stays off for it.
//
// TODO(flutter_scene): remove this once the GLES render-to-texture top-down
// fix (flutter/flutter#186556 or equivalent) is in the supported engines.
// See: <upstream issue link>.

bool _flipsRenderTargetY = false;
bool _probed = false;

/// Whether this backend stores render-to-texture content bottom-up and so
/// needs flutter_scene's Y-flip. Defaults to `false` until [probeBackendYFlip]
/// has measured it; the renderers read this each frame.
bool get backendFlipsRenderTargetY => _flipsRenderTargetY;

/// Sign to multiply `gl_Position.y` by in the full-screen passes' vertex
/// shader: -1 to flip when [backendFlipsRenderTargetY], +1 otherwise.
/// Matrix-based passes premultiply [applyBackendYFlip] instead.
double get backendYFlipSign => _flipsRenderTargetY ? -1.0 : 1.0;

/// Clip-space Y-flip premultiplied into the camera/light matrix sent to the
/// vertex shaders when [backendFlipsRenderTargetY], so `gl_Position.y` is
/// negated. Identity otherwise. The returned matrix is for the shader only;
/// frustum culling must keep using the unflipped transform.
Matrix4 applyBackendYFlip(Matrix4 cameraTransform) {
  if (!_flipsRenderTargetY) return cameraTransform;
  return Matrix4.diagonal3Values(1.0, -1.0, 1.0) * cameraTransform;
}

/// Inverts [w] when [backendFlipsRenderTargetY]: the vertex Y negation
/// reverses screen-space winding, so the cull winding must flip to keep the
/// same faces visible.
gpu.WindingOrder backendWinding(gpu.WindingOrder w) {
  if (!_flipsRenderTargetY) return w;
  return w == gpu.WindingOrder.clockwise
      ? gpu.WindingOrder.counterClockwise
      : gpu.WindingOrder.clockwise;
}

// A small full-screen quad (6 vec2 NDC positions) for the probe pass.
gpu.DeviceBuffer? _probeQuad;
gpu.BufferView _probeQuadView() {
  final buffer =
      _probeQuad ??= gpu.gpuContext.createDeviceBufferWithCopy(
        ByteData.sublistView(
          Float32List.fromList(<double>[
            -1.0, -1.0, 1.0, -1.0, -1.0, 1.0, //
            -1.0, 1.0, 1.0, -1.0, 1.0, 1.0, //
          ]),
        ),
      );
  return gpu.BufferView(buffer, offsetInBytes: 0, lengthInBytes: 6 * 2 * 4);
}

/// Renders a top/bottom pattern to an offscreen texture and reads it back to
/// determine [backendFlipsRenderTargetY]. Idempotent and cheap (runs once).
///
/// Triggered from the first [Scene.render] rather than initialization: the
/// OpenGL ES backend brings its GPU context up lazily on the raster thread
/// only after the first frame, so the probe's render pass must run during a
/// frame. The render and submit happen synchronously here; the read-back
/// completes asynchronously and updates [backendFlipsRenderTargetY] for
/// subsequent frames (the first frame uses the default, no flip).
void probeBackendYFlip() {
  if (_probed) return;
  _probed = true;

  const size = 4;
  final texture = gpu.gpuContext.createTexture(
    gpu.StorageMode.devicePrivate,
    size,
    size,
    format: gpu.PixelFormat.r8g8b8a8UNormInt,
    enableRenderTargetUsage: true,
    enableShaderReadUsage: true,
    coordinateSystem: gpu.TextureCoordinateSystem.renderToTexture,
  );

  final vertexShader = baseShaderLibrary['FullscreenVertex']!;
  final fragmentShader = baseShaderLibrary['YFlipProbeFragment']!;
  final commandBuffer = gpu.gpuContext.createCommandBuffer();
  final renderPass = commandBuffer.createRenderPass(
    gpu.RenderTarget.singleColor(
      gpu.ColorAttachment(texture: texture, clearValue: Vector4.zero()),
    ),
  );
  renderPass.bindPipeline(
    gpu.gpuContext.createRenderPipeline(vertexShader, fragmentShader),
  );
  renderPass.bindVertexBuffer(_probeQuadView(), 6);
  // FlipInfo +1: measure the raw backend orientation, without this workaround.
  final flipInfo = Float32List(4)..[0] = 1.0;
  renderPass.bindUniform(
    vertexShader.getUniformSlot('FlipInfo'),
    gpu.gpuContext.createHostBuffer().emplace(ByteData.sublistView(flipInfo)),
  );
  renderPass.draw();
  commandBuffer.submit();

  // Read back asynchronously: top row red means the backend stored the
  // top-of-NDC fragment at row 0 (top-down, no flip); otherwise it stored it
  // bottom-up and we must flip.
  final image = texture.asImage();
  image.toByteData(format: ui.ImageByteFormat.rawRgba).then((bytes) {
    if (bytes == null) return;
    _flipsRenderTargetY = bytes.getUint8(0) < 128;
  });
}
