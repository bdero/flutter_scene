import 'dart:math';

import 'package:dashwire/dashwire.dart';
import 'package:dashwire_replication/dashwire_replication.dart';
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' hide Colors;

import 'transform_replica.dart';

/// Drives the owning node's transform from a [TransformReplica].
///
/// Replicated poses arrive at packet rate; rendering [delay] in the past
/// through a small sample buffer turns them into smooth motion, the
/// standard snapshot-interpolation tradeoff of latency for continuity.
// TODO(prediction): owned replicas currently render on the same delayed
// timeline as everything else; input-replay prediction needs the tick
// infrastructure wired through here.
final class NetworkTransformComponent extends Component {
  NetworkTransformComponent(
    this.replica, {
    this.delay = const Duration(milliseconds: 100),
    NowMicros now = defaultNowMicros,
  }) : _now = now {
    _push();
    replica.position.onChanged((_, _) => _push());
    replica.rotation.onChanged((_, _) => _push());
  }

  final TransformReplica replica;

  /// How far in the past remote poses render.
  final Duration delay;

  final NowMicros _now;

  final List<(int, Vector3, Quaternion)> _samples = [];

  void _push() {
    final now = _now();
    // Samples are only pushed on pose change, so after an idle stretch the
    // newest one is stale. Re-anchor the held pose at now - delay before
    // appending the fresh one, so resuming motion eases in over `delay`
    // instead of interpolating across the whole gap (which snaps forward).
    if (_samples.isNotEmpty && now - _samples.last.$1 > delay.inMicroseconds) {
      final (_, p, q) = _samples.last;
      _samples
        ..clear()
        ..add((now - delay.inMicroseconds, p, q));
    }
    _samples.add((now, replica.positionVector, replica.rotationQuaternion));
    if (_samples.length > 64) _samples.removeAt(0);
  }

  @override
  void update(double deltaSeconds) {
    final (position, rotation) = sampleAt(_now() - delay.inMicroseconds);
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
