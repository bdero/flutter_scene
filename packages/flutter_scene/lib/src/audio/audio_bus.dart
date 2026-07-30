/// A named mix group owned by an `AudioEngine`.
///
/// Sources route into a bus (or the engine's master bus by default), and
/// bus volumes multiply down the chain, so a `music` bus can be faded
/// without touching individual sources. Create buses with
/// `AudioEngine.createBus`.
/// {@category Audio}
abstract class AudioBus {
  /// The name the bus was created with.
  String get name;

  /// The parent bus, or null for the master bus.
  AudioBus? get parent;

  /// Gain applied to everything routed through this bus, multiplied with
  /// ancestor bus volumes. `1.0` is unity gain.
  double get volume;
  set volume(double value);
}
