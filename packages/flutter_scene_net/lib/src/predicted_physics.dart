import 'dart:math';
import 'dart:typed_data';

import 'package:dashwire/dashwire.dart';
import 'package:dashwire_replication/dashwire_replication.dart';
import 'package:flutter_scene/physics.dart';
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' hide Colors;

import 'predicted_transform.dart';
import 'transform_replica.dart';

/// Bounds what a retained prediction tick has to carry.
///
/// Implement alongside [PredictedPhysicsController] to opt in. Without it a
/// tick retains the whole serialized world, which is always correct and costs
/// the whole world every tick — sixty-four retained ticks of a scene that
/// mostly is not moving is what makes a large predicted scene expensive.
///
/// **The set must be closed under interaction over the rollback window**:
/// every body that can touch the owned body, and every body those can touch,
/// for as many ticks as can be replayed. Anything outside it is not restored,
/// so if it could have influenced the replay the correction silently diverges.
/// That is the closure a solver island describes; this asks for it rather than
/// deriving it, because the simulation interface has no island query and a
/// wrong answer here is worse than a slow one.
///
/// The set must also be fixed for the life of the prediction, for the same
/// reason [PredictedPhysicsController.onWorldRestored] describes: a retained
/// tick knows the bodies it captured, and a set that changed underneath it
/// cannot be put back.
abstract interface class PredictedBodyScope {
  /// The bodies whose state each retained tick carries.
  List<int> get predictedBodies;
}

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
  /// before pending inputs replay.
  ///
  /// A restore rewinds to the body set its snapshot captured, so bodies
  /// created since are gone and their handles dangle. Recreating them here or
  /// on the next fresh tick does not hold, since the next correction restores
  /// an older snapshot that knows only the previous handles and reconciles
  /// both sets away. Allocate a fixed pool before the first snapshot instead,
  /// parking unused bodies out of reach, so the body set never changes and
  /// this hook has nothing to repair.
  void onWorldRestored();

  Vector3? get authoritativeLinearVelocity;

  Vector3? get authoritativeAngularVelocity;
}

/// A retained per-tick prediction, the serialized world plus the owned
/// body's state read back after the step.
final class _WorldState {
  _WorldState(
    this.world,
    this.bodies,
    this.position,
    this.rotation,
    this.linearVelocity,
    this.angularVelocity,
  );

  /// The serialized world, or null when this tick retained a body set.
  final Uint8List? world;

  /// The retained bodies' state, thirteen floats each (pose, then linear and
  /// angular velocity), or null when this tick retained the whole world.
  final Float32List? bodies;

  final Vector3 position;
  final Quaternion rotation;
  final Vector3 linearVelocity;
  final Vector3 angularVelocity;
}

