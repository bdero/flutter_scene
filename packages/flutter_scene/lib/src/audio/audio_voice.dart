import 'package:flutter_scene/src/audio/audio_attenuation.dart';
import 'package:flutter_scene/src/audio/audio_bus.dart';
import 'package:vector_math/vector_math.dart';

/// One playback of an `AudioClip`, created by `AudioEngine.createVoice`.
///
/// A voice is single-use. It is created paused so the caller can
/// configure volume, routing, and 3D state without an audible pop, then
/// begins with [start]. Once stopped (or finished naturally, for
/// non-looping clips) it cannot be restarted; create a new voice
/// instead. Backends release finished voices themselves, and every
/// operation on a finished voice is a safe no-op.
///
/// Most code never touches voices directly. `ClipAudioSource` manages
/// one per playback, and `AudioEngine.playOneShot` returns one for
/// fire-and-forget control.
/// {@category Audio}
abstract class AudioVoice {
  /// Whether the voice is still live (audible or paused). `false` once
  /// stopped or finished.
  bool get isPlaying;

  /// Whether playback is currently paused (including the initial
  /// pre-[start] pause).
  bool get isPaused;

  /// Begins playback. Calling it again after the voice started is a
  /// no-op.
  void start();

  void pause();

  void resume();

  /// Ends this playback permanently.
  void stop();

  /// Gain for this voice. `1.0` is unity. Multiplied with the routed
  /// bus chain.
  double get volume;
  set volume(double value);

  /// Playback rate multiplier. `1.0` is the clip's natural rate.
  double get pitch;
  set pitch(double value);

  /// Whether the clip repeats until stopped.
  set looping(bool value);

  /// Routes this voice through [bus], or the master bus when null.
  /// Must be set before [start]; rerouting a started voice is
  /// backend-dependent.
  void setBus(AudioBus? bus);

  /// Selects 3D or 2D playback. Must be set before [start].
  void setPositional(bool positional);

  /// Pushes this frame's 3D state. Called every frame for positional
  /// voices while the owning source is mounted.
  void update3d(
    Vector3 position,
    Vector3 velocity,
    AudioAttenuation attenuation,
  );
}
