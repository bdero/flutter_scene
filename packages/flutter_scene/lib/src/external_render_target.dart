import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show internal;
import 'package:flutter_scene/src/gpu/external_targets.dart' as targets;
import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;

/// A color target the caller owns, which a `RenderView` renders into through
/// `Scene.renderViewsToTargets`.
///
/// The scene never allocates, resizes, samples, or disposes [color]; it only
/// draws into it. That is the contract a platform runtime's swapchain image
/// needs (a WebXR layer, later an OpenXR swapchain), and it also fits a
/// texture an application allocated itself. A `RenderView.viewport` on a
/// view with this target selects the region of [color] the view fills, so
/// two eyes can share one image.
///
/// ```dart
/// final target = ExternalRenderTarget.platform(
///   layer.framebuffer,
///   width: layer.framebufferWidth,
///   height: layer.framebufferHeight,
/// );
/// final views = [
///   RenderView(camera: leftEye, externalTarget: target,
///       viewport: const Rect.fromLTWH(0, 0, 0.5, 1)),
///   RenderView(camera: rightEye, externalTarget: target,
///       viewport: const Rect.fromLTWH(0.5, 0, 0.5, 1)),
/// ];
/// final frame = scene.renderViewsToTargets([RenderViewGroup(views)]);
/// ```
/// {@category Rendering}
class ExternalRenderTarget {
  /// Wraps [color], a texture the caller created with render-target usage.
  ExternalRenderTarget.texture(this.color, {this.backgroundColor})
    : surfaceFrame = null;

  /// Allocates a color target of [width] by [height] pixels this package's
  /// backend owns, for a caller that has nowhere else to render (an emulated
  /// XR layer without a framebuffer, a capture). It is shader-readable, so
  /// `color.asImage()` draws it onto a canvas afterwards.
  ExternalRenderTarget.allocate({
    required int width,
    required int height,
    this.backgroundColor,
  }) : surfaceFrame = null,
       color = gpu.gpuContext.createTexture(
         gpu.StorageMode.devicePrivate,
         width,
         height,
         enableRenderTargetUsage: true,
         enableShaderReadUsage: true,
       );

  /// Wraps a platform object the active backend can draw into, through
  /// `wrapExternalColorTarget` (see that function for what each backend
  /// accepts). Throws [UnsupportedError] where the backend cannot.
  ExternalRenderTarget.platform(
    Object handle, {
    required int width,
    required int height,
    gpu.ExternalTargetHandleKind kind =
        gpu.ExternalTargetHandleKind.framebuffer,
    gpu.PixelFormat format = gpu.PixelFormat.r8g8b8a8UNormInt,
    this.backgroundColor,
  }) : surfaceFrame = null,
       color = targets.wrapExternalColorTarget(
         handle,
         width: width,
         height: height,
         kind: kind,
         format: format,
       );

  /// Leases [frame], one image of a surface the platform presents (a
  /// swapchain image an engine or runtime lends out).
  ///
  /// The scene ends the lease. A frame that renders presents [frame] on its
  /// last GPU submission, and a frame that is skipped or throws discards it,
  /// so the surface always gets its image back. The target is then spent, so
  /// build a new one around the next frame the surface vends.
  ///
  /// ```dart
  /// final frame = surface.acquireNextFrame();
  /// if (frame == null) return;
  /// final target = ExternalRenderTarget.surfaceFrame(frame);
  /// scene.renderViewsToTargets([
  ///   RenderViewGroup([RenderView(camera: eye, externalTarget: target)]),
  /// ]);
  /// ```
  ExternalRenderTarget.surfaceFrame(
    gpu.GpuSurfaceFrame frame, {
    this.backgroundColor,
  }) : surfaceFrame = frame,
       color = frame.colorTexture;

  /// The color texture views draw into.
  // TODO(xr-depth): take an optional depth texture too, written by a depth
  // copy pass with a declared convention, for runtimes that reproject from
  // depth (XR_KHR_composition_layer_depth, WebXR layers with depth).
  final gpu.Texture color;

