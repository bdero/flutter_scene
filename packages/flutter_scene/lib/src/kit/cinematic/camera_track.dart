import 'dart:math' as math;

import 'package:flutter_scene/src/kit/cinematic/timeline.dart';
import 'package:vector_math/vector_math.dart' as vm;

/// One key on a [CameraTrack]: where the camera is and what it sees at
/// [time].
///
/// {@category Animation}
class CameraKey {
  /// Creates a camera key.
  const CameraKey({
    required this.time,
    required this.eye,
    required this.target,
    this.fovRadiansY,
    this.roll = 0,
    this.focusDistance,
    this.fStop,
    this.ease = KeyframeEase.smooth,
  });

  /// Time of the key in seconds.
  final double time;

  /// Camera position.
  final vm.Vector3 eye;

  /// The point the camera looks at.
  final vm.Vector3 target;

  /// Vertical field of view in radians. Null carries the neighboring keys'
  /// value (or the track default).
  final double? fovRadiansY;

  /// Rotation of the camera about its view direction in radians,
  /// right-handed, so positive rolls the camera clockwise as seen from
  /// behind it (the horizon tilts counterclockwise on screen).
  final double roll;

  /// Distance to the focus plane. Null focuses on [target].
  final double? focusDistance;

  /// Aperture f-number for depth of field. Null carries the track default.
  final double? fStop;

  /// How the camera passes through this key; [KeyframeEase.stop] settles
  /// here before moving on.
  final KeyframeEase ease;
}

/// A camera pose sampled from a [CameraTrack].
///
/// {@category Animation}
class CameraSample {
  /// Creates a sample.
  CameraSample({
    required this.eye,
    required this.target,
    required this.up,
    required this.fovRadiansY,
    required this.focusDistance,
    required this.fStop,
  });

  /// Camera position.
  final vm.Vector3 eye;

  /// The point the camera looks at.
  final vm.Vector3 target;

  /// World up for the view, rolled.
  final vm.Vector3 up;

  /// Vertical field of view in radians.
  final double fovRadiansY;

  /// Distance to the focus plane.
  final double focusDistance;

  /// Aperture f-number.
  final double fStop;
}

/// A camera move through [CameraKey]s, sampled as a pure function of time.
///
/// The eye and the target each follow a centripetal Catmull-Rom spline
/// through their keys (no cusps or self-intersecting loops, even with uneven
/// key spacing), re-parameterized by arc length. Travel along each path is
/// a [KeyframeCurve] of distance against key time, so the move keeps the
/// keyed timing with continuous speed, never overshoots or backs up, and
/// comes to rest at [KeyframeEase.stop] keys and at both ends.
///
/// Field of view, roll, focus, and aperture ease the same way.
///
/// {@category Animation}
class CameraTrack {
  /// Creates a track through [keys], which must be sorted by time.
  /// [defaultFovRadiansY] and [defaultFStop] fill keys that leave them null.
  CameraTrack(
    List<CameraKey> keys, {
    double defaultFovRadiansY = 45 * math.pi / 180,
    double defaultFStop = 2.8,
  }) : assert(keys.isNotEmpty),
       keys = List.unmodifiable(keys) {
    _eye = _ArcSpline([for (final k in keys) k.eye]);
    _target = _ArcSpline([for (final k in keys) k.target]);
    _eyeTravel = KeyframeCurve([
      for (var i = 0; i < keys.length; i++)
        Keyframe(keys[i].time, _eye.keyDistance(i), ease: keys[i].ease),
    ]);
    _targetTravel = KeyframeCurve([
      for (var i = 0; i < keys.length; i++)
        Keyframe(keys[i].time, _target.keyDistance(i), ease: keys[i].ease),
    ]);
    double carry(double? Function(CameraKey k) get, int i, double fallback) {
      for (var j = i; j >= 0; j--) {
        final v = get(keys[j]);
        if (v != null) return v;
      }
      for (var j = i + 1; j < keys.length; j++) {
        final v = get(keys[j]);
        if (v != null) return v;
      }
      return fallback;
    }

    KeyframeCurve curve(double Function(int i) value) => KeyframeCurve([
      for (var i = 0; i < keys.length; i++)
        Keyframe(keys[i].time, value(i), ease: keys[i].ease),
    ]);
    _fov = curve((i) => carry((k) => k.fovRadiansY, i, defaultFovRadiansY));
    _fStop = curve((i) => carry((k) => k.fStop, i, defaultFStop));
    _roll = curve((i) => keys[i].roll);
    _focus = curve(
      (i) => keys[i].focusDistance ?? (keys[i].target - keys[i].eye).length,
    );
  }

  /// The keys, sorted by time.
  final List<CameraKey> keys;

  late final _ArcSpline _eye;
  late final _ArcSpline _target;
  late final KeyframeCurve _eyeTravel;
  late final KeyframeCurve _targetTravel;
  late final KeyframeCurve _fov;
  late final KeyframeCurve _fStop;
  late final KeyframeCurve _roll;
  late final KeyframeCurve _focus;

  /// Time of the first key.
  double get startTime => keys.first.time;

  /// Time of the last key.
  double get endTime => keys.last.time;

