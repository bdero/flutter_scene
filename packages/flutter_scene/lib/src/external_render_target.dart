import 'dart:async';

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
  ExternalRenderTarget.texture(this.color);

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
  }) : color = targets.wrapExternalColorTarget(
         handle,
         width: width,
         height: height,
         kind: kind,
         format: format,
       );

  /// The color texture views draw into.
  // TODO(xr-depth): take an optional depth texture too, written by a depth
  // copy pass with a declared convention, for runtimes that reproject from
  // depth (XR_KHR_composition_layer_depth, WebXR layers with depth).
  final gpu.Texture color;

  /// The target's width in pixels.
  int get width => color.width;

  /// The target's height in pixels.
  int get height => color.height;
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
  static FrameCompletion afterSubmissions() {
    final completer = Completer<void>();
    gpu.gpuContext.createCommandBuffer().submit(
      completionCallback: (_) {
        if (!completer.isCompleted) completer.complete();
      },
    );
    return FrameCompletion.rendered(completer.future);
  }
}
