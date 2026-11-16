import 'dart:async';
import 'dart:ui' show Color;

import 'package:flutter_scene/scene.dart';

import 'package:flutter_scene_xr/src/xr_frame.dart';
import 'package:flutter_scene_xr/src/xr_input_source.dart';
import 'package:flutter_scene_xr/src/xr_rig.dart';
import 'package:flutter_scene_xr/src/xr_session.dart';

/// Renders a [Scene] through an [XrRig] for every frame of an [XrSession].
///
/// Each frame, in order: the rig takes the frame's poses, [input] publishes
/// the frame's controllers, [onTick] runs, the scene updates by the time
/// between predicted display times, [onBeforeRender] runs, the rig's views
/// render into the frame's targets as one `RenderViewGroup`, and the frame
/// hears the result through `XrFrame.submit`.
///
/// Nothing here paints a widget, so a scene with `WidgetComponent`s needs a
/// `WidgetHost` (or a `SceneView` of the same scene) in the app's widget
/// tree to keep their subtrees live.
/// {@category Rig}
class XrSceneLoop {
  /// A loop drawing [scene] through [rig] for [session]'s frames.
  XrSceneLoop({
    required this.scene,
    required this.rig,
    required this.session,
    this.input,
    this.pixelRatio = 1.0,
    this.maxDeltaSeconds = 0.1,
    this.backgroundColor,
    this.onTick,
    this.onBeforeRender,
  });

  /// The scene rendered.
  final Scene scene;

  /// The rig the frames drive. Its `origin` should be in [scene].
  final XrRig rig;

  /// The frame source.
  final XrSession session;

  /// Publishes the frames' controllers and hands into the input system, and
  /// drives their pointers.
  final XrInputSource? input;

  /// Logical pixels per target pixel, passed to `renderViewsToTargets`.
  final double pixelRatio;

  /// The longest step `Scene.update` is given, so a pause does not become
  /// one giant tick.
  final double maxDeltaSeconds;

  /// A color put behind the scene in every eye, or null to leave each
  /// target's own (see `ExternalRenderTarget.backgroundColor`).
  ///
  /// An opaque session shows the scene's clear pixels as whatever the
  /// runtime does with zero alpha, so a scene without a skybox usually wants
  /// an opaque color here. Leave it null for passthrough, where clear pixels
  /// are the world.
  Color? backgroundColor;

  /// Runs after the rig and input took the frame, before the scene updates.
  void Function(XrFrame frame, double deltaSeconds)? onTick;

  /// Runs after the scene updated, right before the views render.
  void Function(XrFrame frame, List<RenderView> views)? onBeforeRender;

  StreamSubscription<XrFrame>? _subscription;
  List<RenderViewGroup>? _groups;
  Duration? _lastDisplayTime;
  FrameCompletion? _lastCompletion;
  int _framesRendered = 0;

  /// What the last rendered frame reported, or null before the first.
  FrameCompletion? get lastCompletion => _lastCompletion;

  /// How many frames have been handed to the renderer.
  int get framesRendered => _framesRendered;

  /// Whether the loop is listening to the session.
  bool get isRunning => _subscription != null;

  /// Starts rendering the session's frames.
  void start() {
    if (_subscription != null) return;
    _subscription = session.frames.listen(handleFrame);
  }

  /// Stops rendering. The session keeps running until it is ended.
  void stop() {
    _subscription?.cancel();
    _subscription = null;
    _lastDisplayTime = null;
  }

  /// Runs one frame. [start] routes the session's frames here; call it
  /// directly to drive the loop from another source.
  void handleFrame(XrFrame frame) {
    final views = rig.applyFrame(frame);
    input?.applyFrame(frame);
    final last = _lastDisplayTime;
    _lastDisplayTime = frame.predictedDisplayTime;
    var deltaSeconds = last == null
        ? 0.0
        : (frame.predictedDisplayTime - last).inMicroseconds / 1e6;
    if (deltaSeconds < 0.0) deltaSeconds = 0.0;
    if (deltaSeconds > maxDeltaSeconds) deltaSeconds = maxDeltaSeconds;
    onTick?.call(frame, deltaSeconds);
    scene.update(deltaSeconds);
    onBeforeRender?.call(frame, views);
    if (!frame.hasTargets) {
      frame.submit(_lastCompletion = FrameCompletion.skipped());
      return;
    }
    final background = backgroundColor;
    if (background != null) {
      for (final view in views) {
        view.externalTarget?.backgroundColor = background;
      }
    }
    final completion = scene.renderViewsToTargets(
      _groups ??= [RenderViewGroup(rig.views)],
      pixelRatio: pixelRatio,
    );
    _lastCompletion = completion;
    _framesRendered++;
    frame.submit(completion);
  }
}
