import 'dart:math';
import 'dart:typed_data';

import 'package:dashwire/dashwire.dart';
import 'package:dashwire_replication/dashwire_replication.dart';
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' hide Colors;

import 'transform_replica.dart';

/// Client-side driver for an owned, predicted entity.
///
/// [sampleInput] captures and encodes this tick's local input for the wire.
/// [step] integrates a pose one fixed tick under a decoded input and must
/// match the server's integration exactly (share one function) so replay
/// reconciliation converges. Encode one-frame events (a jump, a shot) as
/// counters, not booleans, so a resent command reproduces them.
abstract interface class PredictedController {
  Uint8List sampleInput();

  (Vector3 position, Quaternion rotation) step(
    Vector3 position,
    Quaternion rotation,
    Uint8List input,
    double dt,
  );
}

/// Drives the node of an owned [TransformReplica] by client-side prediction
/// with authoritative input-replay reconciliation, so local input renders
/// instantly while the sim stays server-authoritative.
///
/// Each fixed tick it samples and sends an input command, advances the
/// prediction, and stores `(tick, input, pose)`. When the server confirms the
/// authoritative pose after an input tick (via the input-command ack) it rolls
/// the prediction back to that pose and replays the not-yet-applied inputs.
/// A correction decays through a visual error offset over [smoothing] rather
/// than popping.
final class PredictedTransformComponent extends Component {
  PredictedTransformComponent(
    this.replica, {
    required this.controller,
    required this.client,
    required int tickRate,
    this.smoothing = const Duration(milliseconds: 120),
    this.correctionThreshold = 0.05,
    NowMicros now = defaultNowMicros,
  }) : _dt = 1 / tickRate,
       _now = now {
    _predictor = Predictor<Uint8List, (Vector3, Quaternion)>(
      step: (state, input, dt) =>
          controller.step(state.$1, state.$2, input, dt),
      dt: _dt,
      diverged: (a, b) => (a.$1 - b.$1).length > correctionThreshold,
    );
  }

  final TransformReplica replica;
  final PredictedController controller;
  final ReplicationClient client;

  /// Time constant over which an authoritative correction eases in.
  final Duration smoothing;

  /// Positional divergence (metres) beyond which a snapshot triggers a replay
  /// correction.
  final double correctionThreshold;

  final double _dt;
  final NowMicros _now;

  late final Predictor<Uint8List, (Vector3, Quaternion)> _predictor;
  final Vector3 _error = Vector3.zero();
  int _reconciledTick = -1;

  @override
  void update(double deltaSeconds) {
    final clock = client.session.clock;
    if (!clock.isSynchronized) return;
    final target = clock.inputTickAt(_now());

    if (!_predictor.isSeeded) {
      _predictor.reset(target - 1, (
        replica.positionVector,
        replica.rotationQuaternion,
      ));
    }

    // Reconcile against the authoritative pose the server has confirmed
    // applying input through.
    final acked = client.lastAppliedInputTick;
    if (acked > _reconciledTick &&
        acked > 0 &&
        acked <= _predictor.currentTick) {
      final rendered = _predictor.current.$1 + _error;
      final corrected = _predictor.reconcile(acked, (
        replica.positionVector,
        replica.rotationQuaternion,
      ));
      _reconciledTick = acked;
      if (corrected) _error.setFrom(rendered - _predictor.current.$1);
    }

    // Predict forward to the target tick, one input sampled and sent per tick.
    while (_predictor.currentTick < target) {
      final tick = _predictor.currentTick + 1;
      final input = controller.sampleInput();
      _predictor.advance(tick, input);
      client.sendInput(input, tick: tick);
    }

    if (smoothing.inMicroseconds > 0) {
      _error.scale(exp(-deltaSeconds * 1e6 / smoothing.inMicroseconds));
    } else {
      _error.setZero();
    }
    final (position, rotation) = _predictor.current;
    node.localTransform = Matrix4.compose(
      position + _error,
      rotation,
      _unitScale,
    );
  }

  static final Vector3 _unitScale = Vector3(1, 1, 1);
}
