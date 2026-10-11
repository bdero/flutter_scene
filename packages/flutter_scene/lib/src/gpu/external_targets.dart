import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;

/// Whether this backend can render into a color target it did not allocate
/// (see [wrapExternalColorTarget]).
///
/// True on the web backends, where a WebXR layer's framebuffer or texture
/// comes from the same context. False on Flutter GPU until the engine gains
/// an import path (flutter/flutter#192059).
/// {@category Rendering}
bool get externalColorTargetsSupported =>
    gpu.gpuHost.capabilities.externalColorTargets;

/// The platform graphics context the backend draws with, for a runtime that
/// has to bind it, or null where the backend keeps it private.
///
/// On the web this is the `WebGL2RenderingContext` (a `JSObject`) a WebXR
/// session's `XRWebGLLayer` is created from. On Flutter GPU it is null.
/// {@category Rendering}
Object? get nativeGraphicsContext => gpu.gpuHost.nativeGraphicsContext;

/// Wraps [handle], a platform color target, as a texture a scene can render
/// into through an `ExternalRenderTarget`.
///
/// On the web, [handle] is a `WebGLFramebuffer`
/// ([gpu.ExternalTargetHandleKind.framebuffer]) or a `WebGLTexture`
/// ([gpu.ExternalTargetHandleKind.texture]) created on [nativeGraphicsContext].
/// The caller keeps ownership and must not delete it while a scene renders
/// into it. Throws [UnsupportedError] where [externalColorTargetsSupported]
/// is false.
/// {@category Rendering}
gpu.Texture wrapExternalColorTarget(
  Object handle, {
  required int width,
  required int height,
  gpu.ExternalTargetHandleKind kind = gpu.ExternalTargetHandleKind.framebuffer,
  gpu.PixelFormat format = gpu.PixelFormat.r8g8b8a8UNormInt,
}) => gpu.gpuHost.wrapExternalColorTarget(
  handle,
  width: width,
  height: height,
  kind: kind,
  format: format,
);

/// A snapshot of [texture] as a platform image another graphics context can
/// draw, or null where the backend has none.
///
/// On the web this is an `ImageBitmap` (a `JSObject`), upright, taken through
/// the same path a scene's output takes to the screen; a second WebGL context
/// uploads it with `texImage2D`. On Flutter GPU it is null.
/// {@category Rendering}
Object? textureToPlatformImage(gpu.Texture texture) =>
    gpu.gpuHost.textureToPlatformImage(texture);
