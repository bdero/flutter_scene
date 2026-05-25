import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
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
// Flutter GPU exposes no backend query, so we use offscreen-MSAA support as a
// proxy: true on Metal/Vulkan, false on OpenGL ES. The web (WebGL2) shim does
// its own equivalent flip at the shim layer and reports true here, so this
// workaround stays off for it.
//
// TODO(flutter_scene): remove this once the GLES render-to-texture top-down
// fix (flutter/flutter#186556 or equivalent) is in the supported engines.
// See: <upstream issue link>.
bool get backendFlipsRenderTargetY => !gpu.gpuContext.doesSupportOffscreenMSAA;

/// Sign to multiply `gl_Position.y` by in the vertex shaders: -1 to flip when
/// [backendFlipsRenderTargetY], +1 otherwise. Used by passes whose vertex
/// shader takes no camera matrix (the full-screen passes); matrix-based passes
/// premultiply [applyBackendYFlip] instead.
double get backendYFlipSign => backendFlipsRenderTargetY ? -1.0 : 1.0;

/// Clip-space Y-flip premultiplied into the camera/light matrix sent to the
/// vertex shaders when [backendFlipsRenderTargetY], so `gl_Position.y` is
/// negated. Identity otherwise. The returned matrix is for the shader only;
/// frustum culling must keep using the unflipped transform.
Matrix4 applyBackendYFlip(Matrix4 cameraTransform) {
  if (!backendFlipsRenderTargetY) return cameraTransform;
  return Matrix4.diagonal3Values(1.0, -1.0, 1.0) * cameraTransform;
}

/// Inverts [w] when [backendFlipsRenderTargetY]: the vertex Y negation
/// reverses screen-space winding, so the cull winding must flip to keep the
/// same faces visible.
gpu.WindingOrder backendWinding(gpu.WindingOrder w) {
  if (!backendFlipsRenderTargetY) return w;
  return w == gpu.WindingOrder.clockwise
      ? gpu.WindingOrder.counterClockwise
      : gpu.WindingOrder.clockwise;
}
