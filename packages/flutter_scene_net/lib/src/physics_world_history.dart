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

  /// Runs [query] against the world as recorded at [tick], restoring the
  /// present before returning.
  ///
  /// `rewound` is false when [tick] is outside the retained window, which a
  /// null `result` alone cannot distinguish from a query that legitimately
  /// found nothing (no raycast hit against a peer too far behind to
  /// compensate, say).
  ///
  /// The present it restores is the newest recording, so apply world
  /// mutations after a tick's rewinds rather than between them, or [record]
  /// again first.
  ({bool rewound, T? result}) rewind<T>(
    int tick,
    T Function(PhysicsSimulation simulation) query,
  ) {
    final past = _snapshots[tick];
    final present = _snapshots[_newestTick];
    if (past == null || present == null) {
      return (rewound: false, result: null);
    }
    simulation.restore(past);
    try {
      return (rewound: true, result: query(simulation));
    } finally {
      simulation.restore(present);
    }
  }
}
