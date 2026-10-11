import 'package:flutter_scene_xr/src/xr_pose.dart';

/// Poses the runtime keeps fixed to the real world across tracking
/// corrections.
/// {@category Features}
abstract class XrAnchors {
  /// Pins an anchor at [pose] in the session's reference space, or null when
  /// the runtime refuses.
  Future<XrAnchor?> createAnchor(XrPose pose);

  /// Every anchor the runtime still tracks, updated each frame.
  List<XrAnchor> get tracked;
}

/// A tracked real-world pose.
/// {@category Features}
abstract class XrAnchor {
  /// The anchor's pose as of the latest frame.
  XrPose get pose;

  /// Whether the runtime located the anchor this frame.
  bool get isTracked;

  /// Stops tracking the anchor.
  void delete();
}