  /// The camera at [time] seconds; clamps outside the keys.
  CameraSample sampleAt(double time) {
    final eye = _eye.pointAt(_eyeTravel.valueAt(time));
    final target = _target.pointAt(_targetTravel.valueAt(time));
    final forward = target - eye;
    final up = vm.Vector3(0, 1, 0);
    final roll = _roll.valueAt(time);
    if (roll != 0 && forward.length2 > 1e-12) {
      // Rodrigues' rotation of up about the view axis.
      final k = forward.normalized();
      final c = math.cos(roll), sn = math.sin(roll);
      up.setFrom(up * c + k.cross(up) * sn + k * (k.dot(up) * (1 - c)));
    }
    return CameraSample(
      eye: eye,
      target: target,
      up: up,
      fovRadiansY: _fov.valueAt(time),
      focusDistance: _focus.valueAt(time),
      fStop: _fStop.valueAt(time),
    );
  }
}

/// A centripetal Catmull-Rom spline through points, addressed by arc length.
class _ArcSpline {
  _ArcSpline(List<vm.Vector3> points)
    : _points = [for (final p in points) p.clone()] {
    final n = _points.length;
    _cumulative.add(0);
    if (n < 2) return;
    var total = 0.0;
    final prev = vm.Vector3.zero();
    for (var seg = 0; seg < n - 1; seg++) {
      _segmentStart.add(_table.length);
      prev.setFrom(_segmentPoint(seg, 0));
      for (var s = 1; s <= _samplesPerSegment; s++) {
        final u = s / _samplesPerSegment;
        final p = _segmentPoint(seg, u);
        total += p.distanceTo(prev);
        _table.add((seg, u, total));
        prev.setFrom(p);
      }
      _cumulative.add(total);
    }
  }

  static const int _samplesPerSegment = 96;
  final List<vm.Vector3> _points;
  // Distance at the start of each key.
  final List<double> _cumulative = [];
  final List<int> _segmentStart = [];
  // (segment, u, distance at that sample).
  final List<(int, double, double)> _table = [];

  double keyDistance(int i) => _cumulative[math.min(i, _cumulative.length - 1)];

  vm.Vector3 _p(int i) {
    final n = _points.length;
    if (i < 0) return _points[0] * 2 - _points[1];
    if (i >= n) return _points[n - 1] * 2 - _points[n - 2];
    return _points[i];
  }

  // Barry and Goldman's pyramid for the centripetal (alpha 0.5) form.
  vm.Vector3 _segmentPoint(int seg, double u) {
    final p0 = _p(seg - 1), p1 = _p(seg), p2 = _p(seg + 1), p3 = _p(seg + 2);
    double knot(vm.Vector3 a, vm.Vector3 b) =>
        math.max(math.sqrt(a.distanceTo(b)), 1e-4);
    const t0 = 0.0;
    final t1 = t0 + knot(p0, p1);
    final t2 = t1 + knot(p1, p2);
    final t3 = t2 + knot(p2, p3);
    final t = t1 + (t2 - t1) * u;
    vm.Vector3 mix(vm.Vector3 a, vm.Vector3 b, double ta, double tb) =>
        a * ((tb - t) / (tb - ta)) + b * ((t - ta) / (tb - ta));
    final a1 = mix(p0, p1, t0, t1);
    final a2 = mix(p1, p2, t1, t2);
    final a3 = mix(p2, p3, t2, t3);
    final b1 = mix(a1, a2, t0, t2);
    final b2 = mix(a2, a3, t1, t3);
    return mix(b1, b2, t1, t2);
  }

  vm.Vector3 pointAt(double distance) {
    if (_points.length < 2 || _table.isEmpty) return _points.first.clone();
    if (distance <= 0) return _points.first.clone();
    if (distance >= _cumulative.last) return _points.last.clone();
    var lo = 0, hi = _table.length - 1;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (_table[mid].$3 < distance) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    final (seg, u1, d1) = _table[lo];
    final start = _segmentStart[seg];
    final (u0, d0) = lo == start
        ? (0.0, _cumulative[seg])
        : (_table[lo - 1].$2, _table[lo - 1].$3);
    final f = d1 > d0 ? (distance - d0) / (d1 - d0) : 0.0;
    return _segmentPoint(seg, u0 + (u1 - u0) * f);
  }
}

/// A value that follows a moving goal like a focus puller's hand: critically
/// damped, so it settles without overshoot in about [settleSeconds].
///
/// Unlike [CameraTrack], this integrates frame deltas, so use it for goals
/// that come from live simulation (keeping focus on a swimming fish) rather
/// than for keyed values.
///
/// {@category Animation}
class FocusPuller {
  /// Creates a puller resting at [value].
  FocusPuller({required this.value, this.settleSeconds = 0.6});

  /// The current value.
  double value;

  /// Rate of change, per second.
  double velocity = 0;

  /// Roughly how long a step change takes to settle.
  double settleSeconds;

  /// Moves [value] toward [goal] over [deltaSeconds] and returns it.
  double update(double goal, double deltaSeconds) {
    if (deltaSeconds <= 0) return value;
    if (settleSeconds <= 0) {
      velocity = 0;
      return value = goal;
    }
    // The closed-form critically damped step (as in the common SmoothDamp),
    // stable at any frame rate.
    final omega = 4.0 / settleSeconds;
    final x = omega * deltaSeconds;
    final decay = 1 / (1 + x + 0.48 * x * x + 0.235 * x * x * x);
    final change = value - goal;
    final temp = (velocity + omega * change) * deltaSeconds;
    velocity = (velocity - omega * temp) * decay;
    value = goal + (change + temp) * decay;
    return value;
  }
}