/// Floats one body occupies in a retained set: position, rotation, linear and
/// angular velocity.
const int floatsPerPredictedBody = 3 + 4 + 3 + 3;

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
/// A retained tick is the whole serialized world by default, so keep the
/// prediction world small (the owned body plus static geometry). A controller
/// that also implements [PredictedBodyScope] retains only the bodies it names,
/// which bounds the cost by that set rather than by the world — see that
/// interface for what the set has to contain to stay correct.
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

  /// The state the live world currently equals, so the fresh-prediction hot
  /// path skips the restore and only replay pays for it.
  _WorldState? _liveState;

  _WorldState _step(_WorldState state, Uint8List input, double dt) {
    final sim = controller.simulation;
    if (!identical(state, _liveState)) {
      _restore(state);
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
    final handles = _scopedBodies;
    final state = _WorldState(
      handles == null ? sim.snapshot() : null,
      handles == null ? null : capturePredictedBodies(sim, handles),
      position,
      rotation,
      sim.readBodyLinearVelocity(controller.bodyHandle),
      sim.readBodyAngularVelocity(controller.bodyHandle),
    );
    _liveState = state;
    return state;
  }

  /// The replay base for a reconcile: the retained tick at [ackedTick] with
  /// the authoritative pose (and velocity when replicated) overriding the
  /// owned body.
  _WorldState _authoritativeState(int ackedTick) {
    final predicted = _predictor.stateAt(ackedTick) ?? _predictor.current;
    return _WorldState(
      predicted.world,
      predicted.bodies,
      replica.positionVector,
      replica.rotationQuaternion,
      controller.authoritativeLinearVelocity ?? predicted.linearVelocity,
      controller.authoritativeAngularVelocity ?? predicted.angularVelocity,
    );
  }

  /// Puts [state] back into the live simulation.
  void _restore(_WorldState state) {
    final sim = controller.simulation;
    final world = state.world;
    if (world != null) {
      sim.restore(world);
      return;
    }
    final bodies = state.bodies;
    final handles = _scopedBodies;
    if (bodies == null || handles == null) return;
    restorePredictedBodies(sim, handles, bodies);
  }

  /// The declared body set, or null when this controller retains the world.
  List<int>? get _scopedBodies {
    final scope = controller;
    if (scope is! PredictedBodyScope) return null;
    return (scope as PredictedBodyScope).predictedBodies;
  }

  @override
  void update(double deltaSeconds) {
    final clock = client.session.clock;
    if (!clock.isSynchronized) return;
    // Pace the send-ahead from the client's adaptive lead. Passing an
    // explicit tick to sendInput bypasses the sender's own pacing, so
    // sampling the lead here is what keeps the server's buffer-depth control
    // loop closed and lets the lead deepen under jitter.
    final target = clock.inputTickAt(
      _now(),
      marginTicks: client.inputLeadTicks.toDouble(),
    );

    if (!_predictor.isSeeded) {
      _predictor.reset(target - 1, _capture());
    }

    // Reconcile against the authoritative pose, at the tick that pose
    // actually belongs to. The input ack goes out every tick while snapshots
    // are priority-packed against a byte budget and can be deferred or
    // dropped, so the replica's pose is often older than the ack; adopting it
    // at the ack's tick would discard the motion in between and re-predict
    // it, tugging backward on every snapshot.
    // Before the first snapshot the pose is the spawn's, belonging to no tick
    // the predictor knows, so a zero snapshot tick skips reconciliation
    // through the guard below rather than anchoring it to the ack.
    final applied = client.lastAppliedInputTick;
    final carried = replica.snapshotTick;
    final acked = carried < applied ? carried : applied;
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

/// Reads [handles]' pose and velocities out of [simulation] into one flat
/// buffer, [floatsPerPredictedBody] floats each.
///
/// Flat rather than a list of objects because this runs every tick and is
/// retained sixty-odd times over: the point is to stop a retained tick costing
/// much, and a per-body object would put the allocation straight back.
Float32List capturePredictedBodies(
  PhysicsSimulation simulation,
  List<int> handles,
) {
  final out = Float32List(handles.length * floatsPerPredictedBody);
  for (var i = 0; i < handles.length; i++) {
    final handle = handles[i];
    final (position, rotation) = simulation.readBodyPose(handle);
    final linear = simulation.readBodyLinearVelocity(handle);
    final angular = simulation.readBodyAngularVelocity(handle);
    final base = i * floatsPerPredictedBody;
    out
      ..[base] = position.x
      ..[base + 1] = position.y
      ..[base + 2] = position.z
      ..[base + 3] = rotation.x
      ..[base + 4] = rotation.y
      ..[base + 5] = rotation.z
      ..[base + 6] = rotation.w
      ..[base + 7] = linear.x
      ..[base + 8] = linear.y
      ..[base + 9] = linear.z
      ..[base + 10] = angular.x
      ..[base + 11] = angular.y
      ..[base + 12] = angular.z;
  }
  return out;
}

/// Puts [state] back onto [handles] in [simulation].
///
/// Bodies outside [handles] are left where they are, which is the bargain the
/// declared set makes: what you leave out is not rewound.
void restorePredictedBodies(
  PhysicsSimulation simulation,
  List<int> handles,
  Float32List state,
) {
  // A set that changed between capture and restore would read past the buffer.
  // Restoring what both agree on and leaving the rest is a divergence the
  // correction cannot fix, so refuse rather than half-apply: better found here
  // than in a game.
  if (state.length != handles.length * floatsPerPredictedBody) {
    throw StateError(
      'the predicted body set changed between capture and restore '
      '(${state.length ~/ floatsPerPredictedBody} bodies retained, '
      '${handles.length} declared now). The set has to be fixed for the life '
      'of the prediction; allocate a pool up front the way '
      'PredictedPhysicsController.onWorldRestored describes.',
    );
  }
  for (var i = 0; i < handles.length; i++) {
    final handle = handles[i];
    final base = i * floatsPerPredictedBody;
    simulation
      ..setBodyPose(
        handle,
        Vector3(state[base], state[base + 1], state[base + 2]),
        Quaternion(
          state[base + 3],
          state[base + 4],
          state[base + 5],
          state[base + 6],
        ),
      )
      ..setBodyLinearVelocity(
        handle,
        Vector3(state[base + 7], state[base + 8], state[base + 9]),
      )
      ..setBodyAngularVelocity(
        handle,
        Vector3(state[base + 10], state[base + 11], state[base + 12]),
      );
  }
}
