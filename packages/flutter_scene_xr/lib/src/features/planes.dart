import 'package:vector_math/vector_math.dart' show Vector3;

import 'package:flutter_scene_xr/src/xr_pose.dart';

/// How a detected plane lies.
/// {@category Features}
enum XrPlaneOrientation {
  /// A floor, table or ceiling.
  horizontal,

  /// A wall.
  vertical,

  /// The runtime did not say.
  unknown,
}

/// Flat real-world surfaces the runtime has found.
/// {@category Features}
abstract class XrPlaneDetection {
  /// Every plane detected as of the latest frame.
  List<XrPlane> get planes;
}

/// One detected plane.
/// {@category Features}
abstract class XrPlane {
  /// Which way the plane lies.
  XrPlaneOrientation get orientation;

  /// The plane's outline in its own space (`y` is zero), relative to [pose].
  List<Vector3> get polygon;

  /// The plane's pose in the session's reference space, or null when it is
  /// not tracked this frame.
  XrPose? get pose;

  /// When the runtime last changed the outline, in the runtime's seconds.
  double get lastChangedTime;
}