  /// The surface frame this target leases, or null for a target the caller
  /// keeps.
  final gpu.GpuSurfaceFrame? surfaceFrame;

  /// A color composited under the finished image, or null to keep the
  /// scene's own alpha.
  ///
  /// It sits behind everything the scene drew, untouched by lighting,
  /// exposure or tone mapping, the way a widget behind a `SceneView` does.
  /// An opaque color makes every pixel of the target opaque, which a runtime
  /// that reads alpha as coverage needs when the scene has no skybox.
  ui.Color? backgroundColor;

  /// The target's width in pixels.
  int get width => color.width;

  /// The target's height in pixels.
  int get height => color.height;

  /// Whether [color] encodes sRGB on write (an sRGB swapchain format). The
  /// scene then writes linear color and lets the attachment encode it, so
  /// the stored image matches what a plain target of the same scene holds.
  bool get encodesSrgb => switch (color.format) {
    gpu.PixelFormat.r8g8b8a8UNormIntSRGB ||
    gpu.PixelFormat.b8g8r8a8UNormIntSRGB => true,
    _ => false,
  };

  gpu.GpuPresentStatus? _presentStatus;
  bool _leaseEnded = false;

  /// What presenting [surfaceFrame] reported, or null before the scene has
  /// presented it, after a discard, and for a target without one.
  gpu.GpuPresentStatus? get presentStatus => _presentStatus;

  /// Whether [surfaceFrame] was presented or discarded, after which the
  /// target cannot be rendered into. Always false without a surface frame.
  bool get isSpent => _leaseEnded;

  /// Presents [surfaceFrame] on [commandBuffer], which the caller submits.
  @internal
  void presentSurfaceFrame(gpu.CommandBuffer commandBuffer) {
    final frame = surfaceFrame;
    if (frame == null || _leaseEnded) return;
    // A present that throws leaves the lease open, for the discard to end.
    _presentStatus = frame.present(commandBuffer);
    _leaseEnded = true;
  }

  /// Returns [surfaceFrame] to its surface unpresented.
  @internal
  void discardSurfaceFrame() {
    final frame = surfaceFrame;
    if (frame == null || _leaseEnded) return;
    _leaseEnded = true;
    frame.discard();
  }
}

/// What `Scene.renderViewsToTargets` reports about the frame it was asked to
/// render.
/// {@category Rendering}
class FrameCompletion {
  /// A frame whose GPU work was submitted; [whenGpuDone] completes when it
  /// has executed.
  FrameCompletion.rendered(this.whenGpuDone) : skipped = false;

  /// A frame the scene did not draw (its resources were still loading, or
  /// there was nothing to draw). [whenGpuDone] is already complete, so a
  /// runtime loop can await it unconditionally.
  FrameCompletion.skipped()
    : skipped = true,
      whenGpuDone = Future<void>.value();

  /// Whether the scene drew nothing this frame. The targets hold whatever
  /// they held before.
  final bool skipped;

  /// Completes once the GPU has finished every command the frame submitted,
  /// so a runtime may release the targets (an OpenXR swapchain image) or
  /// read them back.
  ///
  /// This is true GPU completion on Metal and Vulkan and in-order completion
  /// on WebGL. On OpenGL ES through Flutter GPU it completes when the
  /// commands reach the driver, not when they finish, since the engine exposes
  /// no fence yet (part of flutter/flutter#192059).
  final Future<void> whenGpuDone;

  /// Signals completion once a trailing empty submission finishes, which on
  /// an in-order queue is after everything submitted before it.
  ///
  /// The surface frames among [present] are presented on that submission, so
  /// each surface learns its image is final when the frame's work is.
  static FrameCompletion afterSubmissions({
    Iterable<ExternalRenderTarget> present = const [],
  }) {
    final completer = Completer<void>();
    final commandBuffer = gpu.gpuContext.createCommandBuffer();
    for (final target in present) {
      target.presentSurfaceFrame(commandBuffer);
    }
    commandBuffer.submit(
      completionCallback: (_) {
        if (!completer.isCompleted) completer.complete();
      },
    );
    return FrameCompletion.rendered(completer.future);
  }
}
