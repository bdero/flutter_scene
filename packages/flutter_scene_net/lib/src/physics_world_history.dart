import 'dart:typed_data';

import 'package:flutter_scene/physics.dart';

/// Server-side per-tick world snapshot ring for lag-compensated rewind.
///
/// Record once per authoritative tick after stepping. [rewind] restores the
/// retained world at the client-rendered tick, runs a query against it (a
/// raycast for hit registration, say), then restores the present before
/// returning. Retention doubles as the rewind cap, [maxRewindTicks] bounds
/// how far back a high-latency peer can drag everyone else.
///
/// For fractional-tick precision on individual poses, pair this with the
/// interpolating `LagCompensation` history from `dashwire_replication`.
/// TODO(lagcomp): fractional world rewind by nudging tracked bodies between
/// the two bracketing snapshots via `PhysicsSimulation.setBodyPose`.
final class PhysicsWorldHistory {
  PhysicsWorldHistory(this.simulation, {this.maxRewindTicks = 8});

  final PhysicsSimulation simulation;

  /// Oldest rewindable age, in ticks behind the newest recording.
  final int maxRewindTicks;

  final Map<int, Uint8List> _snapshots = {};
  int _newestTick = -1;

  /// Ticks currently rewindable.
  int get depth => _snapshots.length;

  /// Snapshots the present world as [tick].
  void record(int tick) {
    _snapshots[tick] = simulation.snapshot();
    _newestTick = tick;
    _snapshots.removeWhere((t, _) => _newestTick - t > maxRewindTicks);
  }

  /// Runs [query] against the world as recorded at [tick] and returns its
  /// result, or null when [tick] is outside the retained window. The present
  /// world is restored before returning.
  T? rewind<T>(int tick, T Function(PhysicsSimulation simulation) query) {
    final past = _snapshots[tick];
    if (past == null) return null;
    final present = simulation.snapshot();
    simulation.restore(past);
    try {
      return query(simulation);
    } finally {
      simulation.restore(present);
    }
  }
}
