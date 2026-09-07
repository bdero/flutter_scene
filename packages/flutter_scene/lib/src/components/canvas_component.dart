import 'package:flutter_scene/src/components/component.dart';
import 'package:scene/scene.dart' show UiRect;

/// Where a canvas's rectangle lives.
/// {@category UI}
enum CanvasRenderMode {
  /// Over the finished frame, at the view's own size. The canvas is drawn
  /// after the scene and is not in it: no camera moves it, nothing occludes
  /// it, and it is unaffected by fog, depth of field or tone mapping. What a
  /// HUD wants.
  screenSpaceOverlay,

  /// Over the frame, but sized and positioned through the rendering camera,
  /// so the canvas sits a fixed distance in front of it. Still flat to the
  /// viewer, but post-processing reaches it and scene geometry can be drawn
  /// in front of it.
  screenSpaceCamera,

  /// In the scene, as a quad with a size in world units. It has a position
  /// and an orientation like anything else, so it can hang on a wall, float
  /// beside a character, or be walked around.
  worldSpace,
}

/// A rectangle that UI is laid out inside.
///
/// The canvas answers one question — how big is the space children are
/// positioned in — and the answer differs by [renderMode]. A screen-space
/// canvas takes the view's size in logical pixels, scaled so that a layout
/// authored against [referenceSize] holds together on a screen of a different
/// size. A world-space canvas takes [worldSize] and is measured in the same
/// units as the rest of the scene.
///
/// Children position themselves with `RectTransformComponent`, against this
/// rectangle or against the rectangle of the nearest ancestor that has one.
/// {@category UI}
class CanvasComponent extends Component {
  CanvasComponent({
    this.renderMode = CanvasRenderMode.screenSpaceOverlay,
    double referenceWidth = 1920,
    double referenceHeight = 1080,
    double worldWidth = 1.6,
    double worldHeight = 0.9,
    this.cameraDistance = 1.0,
    this.sortOrder = 0,
  }) : referenceWidth = referenceWidth <= 0 ? 1 : referenceWidth,
       referenceHeight = referenceHeight <= 0 ? 1 : referenceHeight,
       worldWidth = worldWidth <= 0 ? 0.0 : worldWidth,
       worldHeight = worldHeight <= 0 ? 0.0 : worldHeight;

  /// Where the canvas is drawn.
  CanvasRenderMode renderMode;

  /// The size the layout was authored against, in canvas units.
  ///
  /// A screen-space canvas reports this size to its children whatever the
  /// view measures, and scales the result to fit. Without it every offset in
  /// a layout would mean a different fraction of the screen on every device.
  double referenceWidth;
  double referenceHeight;

  /// The canvas's size in world units, for [CanvasRenderMode.worldSpace].
  double worldWidth;
  double worldHeight;

  /// How far in front of the camera a [CanvasRenderMode.screenSpaceCamera]
  /// canvas sits, in world units.
  double cameraDistance;

  /// Draw order between canvases, low to high. Equal orders keep scene-graph
  /// order.
  int sortOrder;

  /// The rectangle children lay out inside.
  ///
  /// [viewWidth] and [viewHeight] are the view's logical size, and are
  /// ignored by a world-space canvas, which has a size of its own.
  UiRect rect({required double viewWidth, required double viewHeight}) =>
      switch (renderMode) {
        CanvasRenderMode.worldSpace => UiRect.size(worldWidth, worldHeight),
        // The reference size, not the view's: children are positioned in the
        // space the layout was authored in, and the whole canvas is scaled to
        // the view afterwards by [scaleFor].
        _ => UiRect.size(referenceWidth, referenceHeight),
      };

  /// How much to scale the laid-out canvas by to cover a [viewWidth] by
  /// [viewHeight] view.
  ///
  /// The smaller of the two ratios, so the reference rectangle always fits:
  /// scaling by the larger would push part of the layout off-screen, and a
  /// HUD that is off-screen on a narrow window is worse than one with room to
  /// spare. A world-space canvas is not scaled at all.
  double scaleFor({required double viewWidth, required double viewHeight}) {
    if (renderMode == CanvasRenderMode.worldSpace) return 1;
    final horizontal = viewWidth / referenceWidth;
    final vertical = viewHeight / referenceHeight;
    return horizontal < vertical ? horizontal : vertical;
  }
}
