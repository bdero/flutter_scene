import 'dart:math';
import 'dart:typed_data';

import 'package:dashwire/dashwire.dart';
import 'package:dashwire_replication/dashwire_replication.dart';
import 'package:flutter_scene/physics.dart';
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' hide Colors;

import 'predicted_transform.dart';
import 'transform_replica.dart';

/// Client-side driver for an owned entity simulated by a physics world.
///
/// The controller owns a [simulation] dedicated to prediction (the arena plus
/// the owned body, built the same way as the server's world) with
/// `supportsSnapshot`. [applyInput] applies a decoded input command to the
/// body before a step and must match the server's application exactly so
/// replay reconciliation converges. Encode one-frame events as counters, not
/// booleans, so a resent command reproduces them.
///
/// The authoritative velocity getters read velocity reps off the replica at
/// reconcile time; return null when velocity is not replicated and the
/// predicted velocity at the acked tick is kept (corrections then converge
/// over subsequent snapshots instead of in one replay).
abstract interface class PredictedPhysicsController
    implements PredictionController {
  PhysicsSimulation get simulation;

  /// Handle of the owned body inside [simulation].
  int get bodyHandle;

  Uint8List sampleInput();

  void applyInput(Uint8List input, double dt);

  /// Called after a rollback correction restores a retained world snapshot,
  /// before pending inputs replay. Bodies the controller created after that
  /// snapshot no longer exist (their handles dangle silently), so mark any
  /// dynamically managed bodies, remote-player proxies, say, for recreation
  /// on the next fresh tick.
  void onWorldRestored();

  Vector3? get authoritativeLinearVelocity;

  Vector3? get authoritativeAngularVelocity;
}

/// A retained per-tick prediction, the serialized world plus the owned
/// body's state read back after the step.
final class _WorldState {
  _WorldState(
    this.world,
    this.position,
    this.rotation,
    this.linearVelocity,
    this.angularVelocity,
  );

  final Uint8List world;
  final Vector3 position;
  final Quaternion rotation;
  final Vector3 linearVelocity;
  final Vector3 angularVelocity;
}

/// Drives the node of an owned [TransformReplica] by physics rollback
/// prediction with authoritative input-replay reconciliation.
///
/// Each fixed tick it samples and sends an input command, applies it to the
/// owned body, steps the controller's prediction world, and retains the tick's
/// world snapshot. When the server confirms the authoritative pose after an
/// input tick, a diverged prediction is corrected by restoring the snapshot at
/// that tick, teleporting the body to the authoritative pose (and velocity
/// when replicated), and replaying the not-yet-applied inputs through the
/// world. A correction decays through a visual error offset over [smoothing]
/// rather than popping.
///
/// Snapshots are whole-world, so keep the prediction world small (the owned
/// body plus static geometry). TODO(prediction): per-island snapshots to
/// bound cost in larger predicted scenes.
final class PredictedPhysicsComponent extends Component {
  PredictedPhysicsComponent(
    this.replica, {
    required this.controller,
    required this.client,
    required int tickRate,
    this.smoothing = const Duration(milliseconds: 120),
    this.correctionThreshold = 0.05,
    int historyTicks = 64,
    this.maxCatchUpTicks = 16,
    NowMicros now = defaultNowMicros,
  }) : _dt = 1 / tickRate,
       _now = now {
    _predictor = Predictor<Uint8List, _WorldState>(
      step: _step,
      dt: _dt,
      diverged: (a, b) =>
          (a.position - b.position).length > correctionThreshold,
      historyLength: historyTicks,
    );
  }

  final TransformReplica replica;
  final PredictedPhysicsController controller;
  final ReplicationClient client;

  /// Time constant over which an authoritative correction eases in.
  final Duration smoothing;

  /// Positional divergence (metres) beyond which a snapshot triggers a replay
  /// correction.
  final double correctionThreshold;

