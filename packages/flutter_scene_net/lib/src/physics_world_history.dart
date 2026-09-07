import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_scene/physics.dart';

import 'predicted_physics.dart';

/// Server-side per-tick world snapshot ring for lag-compensated rewind.
///
/// Record once per authoritative tick after stepping. [rewind] restores the
/// retained world at the client-rendered tick, runs a query against it (a
/// raycast for hit registration, say), then restores the present before
/// returning. Retention doubles as the rewind cap, [maxRewindTicks] bounds
/// how far back a high-latency peer can drag everyone else.
///
/// A tick is a coarse unit for this. A client renders between two server
/// ticks, so rewinding to the nearer one puts a target up to half a tick away
/// from where the shooter saw it -- at 30Hz and a running speed that is most
/// of a body width. [rewindBetween] closes that by restoring the earlier tick
/// and nudging the [tracked] bodies toward the later one, which needs to know
/// which bodies matter: everything else stays on the whole tick, and for
/// static geometry that is exactly right.
final class PhysicsWorldHistory {
  PhysicsWorldHistory(
    this.simulation, {
    this.maxRewindTicks = 8,
    List<int> tracked = const [],
  }) : tracked = List.unmodifiable(tracked);

  final PhysicsSimulation simulation;

  /// The bodies [rewindBetween] interpolates.
  ///
  /// The ones a hit test is about: players, vehicles, anything that moves fast
  /// enough that half a tick of error changes the answer. Leaving a body out
  /// is not a mistake -- static geometry is in the same place at both ends of
  /// the interval, so interpolating it would be arithmetic with no effect.
  final List<int> tracked;

  /// Oldest rewindable age, in ticks behind the newest recording.
  final int maxRewindTicks;

  final Map<int, Uint8List> _snapshots = {};

  /// The tracked bodies' poses per tick, so an interpolated rewind does not
  /// have to restore a second world to read the far end of the interval.
  final Map<int, Float32List> _poses = {};

  int _newestTick = -1;

  /// Ticks currently rewindable.
  int get depth => _snapshots.length;

  /// Snapshots the present world as [tick].
  void record(int tick) {
    _snapshots[tick] = simulation.snapshot();
    if (tracked.isNotEmpty) {
      _poses[tick] = capturePredictedBodies(simulation, tracked);
    }
    _newestTick = tick;
    _snapshots.removeWhere((t, _) => _newestTick - t > maxRewindTicks);
    _poses.removeWhere((t, _) => _newestTick - t > maxRewindTicks);
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

  /// Runs [query] against the world [fraction] of the way from [tick] to the
  /// tick after it, restoring the present before returning.
  ///
  /// The world is the earlier tick's; only [tracked] bodies are moved toward
  /// where they were on the later one. That is the trade lag compensation
  /// makes everywhere: the shooter's view of the targets is reconstructed
  /// exactly, and the rest of the world is reconstructed to the tick.
  ///
  /// `rewound` is false when either end of the interval is outside the
  /// retained window, or when nothing is tracked -- there is nothing to
  /// interpolate then, and silently answering as though there were would hide
  /// that the caller never named the bodies it cares about.
  ({bool rewound, T? result}) rewindBetween<T>(
    int tick,
    double fraction,
    T Function(PhysicsSimulation simulation) query,
  ) {
    if (tracked.isEmpty) return (rewound: false, result: null);
    final from = _poses[tick];
    final to = _poses[tick + 1];
    // Landing exactly on a tick is the ordinary rewind, and asking for it
    // through this door should not fail just because the tick after it has
    // not happened yet.
    if (from != null && to == null && fraction <= 0) {
      return rewind(tick, query);
    }
    if (from == null || to == null) return (rewound: false, result: null);

    return rewind(tick, (sim) {
      restorePredictedBodies(
        sim,
        tracked,
        _lerpBodies(from, to, fraction.clamp(0.0, 1.0)),
      );
      return query(sim);
    });
  }

  /// Blends two retained pose buffers.
  ///
  /// Positions and velocities interpolate componentwise; rotations take the
  /// short arc, because two orientations either side of half a turn would
  /// otherwise blend through the long way and put a target facing backwards
  /// at the moment it is being shot at.
  static Float32List _lerpBodies(Float32List a, Float32List b, double t) {
    final out = Float32List(a.length);
    for (var base = 0; base < a.length; base += floatsPerPredictedBody) {
      for (final i in const [0, 1, 2, 7, 8, 9, 10, 11, 12]) {
        out[base + i] = a[base + i] + (b[base + i] - a[base + i]) * t;
      }
      var dot = 0.0;
      for (var i = 3; i <= 6; i++) {
        dot += a[base + i] * b[base + i];
      }
      final sign = dot < 0 ? -1.0 : 1.0;
      var length = 0.0;
      for (var i = 3; i <= 6; i++) {
        final value = a[base + i] + (b[base + i] * sign - a[base + i]) * t;
        out[base + i] = value;
        length += value * value;
      }
      // Normalized rather than slerped: over one tick the two orientations
      // are close, where the two agree to well under a degree, and this costs
      // a square root instead of two trig calls per body per shot.
      if (length > 1e-12) {
        final scale = 1 / sqrt(length);
        for (var i = 3; i <= 6; i++) {
          out[base + i] *= scale;
        }
      }
    }
    return out;
  }

  /// The tick a peer was looking at, from the newest snapshot it has
  /// acknowledged and the delay its client renders behind that.
  ///
  /// The anchor lag compensation needs, and the thing servers most often get
  /// wrong: the newest tick a client has *received* is not the tick it was
  /// *showing*. A client interpolates a fixed delay behind what it holds, so
  /// compensating to the acked tick alone rewinds too little and still favours
  /// the shooter.
  ///
  /// [renderDelay] is that client's interpolation delay -- the same number its
  /// [NetworkTransformComponent] is configured with. Returns a whole tick and
  /// the fraction past it, for [rewindBetween].
  ///
  /// Answers null when the peer has acknowledged nothing, which is a client
  /// that has connected but not yet been sent a snapshot: there is no view to
  /// reconstruct, so a hit test should fall back rather than compensate to a
  /// guess.
  static ({int tick, double fraction})? renderedAt({
    required int ackedTick,
    required Duration renderDelay,
    required int tickRate,
  }) {
    if (ackedTick < 0 || tickRate <= 0) return null;
    final ticksBehind =
        renderDelay.inMicroseconds * tickRate / Duration.microsecondsPerSecond;
    final exact = ackedTick - ticksBehind;
    // Before the session had run long enough to be that far behind, the
    // oldest thing there is to rewind to is the beginning.
    if (exact <= 0) return (tick: 0, fraction: 0);
    final tick = exact.floor();
    return (tick: tick, fraction: exact - tick);
  }
}
