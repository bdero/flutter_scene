import 'dart:ui' as ui;

import 'package:flutter_scene/src/camera.dart';
import 'package:flutter_scene/src/render/render_layers.dart';
import 'package:flutter_scene/src/render_texture.dart';
import 'package:flutter_scene/src/scene.dart' show AntiAliasingMode, Scene;

/// One view of a `Scene`: a [camera] plus where and how its image is drawn.
///
/// A scene can be rendered as a list of views (split-screen, picture-in-
/// picture, and more). Each view binds a camera to a [target] (an offscreen
/// [RenderTexture], or null for the screen), a [viewport] sub-rectangle of
/// the target, a [layerMask] selecting which nodes it sees, an [order]
/// controlling how overlapping views composite, and an optional
/// [antiAliasingMode] override.
/// {@category Rendering}
class RenderView {
  /// Creates a render view for [camera].
  RenderView({
    required this.camera,
    this.target,
    this.viewport,
    this.layerMask = kRenderLayerAll,
    this.order = 0,
    this.antiAliasingMode,
    this.renderScale,
    this.filterQuality,
  }) : assert(
         renderScale == null || (renderScale.isFinite && renderScale > 0.0),
         'renderScale must be a positive, finite number.',
       );

  /// The camera whose view and projection this view renders.
  Camera camera;

  /// The offscreen texture this view renders into, or null to render to
  /// the screen.
  ///
  /// A view with a target renders whenever the owning scene renders,
  /// subject to the target's `RenderTexture.update` policy. Add such views
  /// to `Scene.views` so they render without being passed to every
  /// `Scene.renderViews` call.
  RenderTexture? target;

  /// The sub-rectangle of the render target this view draws into, in
  /// normalized coordinates (`0..1`, with a top-left origin). `null` fills
  /// the whole target.
  ///
  /// Ignored when [target] is set; a view renders the full extent of its
  /// render texture.
  // TODO(rendertarget): support viewport sub-rects on texture targets
  // (requires compositing multiple views into one texture).
  ui.Rect? viewport;

  /// A bitmask selecting which `Node` layers this view renders. A node is
  /// drawn only when `node.layers & layerMask != 0`. Defaults to
  /// [kRenderLayerAll] (every layer).
  int layerMask;

  /// The compositing order among views sharing a target: a lower [order]
  /// renders first, a higher one draws on top.
  int order;

  /// The anti-aliasing strategy for this view, or null (the default) to
  /// inherit the scene's `Scene.antiAliasingMode`.
  ///
  /// Resolution against backend support follows the same rules as the
  /// scene-level setting (an unsupported [AntiAliasingMode.msaa] renders
  /// with FXAA); check [Scene.isAntiAliasingModeSupported] up front.
  AntiAliasingMode? antiAliasingMode;

  /// Scales the resolution this view renders at relative to the display's
  /// native resolution, or null (the default) to inherit the scene's
  /// `Scene.renderScale`.
  ///
  /// Ignored when [target] is set; a render texture's resolution is its
  /// explicit size.
  double? renderScale;

  /// The sampling quality this view's image is composited onto the canvas
  /// with, or null (the default) to inherit the scene's
  /// `Scene.filterQuality` (which documents how the values map to
  /// concrete sampling modes per backend).
  ///
  /// Ignored when [target] is set; display filtering of a render texture
  /// belongs to its consumer (for example `RenderTextureView`).
  ui.FilterQuality? filterQuality;
}
