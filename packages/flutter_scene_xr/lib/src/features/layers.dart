import 'package:flutter_scene/scene.dart' show ExternalRenderTarget;

import 'package:flutter_scene_xr/src/xr_pose.dart';

/// What a composition layer stays fixed to.
/// {@category Features}
enum XrLayerSpace {
  /// The session's reference space, so the layer holds its place in the
  /// world as the viewer moves.
  reference,

  /// The viewer's head, so the layer follows it. Meant for small things (a
  /// reticle); a large head-locked panel is uncomfortable.
  viewer,
}

/// Images the runtime's compositor places in the world itself, over the
/// rendered scene.
///
/// A layer has its own image at its own resolution, redrawn only when its
/// content changes, and the compositor reprojects it every display frame.
/// That keeps text sharp and steady where the same panel drawn into the eye
/// images would be resampled twice and would judder when the scene misses a
/// frame.
///
/// ```dart
/// final panel = session.layers?.createQuadLayer(
///   pixelWidth: 1024,
///   pixelHeight: 512,
///   width: 1.0,
///   height: 0.5,
///   pose: XrPose(position: Vector3(0, 1.4, -1.2)),
/// );
/// session.frames.listen((frame) {
///   if (panel == null || !(panel.needsRedraw || contentChanged)) return;
///   final target = panel.acquireTarget();
///   if (target == null) return;
///   panelScene.renderViewsToTargets([
///     RenderViewGroup([RenderView(camera: flat, externalTarget: target)]),
///   ]);
/// });
/// ```
/// {@category Features}
abstract class XrLayers {
  /// The layers the compositor draws over the scene, bottom first.
  List<XrCompositionLayer> get layers;

  /// Adds a flat panel [width] by [height] meters, centered on [pose], whose
  /// image is [pixelWidth] by [pixelHeight].
  ///
  /// The panel faces along its pose's +Z axis, the way a quad facing the
  /// viewer does at the identity orientation.
  XrQuadLayer createQuadLayer({
    required int pixelWidth,
    required int pixelHeight,
    required double width,
    required double height,
    XrPose? pose,
    XrLayerSpace space = XrLayerSpace.reference,
  });

  /// Adds a panel curved around the viewer, a section of a cylinder of
  /// [radius] meters whose axis passes through [pose] along its Y axis.
  ///
  /// [centralAngle] is the angle in radians the visible section spans,
  /// centered on the pose's -Z axis. Its width is the arc
  /// `radius * centralAngle` and its height that width over [aspectRatio].
  XrCylinderLayer createCylinderLayer({
    required int pixelWidth,
    required int pixelHeight,
    required double radius,
    required double centralAngle,
    required double aspectRatio,
    XrPose? pose,
    XrLayerSpace space = XrLayerSpace.reference,
  });
}

/// One image the compositor places for the app.
/// {@category Features}
abstract class XrCompositionLayer {
  /// What the layer is fixed to.
  XrLayerSpace get space;

  /// Where the layer sits in [space]. Write its fields to move the layer;
  /// the runtime reads it every frame.
  XrPose get pose;

  /// The image's width in pixels.
  int get pixelWidth;

  /// The image's height in pixels.
  int get pixelHeight;

  /// Whether the compositor draws the layer.
  bool get visible;
  set visible(bool value);

  /// Whether the image must be drawn again this frame, true for a new layer
  /// and whenever the runtime lost what it held.
  bool get needsRedraw;

  /// The image to redraw the layer into this frame, or null when the runtime
  /// has none to give (outside the frame callback, or after [dispose]).
  ///
  /// Render into it with `Scene.renderViewsToTargets` before the frame
  /// callback returns. A layer whose target is not acquired keeps the image
  /// it had, so acquire only when the content changed or [needsRedraw] is
  /// set.
  ExternalRenderTarget? acquireTarget();

  /// Removes the layer and frees its images.
  void dispose();
}

/// A flat panel.
/// {@category Features}
abstract class XrQuadLayer implements XrCompositionLayer {
  /// The panel's width in meters.
  double get width;
  set width(double value);

  /// The panel's height in meters.
  double get height;
  set height(double value);
}

/// A panel curved around its pose.
/// {@category Features}
abstract class XrCylinderLayer implements XrCompositionLayer {
  /// The cylinder's radius in meters.
  double get radius;
  set radius(double value);

  /// The angle in radians the visible section spans.
  double get centralAngle;
  set centralAngle(double value);

  /// The visible section's width over its height.
  double get aspectRatio;
  set aspectRatio(double value);
}
