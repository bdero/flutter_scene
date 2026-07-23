/// A loaded, playable piece of audio owned by an `AudioEngine`.
///
/// Clips are backend-typed handles. Load them with
/// `AudioEngine.loadClip` and play them through an `AudioSource` or
/// `AudioEngine.playOneShot`. A clip may be played by any number of
/// sources at once.
/// {@category Audio}
abstract class AudioClip {
  /// The decoded length, or null when the backend cannot determine it
  /// (some streamed formats).
  Duration? get duration;

  /// Whether [dispose] has been called.
  bool get isDisposed;

  /// Releases the backend resources for this clip. Playing a disposed
  /// clip throws. Sources currently playing it are stopped.
  void dispose();
}
