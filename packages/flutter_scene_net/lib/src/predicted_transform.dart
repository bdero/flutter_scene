import 'dart:math';

import 'package:dashwire_replication/dashwire_replication.dart';
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' hide Colors;

import 'transform_replica.dart';

/// Advances a predicted pose by [deltaSeconds] from local input.
///
/// The same movement code should run on the authoritative server so the
/// prediction and the server agree; the client feeds its local input, the
/// server feeds the owner's replicated input.
typedef PredictStep =
    (Vector3 position, Quaternion rotation) Function(
      Vector3 position,
      Quaternion rotation,
      double deltaSeconds,
    );

/// Drives the owning node from a client-side prediction of a [TransformReplica]
/// this client owns, so local input renders instantly instead of a round trip
/// in the past.
///
/// Each frame it advances the predicted pose with [step] and renders it. When
/// an authoritative snapshot arrives (the replica's server-owned pose changes)
/// it adopts that pose and lets the visible discrepancy decay over [smoothing],
/// so corrections ease in rather than pop.
///
/// This is the client half. It adopts each snapshot as truth, which is exact
/// at low latency; it does not yet replay the inputs the server has not acked,
/// so under high latency the correction lags by about the round trip.
// TODO(prediction): replay unacked inputs on top of each authoritative
// snapshot. That needs a sequenced input command stream (client tags inputs,
// server echoes the last-applied sequence), which the replication layer does
// not expose yet. Server-side lag compensation (rewinding other entities to
// the shooter's view) is a separate server concern built on a pose history.
final class PredictedTransformComponent extends Component {
  PredictedTransformComponent(
    this.replica, {
    required this.step,
    this.smoothing = const Duration(milliseconds: 120),
  }) {
    _position = replica.positionVector;
    _rotation = replica.rotationQuaternion;
    replica.position.onChanged((_, _) => _serverPending = true);
    replica.rotation.onChanged((_, _) => _serverPending = true);
  }

  final TransformReplica replica;
  final PredictStep step;

  /// Time constant over which an authoritative correction eases in.
  final Duration smoothing;

  late Vector3 _position;
  late Quaternion _rotation;

  /// Rendered-minus-authoritative offset, decays toward zero.
  final Vector3 _error = Vector3.zero();
  bool _serverPending = false;

  @override
  void update(double deltaSeconds) {
    if (_serverPending) {
      _serverPending = false;
      _reconcile();
    }
    final (position, rotation) = step(_position, _rotation, deltaSeconds);
    _position = position;
    _rotation = rotation;
    if (smoothing.inMicroseconds > 0) {
      _error.scale(exp(-deltaSeconds * 1e6 / smoothing.inMicroseconds));
    } else {
      _error.setZero();
    }
    node.localTransform = Matrix4.compose(
      _position + _error,
      _rotation,
      _unitScale,
    );
  }

  void _reconcile() {
    final serverPosition = replica.positionVector;
    // Keep drawing where we were, then let the gap to the authoritative pose
    // decay through [_error] so the correction eases in.
    final rendered = _position + _error;
    _position = serverPosition;
    _error.setFrom(rendered - serverPosition);
    _rotation = replica.rotationQuaternion;
  }

  static final Vector3 _unitScale = Vector3(1, 1, 1);
}
