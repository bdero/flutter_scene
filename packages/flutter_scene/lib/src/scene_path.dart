import 'package:vector_math/vector_math.dart';

/// An oriented coordinate frame at a point along a [ScenePath].
///
/// The three axes are unit length and mutually perpendicular: [tangent]
/// runs along the path, and [normal] and [binormal] span the plane
/// across it. Frames along a path are rotation-minimizing, so a profile
/// swept through them does not twist.
/// {@category Geometry}
class ScenePathFrame {
  /// Creates a frame from its position and axes.
  const ScenePathFrame({
    required this.position,
    required this.tangent,
    required this.normal,
    required this.binormal,
  });

  /// The point on the path.
  final Vector3 position;

  /// Unit direction along the path.
  final Vector3 tangent;

  /// Unit direction across the path, perpendicular to [tangent].
  final Vector3 normal;

  /// Unit direction completing the frame: `tangent` cross `normal`.
  final Vector3 binormal;
}

/// A curve through 3D space, independent of any geometry or rendering.
///
/// A `ScenePath` is an immutable value type. Subclasses ([PolylinePath],
/// [CatmullRomPath], [BezierPath]) define the curve; this base class adds
/// arc-length measurement and rotation-minimizing frames on top.
///
/// Two parameter spaces are available. The natural parameter `t` runs
/// `0..1` and is spaced evenly per segment ([positionAt], [tangentAt],
/// [frameAt]). Arc-length distance `d` runs `0..length` and is spaced
/// evenly along the curve ([positionAtDistance], [frameAtDistance]); use
/// it when spacing must stay uniform around bends, such as for dashes or
/// a swept profile.
/// {@category Geometry}
abstract class ScenePath {
  /// The point on the curve at natural parameter [t] (clamped to `0..1`).
  Vector3 positionAt(double t);

  /// The unit tangent at natural parameter [t] (clamped to `0..1`).
  Vector3 tangentAt(double t);

  /// The natural parameters at which the curve is sampled when baking
  /// the arc-length and frame tables. Strictly increasing, starting at
  /// `0` and ending at `1`.
  List<double> sampleParameters();

  _PathTable? _table;
  _PathTable get _baked => _table ??= _bake();

  /// The total arc length of the curve.
  double get length => _baked.cumulativeLengths.last;

  /// The point at arc-length distance [d] (clamped to `0..length`).
  Vector3 positionAtDistance(double d) => positionAt(parameterAtDistance(d));

  /// An oriented frame at natural parameter [t] (clamped to `0..1`).
  ScenePathFrame frameAt(double t) {
    final clamped = _clamp01(t);
    final table = _baked;
    final params = table.parameters;
    var hi = 1;
    while (hi < params.length - 1 && params[hi] < clamped) {
      hi++;
    }
    final lo = hi - 1;
    final span = params[hi] - params[lo];
    final local = span > 1e-12 ? (clamped - params[lo]) / span : 0.0;

    final position = positionAt(clamped);
    var tangent = tangentAt(clamped);
    if (tangent.length2 < 1e-12) {
      tangent = table.tangents[hi].clone();
    }
    tangent = tangent.normalized();

    var normal = table.normals[lo] * (1.0 - local) + table.normals[hi] * local;
    normal = normal - tangent * normal.dot(tangent);
    if (normal.length2 < 1e-12) {
      normal = _perpendicularTo(tangent);
    }
    normal = normal.normalized();

    return ScenePathFrame(
      position: position,
      tangent: tangent,
      normal: normal,
      binormal: tangent.cross(normal).normalized(),
    );
  }

  /// An oriented frame at arc-length distance [d] (clamped to
  /// `0..length`).
  ScenePathFrame frameAtDistance(double d) => frameAt(parameterAtDistance(d));

