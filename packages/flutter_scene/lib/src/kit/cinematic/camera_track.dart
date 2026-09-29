import 'dart:math' as math;
import 'dart:typed_data';

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
/// [smoothing] then low-passes the whole move like a camera with inertia,
/// so acceleration is continuous too: speed changes at keys, stops, and
/// bends at closely spaced keys all round off instead of switching within a
/// frame.
///
/// {@category Animation}
class CameraTrack {
  /// Creates a track through [keys], which must be sorted by time.
  /// [defaultFovRadiansY] and [defaultFStop] fill keys that leave them null.
  CameraTrack(
    List<CameraKey> keys, {
    double defaultFovRadiansY = 45 * math.pi / 180,
    double defaultFStop = 2.8,
    this.smoothing = 0.3,
    this.wander,
  }) : assert(keys.isNotEmpty),
       assert(smoothing >= 0),
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
    // Keyed distances interpolate as keyed. Keys without one focus on the
    // sampled eye-to-target distance, blending in where the two kinds meet.
    _focus = curve((i) => carry((k) => k.focusDistance, i, 0));
    _focusAuto = curve((i) => keys[i].focusDistance == null ? 1 : 0);
    if (smoothing > 0) _smooth();
  }

  /// The keys, sorted by time.
  final List<CameraKey> keys;

  /// Standard deviation in seconds of the Gaussian that low-passes every
  /// sampled channel (eye, target, field of view, focus, aperture, roll).
  ///
  /// Larger values move like a heavier camera. The move passes slightly
  /// inside sharp bends and a [KeyframeEase.stop] becomes a brief slow
  /// drift rather than a dead stop, but a channel that only rises (or only
  /// falls) between keys still never overshoots them. Zero samples the
  /// keyed move exactly.
  final double smoothing;

  // Channels per sample: eye xyz, target xyz, fov, keyed focus, fStop, roll,
  // automatic focus weight.
  static const int _channels = 11;
  static const double _rate = 120;
  late final Float64List _samples;
  late final double _sampleStart;
  late final int _sampleCount;

  late final _ArcSpline _eye;
  late final _ArcSpline _target;
  late final KeyframeCurve _eyeTravel;
  late final KeyframeCurve _targetTravel;
  late final KeyframeCurve _fov;
  late final KeyframeCurve _fStop;
  late final KeyframeCurve _roll;
  late final KeyframeCurve _focus;
  late final KeyframeCurve _focusAuto;

  /// Time of the first key.
  double get startTime => keys.first.time;

  /// Time of the last key.
  double get endTime => keys.last.time;

  // The keyed move, unsmoothed.
  void _raw(double time, Float64List out, int offset) {
    final eye = _eye.pointAt(_eyeTravel.valueAt(time));
    final target = _target.pointAt(_targetTravel.valueAt(time));
    out
      ..[offset] = eye.x
      ..[offset + 1] = eye.y
      ..[offset + 2] = eye.z
      ..[offset + 3] = target.x
      ..[offset + 4] = target.y
      ..[offset + 5] = target.z
      ..[offset + 6] = _fov.valueAt(time)
      ..[offset + 7] = _focus.valueAt(time)
      ..[offset + 8] = _fStop.valueAt(time)
      ..[offset + 9] = _roll.valueAt(time)
      ..[offset + 10] = _focusAuto.valueAt(time);
  }

  // Samples the keyed move at a fixed rate, padded by the kernel's reach
  // (held at the end poses), and convolves each channel with the Gaussian.
  void _smooth() {
    final reach = (3 * smoothing * _rate).ceil();
    _sampleStart = startTime - reach / _rate;
    _sampleCount = ((endTime - startTime) * _rate).ceil() + 2 * reach + 1;
    final raw = Float64List(_sampleCount * _channels);
    for (var i = 0; i < _sampleCount; i++) {
      final t = (_sampleStart + i / _rate).clamp(startTime, endTime);
      _raw(t, raw, i * _channels);
    }
    final kernel = Float64List(2 * reach + 1);
    var sum = 0.0;
    for (var k = -reach; k <= reach; k++) {
      final x = k / (_rate * smoothing);
      sum += kernel[k + reach] = math.exp(-0.5 * x * x);
    }
    for (var k = 0; k < kernel.length; k++) {
      kernel[k] /= sum;
    }
    _samples = Float64List(_sampleCount * _channels);
    final last = _sampleCount - 1;
    for (var i = 0; i < _sampleCount; i++) {
      for (var k = -reach; k <= reach; k++) {
        final j = (i + k).clamp(0, last) * _channels;
        final w = kernel[k + reach];
        for (var c = 0; c < _channels; c++) {
          _samples[i * _channels + c] += raw[j + c] * w;
        }
      }
    }
  }

  // The smoothed samples at [time] through a uniform cubic B-spline, which
  // keeps acceleration continuous between them.
  void _smoothed(double time, Float64List out) {
    final f = (time.clamp(startTime, endTime) - _sampleStart) * _rate;
    final i = f.floor();
    final u = f - i;
    final u2 = u * u, u3 = u2 * u;
    final w0 = (1 - 3 * u + 3 * u2 - u3) / 6;
    final w1 = (4 - 6 * u2 + 3 * u3) / 6;
    final w2 = (1 + 3 * u + 3 * u2 - 3 * u3) / 6;
    final w3 = u3 / 6;
    final last = _sampleCount - 1;
    final a = (i - 1).clamp(0, last) * _channels;
    final b = i.clamp(0, last) * _channels;
    final c = (i + 1).clamp(0, last) * _channels;
    final d = (i + 2).clamp(0, last) * _channels;
    for (var ch = 0; ch < _channels; ch++) {
      out[ch] =
          w0 * _samples[a + ch] +
          w1 * _samples[b + ch] +
          w2 * _samples[c + ch] +
          w3 * _samples[d + ch];
    }
  }

  final Float64List _scratch = Float64List(_channels);

  /// A slow drift layered over the smoothed path, or null for none.
  final CameraWander? wander;

  /// The camera at [time] seconds; clamps outside the keys.
  CameraSample sampleAt(double time) {
    final v = _scratch;
    if (smoothing > 0) {
      _smoothed(time, v);
    } else {
      _raw(time, v, 0);
    }
    final eye = vm.Vector3(v[0], v[1], v[2]);
    final target = vm.Vector3(v[3], v[4], v[5]);
    final drift = wander;
    if (drift != null) {
      final (e, t) = drift.offsetsAt(time, eye.distanceTo(target));
      eye.add(e);
      target.add(t);
    }
    final forward = target - eye;
    final up = vm.Vector3(0, 1, 0);
    final roll = v[9];
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
      fovRadiansY: v[6],
      focusDistance: math.max(
        v[7] + (eye.distanceTo(target) - v[7]) * v[10],
        1e-3,
      ),
      fStop: v[8],
    );
  }
}

