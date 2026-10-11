import 'package:flutter_scene/scene.dart' show ExternalRenderTarget;

import 'package:flutter_scene_xr/src/xr_input_state.dart';
import 'package:flutter_scene_xr/src/xr_pose.dart';
import 'package:flutter_scene_xr/src/xr_session.dart';
import 'package:flutter_scene_xr/src/xr_view.dart';

/// Everything a runtime hands over for one display frame.
///
/// A frame is the views to render, the viewer's pose, the target they render
/// into, and the tracked input sources, all predicted for
/// [predictedDisplayTime]. A runtime refills one frame object per frame, so
/// read it inside the frame callback and copy what must outlive it.
/// {@category Sessions}
class XrFrame {
  /// A frame of [views] relative to [referenceSpaceType].
  XrFrame({
    required this.predictedDisplayTime,
    required this.views,
    required this.referenceSpaceType,
    this.viewerPose,
    this.target,
    this.inputSources = const [],
  });

  /// When the runtime expects to show this frame, on the runtime's clock.
  Duration predictedDisplayTime;

  /// [predictedDisplayTime] in seconds.
  double get predictedDisplaySeconds =>
      predictedDisplayTime.inMicroseconds / 1e6;

  /// The views to render, empty while the runtime has no viewer pose
  /// (tracking lost, or the session not yet visible).
  final List<XrView> views;

  /// The space every pose in this frame is relative to.
  XrReferenceSpaceType referenceSpaceType;

  /// Where the viewer is, between the eyes, or null when tracking is lost.
  XrPose? viewerPose;

  /// The color target the views render into, unless a view carries its own
  /// ([XrView.target]). Null when the runtime offered nothing to draw into.
  ExternalRenderTarget? target;

  /// The tracked controllers, hands and other inputs this frame.
  List<XrInputSourceState> inputSources;

  /// Whether there is anything to render this frame.
  bool get hasViews => views.isNotEmpty;

  /// Whether every view has a target to render into.
  bool get hasTargets =>
      views.isNotEmpty &&
      views.every((view) => (view.target ?? target) != null);
}
