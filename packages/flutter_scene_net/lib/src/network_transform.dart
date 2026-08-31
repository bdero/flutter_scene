import 'dart:math';

import 'package:dashwire/dashwire.dart';
import 'package:dashwire_replication/dashwire_replication.dart';
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' hide Colors;

import 'transform_replica.dart';

/// Drives the owning node's transform from a [TransformReplica].
///
/// Replicated poses arrive at packet rate; rendering a little in the past
/// through a small sample buffer turns them into smooth motion, the
/// standard snapshot-interpolation tradeoff of latency for continuity. The
/// delay sizes itself from the measured arrival cadence and jitter, easing
/// between [minDelay] and [delay] (the ceiling and starting value), so a
/// clean local link renders barely behind while a jittery one buffers deep.
///
/// An owned, predicted entity uses `PredictedTransformComponent` instead, so
/// local input renders instantly rather than a delay in the past.
final class NetworkTransformComponent extends Component {
  NetworkTransformComponent(
    this.replica, {
    this.slot = '',
    this.delay = const Duration(milliseconds: 100),
    this.minDelay = const Duration(milliseconds: 25),
    this.adaptive = true,
    NowMicros now = defaultNowMicros,
  }) : _now = now,
       _delayMicros = delay.inMicroseconds {
    _push();
    // TODO(replication-unsubscribe): dashwire_replication 0.2.0 has no
    // listener removal, so these subscriptions (and through them this
    // component) live as long as the replica; add removal upstream and tear
    // down on detach.
    replica.position.onChanged((_, _) => _push());
    replica.rotation.onChanged((_, _) => _push());
  }

  final TransformReplica replica;

  /// The name this component was resolved from, kept so serializing it writes
  /// the same slot back.
  ///
  /// Empty for a component built directly in code, which has no name to
  /// write: the document would gain a slot nobody registered and the next
  /// load would report it missing.
  final String slot;

  /// The deepest (and initial) render delay; the fixed delay when
  /// [adaptive] is off.
  final Duration delay;

  /// The shallowest the adaptive delay will go.
  final Duration minDelay;

  /// Whether the delay tracks measured arrival cadence and jitter.
  final bool adaptive;

  final NowMicros _now;

  final List<(int, Vector3, Quaternion)> _samples = [];
  int _delayMicros;
  int _lastArrival = 0;
  double _intervalEwma = 0;
  double _jitterEwma = 0;

  /// How far in the past remote poses currently render.
  Duration get currentDelay => Duration(microseconds: _delayMicros);

  void _push() {
    final now = _now();
    // Samples are only pushed on pose change, so after an idle stretch the
    // newest one is stale. Re-anchor the held pose at now - delay before
    // appending the fresh one, so resuming motion eases in over the delay
    // instead of interpolating across the whole gap (which snaps forward).
    // Idleness is judged against the fixed ceiling, not the adapted delay,
    // so a jitter spike is measured rather than mistaken for a gap.
    if (_samples.isNotEmpty && now - _samples.last.$1 > delay.inMicroseconds) {
      final (_, p, q) = _samples.last;
      _samples
        ..clear()
        ..add((now - _delayMicros, p, q));
      _lastArrival = 0; // The cadence measurement restarts after a gap.
    }
    _adapt(now);
    _samples.add((now, replica.positionVector, replica.rotationQuaternion));
    if (_samples.length > 64) _samples.removeAt(0);
  }

  // Sizes the delay off the arrival stream, enough to bridge one and a half
  // typical intervals plus a few deviations, eased so the render timeline
  // never jumps.
  void _adapt(int now) {
    if (!adaptive) return;
    if (_lastArrival != 0) {
      final interval = (now - _lastArrival).toDouble();
      _intervalEwma = _intervalEwma == 0
          ? interval
          : _intervalEwma + (interval - _intervalEwma) * 0.1;
      final deviation = (interval - _intervalEwma).abs();
      _jitterEwma += (deviation - _jitterEwma) * 0.1;
      final target = (_intervalEwma * 1.5 + _jitterEwma * 4).clamp(
        minDelay.inMicroseconds.toDouble(),
        delay.inMicroseconds.toDouble(),
      );
      _delayMicros += ((target - _delayMicros) * 0.05).round();
    }
    _lastArrival = now;
  }

  @override
  void update(double deltaSeconds) {
    final (position, rotation) = sampleAt(_now() - _delayMicros);
    node.localTransform = Matrix4.compose(position, rotation, _unitScale);
  }

  static final Vector3 _unitScale = Vector3(1, 1, 1);

  /// The interpolated pose at monotonic time [micros].
  (Vector3, Quaternion) sampleAt(int micros) {
    final first = _samples.first;
    if (_samples.length == 1 || micros <= first.$1) {
      return (first.$2, first.$3);
    }
    for (var i = 0; i < _samples.length - 1; i++) {
      final (t0, p0, q0) = _samples[i];
      final (t1, p1, q1) = _samples[i + 1];
      if (micros >= t0 && micros <= t1) {
        final f = (micros - t0) / (t1 - t0);
        return (_lerp(p0, p1, f), _slerp(q0, q1, f));
      }
    }
    final last = _samples.last;
    return (last.$2, last.$3);
  }

  static Vector3 _lerp(Vector3 a, Vector3 b, double f) => Vector3(
    a.x + (b.x - a.x) * f,
    a.y + (b.y - a.y) * f,
    a.z + (b.z - a.z) * f,
  );

  static Quaternion _slerp(Quaternion a, Quaternion b, double f) {
    var dot = a.x * b.x + a.y * b.y + a.z * b.z + a.w * b.w;
    var bx = b.x, by = b.y, bz = b.z, bw = b.w;
    // Take the short arc; q and -q are the same rotation.
    if (dot < 0) {
      dot = -dot;
      bx = -bx;
      by = -by;
      bz = -bz;
      bw = -bw;
    }
    // Nearly parallel, normalized lerp avoids the degenerate divide.
    if (dot > 0.9995) {
      final q = Quaternion(
        a.x + (bx - a.x) * f,
        a.y + (by - a.y) * f,
        a.z + (bz - a.z) * f,
        a.w + (bw - a.w) * f,
      );
      return q..normalize();
    }
    final theta = acos(dot);
    final sinTheta = sin(theta);
    final wa = sin((1 - f) * theta) / sinTheta;
    final wb = sin(f * theta) / sinTheta;
    return Quaternion(
      a.x * wa + bx * wb,
      a.y * wa + by * wb,
      a.z * wa + bz * wb,
      a.w * wa + bw * wb,
    );
  }
}
