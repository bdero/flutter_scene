import 'dart:math' as math;

import 'package:vector_math/vector_math.dart' as vm;

/// How a [Keyframe] shapes the curve arriving at it.
///
/// {@category Animation}
enum KeyframeEase {
  /// Passes through the key with the slope of its neighbors, so motion flows
  /// on without a stop. The default.
  smooth,

  /// Arrives at the key and leaves it with zero velocity, a settled pose.
  stop,

  /// Straight lines into and out of the key.
  linear,

  /// Holds the previous value until the key, then jumps.
  hold,
}

/// One key on a [KeyframeTrack].
///
/// {@category Animation}
class Keyframe<T> {
  /// Creates a key with [value] at [time] seconds.
  const Keyframe(this.time, this.value, {this.ease = KeyframeEase.smooth});

  /// Time of the key in seconds.
  final double time;

  /// Value at [time].
  final T value;

  /// How the curve passes through this key.
  final KeyframeEase ease;
}

/// A scalar curve through keys, a monotone cubic Hermite interpolant.
///
/// Between keys it never overshoots the neighboring values (Fritsch and
/// Carlson's slope limiting), which is what keeps a camera or a light from
/// wobbling past its mark, while staying smooth through [KeyframeEase.smooth]
/// keys.
///
/// {@category Animation}
class KeyframeCurve {
  /// Creates a curve through [keys], which must be sorted by time.
  KeyframeCurve(List<Keyframe<double>> keys)
    : assert(keys.isNotEmpty),
      _keys = List.unmodifiable(keys) {
    for (var i = 1; i < keys.length; i++) {
      assert(keys[i].time >= keys[i - 1].time, 'keys must be time sorted');
    }
    _slopes = _computeSlopes();
  }

  final List<Keyframe<double>> _keys;
  late final List<double> _slopes;

  /// The keys, sorted by time.
  List<Keyframe<double>> get keys => _keys;

  /// Time of the first key.
  double get startTime => _keys.first.time;

  /// Time of the last key.
  double get endTime => _keys.last.time;

  List<double> _computeSlopes() {
    final n = _keys.length;
    final m = List<double>.filled(n, 0);
    if (n < 2) return m;
    final delta = <double>[];
    for (var i = 0; i < n - 1; i++) {
      final dt = _keys[i + 1].time - _keys[i].time;
      delta.add(dt <= 0 ? 0 : (_keys[i + 1].value - _keys[i].value) / dt);
    }
    for (var i = 0; i < n; i++) {
      final ease = _keys[i].ease;
      if (ease == KeyframeEase.stop || i == 0 || i == n - 1) {
        // Ends start and finish at rest, which reads as a deliberate move.
        m[i] = 0;
        continue;
      }
      final a = delta[i - 1], b = delta[i];
      // An extremum or a flat side: stop there rather than overshoot.
      m[i] = a * b <= 0 ? 0 : (a + b) / 2;
    }
    // Fritsch and Carlson: limit each interval's slopes to keep it monotone.
    for (var i = 0; i < n - 1; i++) {
      final d = delta[i];
      if (d == 0) {
        m[i] = 0;
        m[i + 1] = 0;
        continue;
      }
      final alpha = m[i] / d, beta = m[i + 1] / d;
      final s = alpha * alpha + beta * beta;
      if (s > 9) {
        final tau = 3 / math.sqrt(s);
        m[i] = tau * alpha * d;
        m[i + 1] = tau * beta * d;
      }
    }
    return m;
  }

  /// The curve's value at [time] seconds; clamps outside the keys.
  double valueAt(double time) {
    final keys = _keys;
    if (time <= keys.first.time) return keys.first.value;
    if (time >= keys.last.time) return keys.last.value;
    var hi = 1;
    while (keys[hi].time < time) {
      hi++;
    }
    final a = keys[hi - 1], b = keys[hi];
    final dt = b.time - a.time;
    if (dt <= 0) return b.value;
    // A hold jumps on its key's own timestamp.
    if (b.ease == KeyframeEase.hold) return time >= b.time ? b.value : a.value;
    final u = (time - a.time) / dt;
    if (b.ease == KeyframeEase.linear || a.ease == KeyframeEase.linear) {
      return a.value + (b.value - a.value) * u;
    }
    final u2 = u * u, u3 = u2 * u;
    final h00 = 2 * u3 - 3 * u2 + 1;
    final h10 = u3 - 2 * u2 + u;
    final h01 = -2 * u3 + 3 * u2;
    final h11 = u3 - u2;
    return h00 * a.value +
        h10 * dt * _slopes[hi - 1] +
        h01 * b.value +
        h11 * dt * _slopes[hi];
  }
}

