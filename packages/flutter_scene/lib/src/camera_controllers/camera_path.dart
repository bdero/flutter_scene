import 'dart:math' as math;

import 'package:vector_math/vector_math.dart';

/// A smooth curve through a list of waypoints, for a camera to travel along.
///
/// The curve is a Catmull-Rom spline, which passes *through* every waypoint
/// rather than being pulled toward it. That is the property that matters for
/// authoring a camera move: the points you place are the points the camera
/// visits, and the curve only decides how it gets between them.
///
/// The path is parameterized by **arc length**, not by segment index. Asking
/// for the point 10 units along gives a point 10 units along, whatever the
/// spacing of the waypoints, so a camera moving at a constant speed does not
/// accelerate through the closely-spaced parts of the curve. This costs a
/// one-time sampling pass at construction ([samplesPerSegment] controls its
/// resolution) and nothing per frame.
///
/// ```dart
/// final path = CameraPath([
///   Vector3(-20, 6, -20),
///   Vector3(0, 4, -8),
///   Vector3(18, 9, 4),
/// ]);
/// ```
/// {@category Scene graph}
class CameraPath {
  /// Creates a path through [waypoints] (at least two).
  ///
  /// A [closed] path loops back to its first waypoint, and its curvature is
  /// continuous across the seam. [samplesPerSegment] sets how finely the
  /// arc-length table is built: raise it for very long or tightly curving
  /// segments, where the default may leave the constant-speed guarantee
  /// slightly loose.
  CameraPath(
    List<Vector3> waypoints, {
    this.closed = false,
    int samplesPerSegment = 24,
  }) : assert(
         waypoints.length >= 2,
         'A CameraPath needs at least two waypoints.',
       ),
       assert(samplesPerSegment >= 1),
       _points = List<Vector3>.unmodifiable(
         waypoints.map((point) => point.clone()),
       ) {
    _buildTable(samplesPerSegment);
  }

  /// A straight path from [from] to [to].
  factory CameraPath.line(Vector3 from, Vector3 to) =>
      CameraPath([from, to], samplesPerSegment: 1);

  /// A circular path of [radius] around [center] on the horizontal plane, at
  /// [height] above it: the standard establishing orbit.
  ///
  /// [segments] waypoints are placed around the circle. The spline through
  /// them bows very slightly inward between waypoints, by roughly `1 /
  /// segments^2`; the default of twelve holds the radius to about a quarter
  /// of a percent, which no camera move will show.
  factory CameraPath.orbit(
    Vector3 center, {
    double radius = 10.0,
    double height = 4.0,
    int segments = 12,
    double startAngle = 0.0,
  }) {
    assert(segments >= 3, 'An orbit needs at least three waypoints.');
    return CameraPath([
      for (var i = 0; i < segments; i++)
        Vector3(
          center.x + math.sin(startAngle + i / segments * math.pi * 2) * radius,
          center.y + height,
          center.z + math.cos(startAngle + i / segments * math.pi * 2) * radius,
        ),
    ], closed: true);
  }

  final List<Vector3> _points;

  /// Whether the path loops back on itself.
  final bool closed;

  /// The waypoints the curve passes through.
  List<Vector3> get waypoints => _points;

  // Cumulative arc length at each sample, and the spline parameter each
  // sample sits at. Parallel lists, both strictly increasing in the first.
  late final List<double> _lengths;
  late final List<double> _parameters;

  /// The total length of the curve, in world units.
  double get length => _lengths.last;

  int get _segmentCount => closed ? _points.length : _points.length - 1;

  void _buildTable(int samplesPerSegment) {
    final sampleCount = _segmentCount * samplesPerSegment;
    final lengths = <double>[0.0];
    final parameters = <double>[0.0];
    var previous = _evaluate(0.0);
    var total = 0.0;
    for (var i = 1; i <= sampleCount; i++) {
      final u = i / sampleCount * _segmentCount;
      final point = _evaluate(u);
      total += (point - previous).length;
      lengths.add(total);
      parameters.add(u);
      previous = point;
    }
    _lengths = lengths;
    _parameters = parameters;
  }