/// A slow, deterministic drift for a [CameraTrack], like a camera held by
/// hand or floating: three sines per axis at unrelated frequencies, so it
/// never visibly repeats and never jerks. A pure function of time, so a
/// track stays seekable; for gameplay impacts, see `CameraShake`.
/// {@category Animation}
class CameraWander {
  /// Creates a drift of [amplitude] world units at the eye and [angle]
  /// radians of aim, whose slowest component runs at [frequency] hertz.
  const CameraWander({
    this.amplitude = 0.004,
    this.angle = 0.004,
    this.frequency = 0.15,
    this.seed = 0,
  });

  /// The eye's drift, in world units.
  final double amplitude;

  /// The aim's drift in radians; the target moves this fraction of its
  /// distance from the eye.
  final double angle;

  /// The slowest component's frequency in hertz; the others run 1.73 and
  /// 2.91 times faster.
  final double frequency;

  /// Picks the phases, so two tracks drift differently.
  final int seed;

  static const List<double> _ratios = [1, 1.73, 2.91];

  // One axis of drift in [-1, 1].
  double _axis(double t, int axis) {
    var sum = 0.0, norm = 0.0;
    for (var i = 0; i < _ratios.length; i++) {
      final weight = 1 / (i + 1);
      final phase = (seed * 31 + axis * 7 + i * 13) * 2.399963;
      final hz = frequency * _ratios[i] * (1 + 0.071 * axis);
      sum += weight * math.sin(2 * math.pi * hz * t + phase);
      norm += weight;
    }
    return sum / norm;
  }