/// A keyed value over time, for any type built from doubles.
///
/// Each component interpolates as its own [KeyframeCurve], so a vector or a
/// color eases component-wise with no overshoot.
///
/// {@category Animation}
class KeyframeTrack<T> {
  /// Creates a track through [keys] (sorted by time), splitting each value
  /// into [components] doubles with [toComponents] and rebuilding it with
  /// [fromComponents].
  KeyframeTrack(
    List<Keyframe<T>> keys, {
    required int components,
    required List<double> Function(T value) toComponents,
    required T Function(List<double> components) fromComponents,
  }) : _fromComponents = fromComponents,
       _curves = [
         for (var c = 0; c < components; c++)
           KeyframeCurve([
             for (final k in keys)
               Keyframe(k.time, toComponents(k.value)[c], ease: k.ease),
           ]),
       ];

  final List<KeyframeCurve> _curves;
  final T Function(List<double> components) _fromComponents;

  /// A track of plain doubles.
  static KeyframeTrack<double> scalar(List<Keyframe<double>> keys) =>
      KeyframeTrack<double>(
        keys,
        components: 1,
        toComponents: (v) => [v],
        fromComponents: (c) => c[0],
      );

  /// A track of [vm.Vector3] values.
  static KeyframeTrack<vm.Vector3> vector3(List<Keyframe<vm.Vector3>> keys) =>
      KeyframeTrack<vm.Vector3>(
        keys,
        components: 3,
        toComponents: (v) => [v.x, v.y, v.z],
        fromComponents: (c) => vm.Vector3(c[0], c[1], c[2]),
      );

  /// A track of [vm.Vector4] values (colors, for example).
  static KeyframeTrack<vm.Vector4> vector4(List<Keyframe<vm.Vector4>> keys) =>
      KeyframeTrack<vm.Vector4>(
        keys,
        components: 4,
        toComponents: (v) => [v.x, v.y, v.z, v.w],
        fromComponents: (c) => vm.Vector4(c[0], c[1], c[2], c[3]),
      );

  /// The value at [time] seconds; clamps outside the keys.
  T valueAt(double time) =>
      _fromComponents([for (final c in _curves) c.valueAt(time)]);
}

/// A named moment on a [Timeline].
///
/// {@category Animation}
class Cue {
  /// Creates a cue called [name] at [time] seconds.
  const Cue(this.time, this.name);

  /// Time in seconds.
  final double time;

  /// What the cue signals, for the listener to match on.
  final String name;

  @override
  String toString() => 'Cue($name @ ${time}s)';
}

/// A time-evaluated playhead that fires [Cue]s as it passes them.
///
/// Everything driven by a timeline should be a function of [time] (sample
/// [KeyframeTrack]s and [CameraTrack]s at it) rather than integrated from
/// frame deltas, so a timeline can seek, scrub, loop, and step at a fixed
/// rate and produce the same frame for the same time.
///
/// {@category Animation}
class Timeline {
  /// Creates a timeline [duration] seconds long with [cues], calling
  /// [onCue] for each cue the playhead crosses.
  Timeline({
    required this.duration,
    List<Cue> cues = const [],
    this.onCue,
    this.loop = false,
  }) : cues = List<Cue>.unmodifiable(List<Cue>.of(cues)..sort(_byTime));

  static int _byTime(Cue a, Cue b) => a.time.compareTo(b.time);

  /// Length in seconds.
  final double duration;

  /// Cues sorted by time.
  final List<Cue> cues;

  /// Called for each cue the playhead crosses, in time order.
  void Function(Cue cue)? onCue;

  /// Whether the playhead wraps to 0 at [duration] (firing the crossed cues
  /// again on each pass) instead of stopping there.
  bool loop;

  double _time = 0;
  bool _started = false;

  /// The playhead in seconds.
  double get time => _time;

  /// Whether a non-looping timeline has reached its end.
  bool get finished => !loop && _time >= duration;

  /// Moves the playhead forward by [seconds], firing the cues it crosses.
  void advance(double seconds) {
    if (seconds <= 0 && _started) return;
    seek(_time + seconds);
  }

  /// Moves the playhead to [time]. Moving forward fires the cues crossed
  /// (including one exactly at [time]); moving backward fires none, so a
  /// scrub back then forward replays them.
  void seek(double time) {
    var from = _time;
    var to = time;
    if (loop && duration > 0) {
      while (to >= duration) {
        _fire(from, duration, inclusiveEnd: false);
        to -= duration;
        from = 0;
        _started = false;
      }
    } else {
      to = to.clamp(0.0, duration);
    }
    if (to >= from) {
      _fire(from, to, inclusiveEnd: true);
    } else {
      // A cue exactly at the new playhead fires when playback resumes.
      _started = false;
    }
    _time = to;
  }

  void _fire(double from, double to, {required bool inclusiveEnd}) {
    final listener = onCue;
    for (final cue in cues) {
      final afterStart = _started ? cue.time > from : cue.time >= from;
      final beforeEnd = inclusiveEnd ? cue.time <= to : cue.time < to;
      if (afterStart && beforeEnd) listener?.call(cue);
    }
    _started = true;
  }
}
