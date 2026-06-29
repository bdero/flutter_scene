/// A one-off (or repeating) burst of particles scheduled at a point in the
/// emitter's run.
///
/// At system time [time] the spawner emits [count] particles at once. With a
/// positive [interval] the burst repeats every [interval] seconds (the first at
/// [time]) for [cycles] occurrences, or forever when [cycles] is null; a
/// non-positive [interval] is a single shot. Burst times are absolute on the
/// system clock.
class ParticleBurst {
  /// Creates a burst of [count] particles at [time], optionally repeating.
  const ParticleBurst({
    required this.time,
    required this.count,
    this.interval = 0.0,
    this.cycles,
  }) : assert(time >= 0),
       assert(count >= 0),
       assert(cycles == null || cycles >= 1);

  /// The system time (seconds) of the first occurrence.
  final double time;

  /// How many particles each occurrence emits.
  final int count;

  /// Seconds between occurrences; non-positive means a single shot.
  final double interval;

  /// The number of occurrences when repeating, or null to repeat forever (only
  /// meaningful when [interval] is positive).
  final int? cycles;
}

/// Decides how many particles to emit on each simulation step from a steady
/// [rate] plus any [bursts].
///
/// The rate is accumulated fractionally across steps (so a rate that emits less
/// than one particle per step still emits on the right cadence rather than
/// truncating to zero), and bursts fire when their scheduled time falls in the
/// step's half-open time window.
class Spawner {
  /// Creates a spawner emitting [rate] particles per second plus [bursts].
  Spawner({this.rate = 0.0, List<ParticleBurst> bursts = const []})
    : assert(rate >= 0),
      bursts = List<ParticleBurst>.unmodifiable(bursts);

  /// Steady emission rate in particles per second.
  double rate;

  /// Scheduled bursts, fired by system time.
  final List<ParticleBurst> bursts;

  double _accumulator = 0.0;

  /// Returns the number of particles to emit over a step of length [dt] that
  /// starts at system time [time].
  int emit(double dt, double time) {
    var count = 0;
    if (rate > 0.0) {
      _accumulator += rate * dt;
      final whole = _accumulator.floor();
      _accumulator -= whole;
      count += whole;
    }
    if (bursts.isNotEmpty) {
      final end = time + dt;
      for (final burst in bursts) {
        if (burst.interval > 0.0) {
          // Occurrence k is at burst.time + k * interval; count those in the
          // half-open window [time, end) directly rather than iterating cycles.
          final inverse = 1.0 / burst.interval;
          var first = ((time - burst.time) * inverse).ceil();
          if (first < 0) first = 0;
          var last = ((end - burst.time) * inverse).ceil() - 1;
          final cycles = burst.cycles;
          if (cycles != null && last > cycles - 1) last = cycles - 1;
          if (last >= first) count += (last - first + 1) * burst.count;
        } else if (burst.time >= time && burst.time < end) {
          count += burst.count;
        }
      }
    }
    return count;
  }

  /// Clears the fractional rate accumulator (used when restarting a system).
  void reset() {
    _accumulator = 0.0;
  }
}