  /// The natural parameter at arc-length distance [d] (clamped to
  /// `0..length`).
  double parameterAtDistance(double d) {
    final table = _baked;
    final cumulative = table.cumulativeLengths;
    final total = cumulative.last;
    if (total <= 0.0) return 0.0;
    final target = d < 0.0 ? 0.0 : (d > total ? total : d);
    var lo = 0;
    var hi = cumulative.length - 1;
    while (lo + 1 < hi) {
      final mid = (lo + hi) >> 1;
      if (cumulative[mid] <= target) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    final segment = cumulative[hi] - cumulative[lo];
    final local = segment > 1e-12 ? (target - cumulative[lo]) / segment : 0.0;
    return table.parameters[lo] +
        (table.parameters[hi] - table.parameters[lo]) * local;
  }

  /// Returns [count] points along the curve.
  ///
  /// With [evenlySpaced] the points are spaced by equal arc length;
  /// otherwise they are spaced by equal natural parameter. [count] must
  /// be at least two.
  List<Vector3> sample(int count, {bool evenlySpaced = false}) {
    if (count < 2) {
      throw ArgumentError.value(count, 'count', 'must be at least two');
    }
    final total = length;
    return <Vector3>[
      for (var i = 0; i < count; i++)
        if (evenlySpaced)
          positionAtDistance(i / (count - 1) * total)
        else
          positionAt(i / (count - 1)),
    ];
  }

  _PathTable _bake() {
    final params = sampleParameters();
    final positions = <Vector3>[for (final t in params) positionAt(t)];
    final tangents = <Vector3>[for (final t in params) tangentAt(t)];

    final cumulative = List<double>.filled(params.length, 0.0);
    for (var i = 1; i < params.length; i++) {
      cumulative[i] =
          cumulative[i - 1] + positions[i].distanceTo(positions[i - 1]);
    }

    return _PathTable(
      parameters: params,
      tangents: tangents,
      normals: _rotationMinimizingNormals(positions, tangents),
      cumulativeLengths: cumulative,
    );
  }

  // Propagates a normal along the sampled curve with the double
  // reflection method, which minimizes frame rotation between samples.
  static List<Vector3> _rotationMinimizingNormals(
    List<Vector3> positions,
    List<Vector3> tangents,
  ) {
    final count = positions.length;
    final normals = List<Vector3>.filled(count, Vector3.zero());
    normals[0] = _perpendicularTo(tangents[0]);
    for (var i = 0; i < count - 1; i++) {
      var reference = normals[i];
      final v1 = positions[i + 1] - positions[i];
      final c1 = v1.dot(v1);
      if (c1 > 1e-12) {
        final reflectedRef = reference - v1 * (2.0 / c1 * v1.dot(reference));
        final reflectedTan =
            tangents[i] - v1 * (2.0 / c1 * v1.dot(tangents[i]));
        final v2 = tangents[i + 1] - reflectedTan;
        final c2 = v2.dot(v2);
        reference = c2 > 1e-12
            ? reflectedRef - v2 * (2.0 / c2 * v2.dot(reflectedRef))
            : reflectedRef;
      }
      // Re-orthonormalize against the next tangent.
      reference = reference - tangents[i + 1] * reference.dot(tangents[i + 1]);
      if (reference.length2 < 1e-12) {
        reference = _perpendicularTo(tangents[i + 1]);
      }
      normals[i + 1] = reference.normalized();
    }
    return normals;
  }

  // An arbitrary unit vector perpendicular to [direction].
  static Vector3 _perpendicularTo(Vector3 direction) {
    final ax = direction.x.abs();
    final ay = direction.y.abs();
    final az = direction.z.abs();
    final Vector3 axis;
    if (ax <= ay && ax <= az) {
      axis = Vector3(1.0, 0.0, 0.0);
    } else if (ay <= az) {
      axis = Vector3(0.0, 1.0, 0.0);
    } else {
      axis = Vector3(0.0, 0.0, 1.0);
    }
    final result = axis.cross(direction);
    if (result.length2 < 1e-12) return Vector3(0.0, 1.0, 0.0);
    return result.normalized();
  }
}

double _clamp01(double v) => v < 0.0 ? 0.0 : (v > 1.0 ? 1.0 : v);

// Maps natural parameter [t] to a segment index and a local `0..1`
// offset within it, given a curve of [segments] equal-parameter spans.
(int, double) _segmentOf(double t, int segments) {
  final scaled = _clamp01(t) * segments;
  var segment = scaled.floor();
  if (segment >= segments) segment = segments - 1;
  return (segment, scaled - segment);
}

class _PathTable {
  _PathTable({
    required this.parameters,
    required this.tangents,
    required this.normals,
    required this.cumulativeLengths,
  });

  final List<double> parameters;
  final List<Vector3> tangents;
  final List<Vector3> normals;
  final List<double> cumulativeLengths;
}

/// A path of straight segments connecting a list of points.
/// {@category Geometry}
class PolylinePath extends ScenePath {
  /// Creates a polyline through [points], which is copied. At least two
  /// points are required.
  PolylinePath(List<Vector3> points)
    : _points = <Vector3>[for (final p in points) p.clone()] {
    if (_points.length < 2) {
      throw ArgumentError('A path needs at least two points');
    }
  }

  final List<Vector3> _points;

  @override
  Vector3 positionAt(double t) {
    final (segment, local) = _segmentOf(t, _points.length - 1);
    return _points[segment] * (1.0 - local) + _points[segment + 1] * local;
  }

  @override
  Vector3 tangentAt(double t) {
    final (segment, _) = _segmentOf(t, _points.length - 1);
    final direction = _points[segment + 1] - _points[segment];
    if (direction.length2 < 1e-12) return Vector3(1.0, 0.0, 0.0);
    return direction.normalized();
  }

