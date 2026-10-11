import 'package:vector_math/vector_math.dart' show Ray;

import 'package:flutter_scene_xr/src/features/anchors.dart';
import 'package:flutter_scene_xr/src/xr_input_state.dart';
import 'package:flutter_scene_xr/src/xr_pose.dart';

/// Where a hit test ray starts.
/// {@category Features}
sealed class XrHitTestOrigin {
  const XrHitTestOrigin();

  /// A ray from the viewer, straight ahead unless offset.
  const factory XrHitTestOrigin.viewer() = XrHitTestViewerOrigin;

  /// A ray along an input source's target ray.
  const factory XrHitTestOrigin.inputSource(XrInputSourceState source) =
      XrHitTestInputSourceOrigin;
}

/// A hit test from the viewer's pose.
/// {@category Features}
final class XrHitTestViewerOrigin extends XrHitTestOrigin {
  const XrHitTestViewerOrigin();
}

/// A hit test from an input source's target ray.
/// {@category Features}
final class XrHitTestInputSourceOrigin extends XrHitTestOrigin {
  const XrHitTestInputSourceOrigin(this.source);

  /// The source whose target ray space the ray follows.
  final XrInputSourceState source;
}

/// Casts rays against the real world the runtime has mapped.
/// {@category Features}
abstract class XrHitTesting {
  /// Starts testing along a ray from [origin], offset by [offsetRay] in that
  /// space (default straight ahead). Returns null when the runtime refuses.
  Future<XrHitTestSource?> requestSource(
    XrHitTestOrigin origin, {
    Ray? offsetRay,
  });
}

/// A standing hit test whose results refresh every frame.
/// {@category Features}
abstract class XrHitTestSource {
  /// This frame's hits, nearest first. Valid inside the frame callback.
  List<XrHitTestResult> get results;

  /// Stops testing.
  void cancel();
}

/// One surface a hit test ray struck.
/// {@category Features}
abstract class XrHitTestResult {
  /// Where the ray hit, in the session's reference space, with `+Y` along
  /// the surface normal.
  XrPose get pose;

  /// Pins an anchor to the hit surface, or null when the runtime refuses or
  /// anchors are not granted.
  Future<XrAnchor?> createAnchor();
}