  /// Most ticks predicted in one [update] before the prediction snaps to
  /// authority instead of catching up.
  ///
  /// The target tick comes from the wall clock, so a stall (a backgrounded
  /// tab, a long hitch, a resume from pause) would otherwise step and snapshot
  /// the world once per missed tick in a single frame. Lower than the
  /// transform component's cap because each tick here costs a world step plus
  /// a full snapshot.
  final int maxCatchUpTicks;

  final double _dt;
  final NowMicros _now;

  late final Predictor<Uint8List, _WorldState> _predictor;
  final Vector3 _error = Vector3.zero();
  int _reconciledTick = -1;

  /// The snapshot the live world currently equals, so the fresh-prediction
  /// hot path skips the restore and only replay pays for it.
  Uint8List? _liveWorld;

  _WorldState _step(_WorldState state, Uint8List input, double dt) {
    final sim = controller.simulation;
    if (!identical(state.world, _liveWorld)) {
      sim.restore(state.world);
      controller.onWorldRestored();
    }
    // The state's body fields override the restored world, so an
    // authoritative base injected by reconcile takes effect here.
    sim.setBodyPose(controller.bodyHandle, state.position, state.rotation);
    sim.setBodyLinearVelocity(controller.bodyHandle, state.linearVelocity);
    sim.setBodyAngularVelocity(controller.bodyHandle, state.angularVelocity);
    controller.applyInput(input, dt);
    sim.step(dt);
    return _capture();
  }

  _WorldState _capture() {
    final sim = controller.simulation;
    final (position, rotation) = sim.readBodyPose(controller.bodyHandle);
    final state = _WorldState(
      sim.snapshot(),
      position,
      rotation,
      sim.readBodyLinearVelocity(controller.bodyHandle),
      sim.readBodyAngularVelocity(controller.bodyHandle),
    );
    _liveWorld = state.world;
    return state;
  }

  /// The replay base for a reconcile, the retained world at [ackedTick] with
  /// the authoritative pose (and velocity when replicated) overriding the
  /// owned body.
  _WorldState _authoritativeState(int ackedTick) {
    final predicted = _predictor.stateAt(ackedTick);
    return _WorldState(
      predicted?.world ?? _predictor.current.world,
      replica.positionVector,
      replica.rotationQuaternion,
      controller.authoritativeLinearVelocity ??
          predicted?.linearVelocity ??
          _predictor.current.linearVelocity,
      controller.authoritativeAngularVelocity ??
          predicted?.angularVelocity ??
          _predictor.current.angularVelocity,
    );
  }

  @override
  void update(double deltaSeconds) {
    final clock = client.session.clock;
    if (!clock.isSynchronized) return;
    final target = clock.inputTickAt(_now());

    if (!_predictor.isSeeded) {
      _predictor.reset(target - 1, _capture());
    }

    // Reconcile against the authoritative pose the server has confirmed
    // applying input through.
    final acked = client.lastAppliedInputTick;
    if (acked > _reconciledTick &&
        acked > 0 &&
        acked <= _predictor.currentTick) {
      final rendered = _predictor.current.position + _error;
      final corrected = _predictor.reconcile(acked, _authoritativeState(acked));
      _reconciledTick = acked;
      if (corrected) _error.setFrom(rendered - _predictor.current.position);
    }

    // Too far behind to catch up tick by tick, so teleport the owned body to
    // the newest authoritative pose and resume predicting from there.
    if (target - _predictor.currentTick > maxCatchUpTicks) {
      final sim = controller.simulation;
      final handle = controller.bodyHandle;
      sim.setBodyPose(
        handle,
        replica.positionVector,
        replica.rotationQuaternion,
      );
      final linear = controller.authoritativeLinearVelocity;
      final angular = controller.authoritativeAngularVelocity;
      if (linear != null) sim.setBodyLinearVelocity(handle, linear);
      if (angular != null) sim.setBodyAngularVelocity(handle, angular);
      _predictor.reset(target - 1, _capture());
      _error.setZero();
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
    final state = _predictor.current;
    node.localTransform = Matrix4.compose(
      state.position + _error,
      state.rotation,
      _unitScale,
    );
  }

  static final Vector3 _unitScale = Vector3(1, 1, 1);
}
