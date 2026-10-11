import 'dart:typed_data';

import 'package:vector_math/vector_math.dart' show Matrix4;

import 'package:flutter_scene_xr/src/xr_view.dart';

/// Real-world depth the runtime measures per view.
/// {@category Features}
abstract class XrDepthSensing {
  /// The depth image for [view] this frame, or null when the runtime has
  /// none. Valid inside the frame callback; the data is copied out.
  XrDepthInformation? depthForView(XrView view);
}

/// A CPU depth image for one view.
///
/// Depth is read with normalized view coordinates (origin top-left) mapped
/// through [normDepthBufferFromNormView], since the buffer may be rotated or
/// scaled relative to the view.
// TODO(xr-depth-occlusion): upload this (or the runtime's GPU depth texture)
// into a texture and apply it as a post pass that zeroes scene alpha where
// real depth is nearer, with a soft edge; nothing consumes it yet.
/// {@category Features}
class XrDepthInformation {
  /// A [width] by [height] image of depths in meters.
  XrDepthInformation({
    required this.width,
    required this.height,
    required this.depthMeters,
    required this.rawValueToMeters,
    required this.normDepthBufferFromNormView,
  });

  /// Columns in [depthMeters].
  final int width;

  /// Rows in [depthMeters].
  final int height;

  /// Row-major depths in meters, [width] times [height] long.
  final Float32List depthMeters;

  /// The scale the runtime's raw samples were multiplied by, kept for
  /// callers that want the raw values back.
  final double rawValueToMeters;

  /// Maps normalized view coordinates to normalized buffer coordinates.
  final Matrix4 normDepthBufferFromNormView;

  /// The depth in meters at normalized view coordinates ([x], [y] in `0..1`,
  /// origin top-left), or null outside the buffer.
  double? depthAt(double x, double y) {
    final m = normDepthBufferFromNormView.storage;
    final bx = m[0] * x + m[4] * y + m[12];
    final by = m[1] * x + m[5] * y + m[13];
    final column = (bx * width).floor();
    final row = (by * height).floor();
    if (column < 0 || column >= width || row < 0 || row >= height) {
      return null;
    }
    return depthMeters[row * width + column];
  }
}