  /// The eye's and target's offsets at [time] seconds, for a target
  /// [distance] from the eye.
  (vm.Vector3, vm.Vector3) offsetsAt(double time, double distance) {
    final eye = vm.Vector3(_axis(time, 0), _axis(time, 1), _axis(time, 2))
      ..scale(amplitude);
    final aim = vm.Vector3(_axis(time, 3), _axis(time, 4), _axis(time, 5))
      ..scale(angle * distance);
    return (eye, eye + aim);
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

  static const int _samplesPerSegment = 256;
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

/// A focus distance that follows a moving goal like a focus puller's hand:
/// it starts gently, eases out, and never overshoots, settling in about
/// [settleSeconds].
///
/// It eases in diopters (one over the distance), the scale blur changes on,
/// so racking between near and far subjects reads as even as between two
/// far ones. Two critically damped stages run in series, so a sudden new
/// goal changes the pull's acceleration smoothly instead of jolting it.
///
/// Unlike [CameraTrack], this integrates frame deltas, so use it for goals
/// that come from live simulation (keeping focus on a swimming fish) rather
/// than for keyed values.
///
/// {@category Animation}
class FocusPuller {
  /// Creates a puller resting at [value] metres.
  FocusPuller({required double value, this.settleSeconds = 1.0}) {
    reset(value);
  }

  /// Roughly how long a step change takes to settle.
  double settleSeconds;

  /// The current focus distance.
  double get value => _value;
  double _value = 1;

  // Diopters and their rates for the two stages.
  double _d1 = 1, _v1 = 0, _d2 = 1, _v2 = 0;

  static const double _minDiopters = 1e-4;

  static double _diopters(double distance) => 1 / math.max(distance, 1 / 1e4);

  /// Rests the puller at [value] metres.
  void reset(double value) {
    _d1 = _d2 = _diopters(value);
    _v1 = _v2 = 0;
    _value = value;
  }

  /// Moves toward [goal] metres over [deltaSeconds] and returns the focus
  /// distance.
  double update(double goal, double deltaSeconds) {
    if (deltaSeconds <= 0) return _value;
    if (settleSeconds <= 0) {
      reset(goal);
      return _value;
    }
    // Two stages in series settle in about twice one stage's time.
    final stage = settleSeconds / 2;
    final target = _diopters(goal);
    // A goal at the current focus stops the pull there; retained speed
    // would otherwise carry it away and back.
    if ((_d2 - target).abs() <= 1e-9 * target) {
      reset(goal);
      return _value;
    }
    var (d1, v1) = _step(_d1, _v1, target, stage, deltaSeconds);
    // A goal that moves mid-pull leaves speed the stages would carry past
    // it, so neither may cross the goal from the side it started on.
    if (_crossed(_d1, d1, target)) (d1, v1) = (target, 0.0);
    // The output chases stage one, but never past the goal: stage one can
    // be beyond it, still carrying the old goal's pull.
    final side = _d2 - target;
    final chase = side == 0 || (d1 - target) * side < 0 ? target : d1;
    var (d2, v2) = _step(_d2, _v2, chase, stage, deltaSeconds);
    if (_crossed(_d2, d2, target)) (d2, v2) = (target, 0.0);
    _d1 = d1;
    _v1 = v1;
    _d2 = d2;
    _v2 = v2;
    return _value = 1 / math.max(_d2, _minDiopters);
  }

  static bool _crossed(double from, double to, double goal) =>
      (from - goal) * (to - goal) < 0;

  // The closed-form critically damped step (as in the common SmoothDamp),
  // stable at any frame rate.
  static (double, double) _step(
    double value,
    double velocity,
    double goal,
    double settle,
    double dt,
  ) {
    final omega = 4.0 / settle;
    final x = omega * dt;
    final decay = 1 / (1 + x + 0.48 * x * x + 0.235 * x * x * x);
    final change = value - goal;
    final temp = (velocity + omega * change) * dt;
    return (goal + (change + temp) * decay, (velocity - omega * temp) * decay);
  }
}
