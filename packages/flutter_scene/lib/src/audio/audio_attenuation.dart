/// Distance rolloff model for a positional sound.
/// {@category Audio}
enum AudioRolloff {
  /// No distance attenuation.
  none,

  /// Inverse-distance rolloff, the physical default.
  inverse,

  /// Linear fade between the min and max distances.
  linear,

  /// Exponential rolloff.
  exponential,
}

/// Spatialization parameters for a positional sound.
///
/// Backends re-apply these every frame, so fields may be mutated freely.
/// Event-style sources whose attenuation is authored externally treat
/// these as an override hint at most; see the backend's documentation.
/// {@category Audio}
class AudioAttenuation {
  AudioAttenuation({
    this.minDistance = 1.0,
    this.maxDistance = 500.0,
    this.rolloff = AudioRolloff.inverse,
    this.rolloffFactor = 1.0,
    this.dopplerFactor = 1.0,
  });

  /// Distance at which attenuation begins. Inside it the sound plays at
  /// full volume.
  double minDistance;

  /// Distance beyond which the sound no longer attenuates (or is
  /// silent, for [AudioRolloff.linear]).
  double maxDistance;

  /// The rolloff curve between [minDistance] and [maxDistance].
  AudioRolloff rolloff;

  /// Steepness multiplier for the rolloff curve. `1.0` is the model's
  /// natural curve.
  double rolloffFactor;

  /// Doppler strength for this sound. `0` disables doppler, `1.0` is
  /// physically correct.
  double dopplerFactor;
}
