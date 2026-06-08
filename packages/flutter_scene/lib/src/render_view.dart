import 'dart:ui' as ui;

import 'package:flutter_scene/src/camera.dart';
import 'package:flutter_scene/src/render/render_layers.dart';

/// One view of a `Scene`: a [camera] plus where and how its image is drawn.
///
/// A scene can be rendered as a list of views (split-screen, picture-in-
/// picture, and more). Each view binds a camera to a [viewport]
/// sub-rectangle of the target, a [layerMask] selecting which nodes it
/// sees, and an [order] controlling how overlapping views composite.
class RenderView {
  /// Creates a render view for [camera].
  RenderView({
    required this.camera,
    this.viewport,
    this.layerMask = kRenderLayerAll,
    this.order = 0,
  });

  /// The camera whose view and projection this view renders.
  Camera camera;

  /// The sub-rectangle of the render target this view draws into, in
  /// normalized coordinates (`0..1`, with a top-left origin). `null` fills
  /// the whole target.
  ui.Rect? viewport;

  /// A bitmask selecting which `Node` layers this view renders. A node is
  /// drawn only when `node.layers & layerMask != 0`. Defaults to
  /// [kRenderLayerAll] (every layer).
  int layerMask;

  /// The compositing order among views sharing a target: a lower [order]
  /// renders first, a higher one draws on top.
  int order;
}
