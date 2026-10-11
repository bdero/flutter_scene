import 'dart:ui' show Rect;

import 'package:flutter_scene/scene.dart'
    show ExternalRenderTarget, OffAxisProjection;
import 'package:vector_math/vector_math.dart';

import 'package:flutter_scene_xr/src/xr_pose.dart';

/// Which eye a view feeds.
/// {@category Sessions}
enum XrEye {
  /// A single view, a phone's camera or a monoscopic headset.
  none,

  /// The left eye.
  left,

  /// The right eye.
  right,
}

/// One view of a frame, an eye's pose and lens and where its image goes.
///
/// The fields are refilled by the runtime each frame; hold the view, not its
/// values. [projection] is an [OffAxisProjection] whose tangents are rewritten
/// in place, so a camera holding it follows the runtime's lens.
/// {@category Sessions}
class XrView {
  /// A view for [eye]. [viewport] is the normalized, top-left region of
  /// [target] (or the frame's target when null) it renders into.
  XrView({
    required this.eye,
    XrPose? pose,
    OffAxisProjection? projection,
    this.viewport = const Rect.fromLTWH(0, 0, 1, 1),
    this.target,
  }) : pose = pose ?? XrPose(),
       projection = projection ?? OffAxisProjection.symmetric();

  /// Which eye this view is.
  XrEye eye;

  /// The eye's pose in the frame's reference space.
  final XrPose pose;

  /// The eye's lens.
  final OffAxisProjection projection;

  /// The region of the target this view fills, normalized with a top-left
  /// origin.
  Rect viewport;

  /// A target of this view's own, or null to render into the frame's.
  ExternalRenderTarget? target;

  /// Copies the lens a runtime states as a projection [matrix] into
  /// [projection], keeping the instance a camera already holds.
  ///
  /// Accepts the OpenGL convention WebXR produces and the engine's own; see
  /// [OffAxisProjection.fromMatrix]. [near] and [far] override the decoded
  /// planes.
  void setProjectionFromMatrix(Matrix4 matrix, {double? near, double? far}) {
    final decoded = OffAxisProjection.fromMatrix(matrix, near: near, far: far);
    projection
      ..tanLeft = decoded.tanLeft
      ..tanRight = decoded.tanRight
      ..tanDown = decoded.tanDown
      ..tanUp = decoded.tanUp
      ..near = decoded.near
      ..far = decoded.far;
  }
}