  /// The control point at [index], inventing the two the ends need.
  ///
  /// An open path reflects its endpoints (`2 * first - second`) rather than
  /// duplicating them. Duplicating gives the curve a zero tangent at each
  /// end, so a camera would ease in and out of every path whether or not the
  /// shot wanted it; reflecting continues the curve straight through, which
  /// is what "constant speed along the path" has to mean at the ends.
  Vector3 _controlPoint(int index) {
    if (closed) {
      return _points[index % _points.length];
    }
    if (index < 0) {
      return _points[0] * 2.0 - _points[1];
    }
    final last = _points.length - 1;
    if (index > last) {
      return _points[last] * 2.0 - _points[last - 1];
    }
    return _points[index];
  }

  /// Evaluates the spline at [u], where whole numbers land on waypoints and
  /// the valid range is `0`.._segmentCount.
  Vector3 _evaluate(double u) {
    final clamped = closed
        ? u % _segmentCount
        : u.clamp(0.0, _segmentCount.toDouble());
    var index = clamped.floor();
    if (index >= _segmentCount) index = _segmentCount - 1;
    final t = clamped - index;

    final p0 = _controlPoint(index - 1 + (closed ? _points.length : 0));
    final p1 = _controlPoint(index + (closed ? _points.length : 0));
    final p2 = _controlPoint(index + 1 + (closed ? _points.length : 0));
    final p3 = _controlPoint(index + 2 + (closed ? _points.length : 0));

    // Uniform Catmull-Rom.
    final t2 = t * t;
    final t3 = t2 * t;
    return (p1 * 2.0 +
            (p2 - p0) * t +
            (p0 * 2.0 - p1 * 5.0 + p2 * 4.0 - p3) * t2 +
            (p1 * 3.0 - p0 - p2 * 3.0 + p3) * t3) *
        0.5;
  }

  /// Converts a distance along the curve into a spline parameter.
  double _parameterAt(double distance) {
    final total = length;
    if (total <= 0.0) return 0.0;
    final target = closed ? distance % total : distance.clamp(0.0, total);

    // Binary search for the sample bracketing the distance, then interpolate
    // the parameter across it: the samples are dense enough that the curve is
    // effectively straight between them.
    var low = 0;
    var high = _lengths.length - 1;
    while (low < high - 1) {
      final mid = (low + high) >> 1;
      if (_lengths[mid] <= target) {
        low = mid;
      } else {
        high = mid;
      }
    }
    final span = _lengths[high] - _lengths[low];
    final fraction = span <= 1e-12 ? 0.0 : (target - _lengths[low]) / span;
    return _parameters[low] + (_parameters[high] - _parameters[low]) * fraction;
  }

  /// The point [distance] world units along the curve.
  ///
  /// Distances past the end clamp to the end, or wrap when [closed].
  Vector3 pointAt(double distance) => _evaluate(_parameterAt(distance));

  /// The point at [fraction] of the way along, `0` to `1`.
  Vector3 pointAtFraction(double fraction) => pointAt(fraction * length);

  /// The unit direction of travel [distance] units along the curve.
  Vector3 tangentAt(double distance) {
    final step = math.max(length * 1e-4, 1e-5);
    final ahead = pointAt(distance + step);
    final behind = pointAt(distance - step);
    final delta = ahead - behind;
    if (delta.length2 < 1e-18) return Vector3(0.0, 0.0, 1.0);
    return delta.normalized();
  }

  /// The distance along the curve of the point nearest [worldPoint].
  ///
  /// Resolved against the arc-length samples, so its precision is the sample
  /// spacing rather than exact. Useful for snapping a hand-placed camera onto
  /// a track, not for collision.
  double nearestDistanceTo(Vector3 worldPoint) {
    var best = 0.0;
    var bestDistance2 = double.infinity;
    for (var i = 0; i < _parameters.length; i++) {
      final delta = _evaluate(_parameters[i]) - worldPoint;
      final distance2 = delta.length2;
      if (distance2 < bestDistance2) {
        bestDistance2 = distance2;
        best = _lengths[i];
      }
    }
    return best;
  }
}
