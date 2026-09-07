/// Network time: the tick both ends count in.
///
/// A networked game does not run on wall-clock time, it runs on ticks. The
/// authority simulates one step per tick and stamps what it sends; a client
/// applies what it receives against the tick it was stamped with. Everything
/// that has to agree across machines — when a shot was fired, which snapshot a
/// prediction is reconciling against — is expressed in ticks, because two
/// machines can agree on a tick number and cannot agree on a clock.
///
/// Two times, and the gap between them is the point. **Local time** is where
/// this machine's simulation has got to. **Server time** is where the
/// authority had got to when the last thing you heard from it was sent, which
/// on a client is always slightly in the past. Rendering a remote object at
/// local time shows it somewhere it has not been told to be yet; rendering it
/// at server time is what interpolation is for.
library;

/// A point in a session's time, counted in ticks.
class NetworkTime {
  const NetworkTime({required this.tick, required this.tickRate})
    : assert(tickRate > 0, 'A session ticks at a positive rate.');

  /// The tick number.
  final int tick;

  /// Ticks per second.
  final int tickRate;

  /// Seconds one tick covers.
  double get fixedDelta => 1 / tickRate;

  /// Seconds since the session started, as of this tick.
  ///
  /// Derived rather than measured, so it is the same number on every machine
  /// that has reached this tick. A measured clock would not be.
  double get seconds => tick / tickRate;

  /// This time [ticks] later.
  NetworkTime operator +(int ticks) =>
      NetworkTime(tick: tick + ticks, tickRate: tickRate);

  /// How far ahead of [other] this is, in ticks.
  ///
  /// Signed, and negative is the normal case when comparing a client's view of
  /// server time against its own: the authority's last word is always a little
  /// behind where the client has simulated to.
  int ticksAhead(NetworkTime other) => tick - other.tick;

  /// How far ahead of [other] this is, in seconds.
  double secondsAhead(NetworkTime other) => ticksAhead(other) / tickRate;

  @override
  String toString() => 'NetworkTime(tick: $tick, ${seconds}s @${tickRate}Hz)';

  @override
  bool operator ==(Object other) =>
      other is NetworkTime && other.tick == tick && other.tickRate == tickRate;

  @override
  int get hashCode => Object.hash(tick, tickRate);
}

/// The two clocks a session runs on, and the lag between them.
class NetworkClock {
  NetworkClock({required this.tickRate})
    : assert(tickRate > 0, 'A session ticks at a positive rate.');

  /// Ticks per second, fixed for the session.
  ///
  /// Fixed because it is part of what the two ends agreed on: a client
  /// counting at a different rate would be reading every stamp wrong.
  final int tickRate;

  int _localTick = 0;
  int _serverTick = 0;

  /// Where this machine's simulation has got to.
  NetworkTime get local => NetworkTime(tick: _localTick, tickRate: tickRate);

  /// Where the authority had got to when it last spoke.
  NetworkTime get server => NetworkTime(tick: _serverTick, tickRate: tickRate);

  /// How far behind the authority's last word is, in seconds.
  ///
  /// Roughly half the round trip plus the send interval, and the number to
  /// look at when a game feels laggy — it is what a remote object is rendered
  /// behind by.
  double get lag => local.secondsAhead(server);

  /// Advances the local simulation by one tick.
  void advance() => _localTick++;

  /// Records the tick the authority stamped on something it sent.
  ///
  /// Never goes backwards: snapshots ride an unreliable channel, so an older
  /// one can arrive after a newer one, and letting it rewind the clock would
  /// make everything derived from it jump.
  void observeServerTick(int tick) {
    if (tick > _serverTick) _serverTick = tick;
    // A client that has fallen behind what the server has already sent is
    // behind, not ahead; carrying a local tick lower than the server's would
    // make lag read as negative.
    if (tick > _localTick) _localTick = tick;
  }

  /// Puts both clocks at [tick], for a client joining a session in progress.
  void resetTo(int tick) {
    _localTick = tick;
    _serverTick = tick;
  }
}