  @override
  List<double> sampleParameters() {
    final segments = _points.length - 1;
    return <double>[for (var i = 0; i <= segments; i++) i / segments];
  }
}

// Natural-parameter samples per segment for the smooth curve types,
// used to bake their arc-length and frame tables.
const int _smoothCurveSamplesPerSegment = 24;

List<double> _subdividedParameters(int segments) {
  final params = <double>[];
  for (var s = 0; s < segments; s++) {
    for (var k = 0; k < _smoothCurveSamplesPerSegment; k++) {
      params.add((s + k / _smoothCurveSamplesPerSegment) / segments);
    }
  }
  params.add(1.0);
  return params;
}

/// A smooth curve passing through every one of a list of points.
///
/// The curve interpolates its control points with uniform Catmull-Rom
/// segments, so `positionAt` returns a control point exactly at that
/// point's natural parameter.
/// {@category Geometry}
class CatmullRomPath extends ScenePath {
  /// Creates a Catmull-Rom curve through [points], which is copied. At
  /// least two points are required.
  CatmullRomPath(List<Vector3> points)
    : _points = <Vector3>[for (final p in points) p.clone()] {
    if (_points.length < 2) {
      throw ArgumentError('A path needs at least two points');
    }
  }

  final List<Vector3> _points;

  @override
  Vector3 positionAt(double t) {
    final (segment, s) = _segmentOf(t, _points.length - 1);
    final (p0, p1, p2, p3) = _controlPoints(segment);
    final s2 = s * s;
    final s3 = s2 * s;
    return (p1 * 2.0 +
            (p2 - p0) * s +
            (p0 * 2.0 - p1 * 5.0 + p2 * 4.0 - p3) * s2 +
            (p1 * 3.0 - p0 - p2 * 3.0 + p3) * s3) *
        0.5;
  }

  @override
  Vector3 tangentAt(double t) {
    final (segment, s) = _segmentOf(t, _points.length - 1);
    final (p0, p1, p2, p3) = _controlPoints(segment);
    final derivative =
        ((p2 - p0) +
            (p0 * 2.0 - p1 * 5.0 + p2 * 4.0 - p3) * (2.0 * s) +
            (p1 * 3.0 - p0 - p2 * 3.0 + p3) * (3.0 * s * s)) *
        0.5;
    if (derivative.length2 < 1e-12) return Vector3(1.0, 0.0, 0.0);
    return derivative.normalized();
  }

  @override
  List<double> sampleParameters() => _subdividedParameters(_points.length - 1);

  // The four control points for [segment], with the endpoints repeated
  // so the first and last segments still interpolate cleanly.
  (Vector3, Vector3, Vector3, Vector3) _controlPoints(int segment) {
    final last = _points.length - 1;
    Vector3 at(int i) => _points[i < 0 ? 0 : (i > last ? last : i)];
    return (at(segment - 1), at(segment), at(segment + 1), at(segment + 2));
  }
}

/// A path of joined cubic Bezier segments.
///
/// Each segment is defined by four control points, and adjacent
/// segments share an endpoint, so the control point count must be
/// `3 * segments + 1`.
/// {@category Geometry}
class BezierPath extends ScenePath {
  /// Creates a Bezier path from [controlPoints], which is copied. The
  /// count must be `3 * segments + 1` for one or more segments.
  BezierPath(List<Vector3> controlPoints)
    : _points = <Vector3>[for (final p in controlPoints) p.clone()] {
    if (_points.length < 4 || (_points.length - 1) % 3 != 0) {
      throw ArgumentError(
        'A Bezier path needs 3 * segments + 1 control points',
      );
    }
  }

  final List<Vector3> _points;

  int get _segments => (_points.length - 1) ~/ 3;

  @override
  Vector3 positionAt(double t) {
    final (segment, s) = _segmentOf(t, _segments);
    final base = segment * 3;
    final p0 = _points[base];
    final p1 = _points[base + 1];
    final p2 = _points[base + 2];
    final p3 = _points[base + 3];
    final u = 1.0 - s;
    return p0 * (u * u * u) +
        p1 * (3.0 * u * u * s) +
        p2 * (3.0 * u * s * s) +
        p3 * (s * s * s);
  }

  @override
  Vector3 tangentAt(double t) {
    final (segment, s) = _segmentOf(t, _segments);
    final base = segment * 3;
    final p0 = _points[base];
    final p1 = _points[base + 1];
    final p2 = _points[base + 2];
    final p3 = _points[base + 3];
    final u = 1.0 - s;
    final derivative =
        (p1 - p0) * (3.0 * u * u) +
        (p2 - p1) * (6.0 * u * s) +
        (p3 - p2) * (3.0 * s * s);
    if (derivative.length2 < 1e-12) return Vector3(1.0, 0.0, 0.0);
    return derivative.normalized();
  }

  @override
  List<double> sampleParameters() => _subdividedParameters(_segments);
}
