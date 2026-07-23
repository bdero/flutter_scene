import 'package:flutter/foundation.dart';
import 'package:flutter_scene/src/audio/audio_attenuation.dart';
import 'package:flutter_scene/src/audio/audio_bus.dart';
import 'package:flutter_scene/src/audio/audio_clip.dart';
import 'package:flutter_scene/src/audio/audio_source.dart';
import 'package:flutter_scene/src/audio/audio_voice.dart';
import 'package:vector_math/vector_math.dart';

/// Plays an [AudioClip] at a node, on any backend.
///
/// The clip comes from [clip] (loaded by the app) or [asset] (loaded by
/// the source itself on first mount). Each [play] starts a fresh
/// playback through a backend voice; [pause] and [play] resume
/// mid-clip, [stop] rewinds.
///
/// This is the source the scene-description format realizes for
/// `audioSource` components, so a serialized scene's sounds play on
/// whichever engine the app mounts.
/// {@category Audio}
class ClipAudioSource extends AudioSource {
  ClipAudioSource({
    AudioClip? clip,
    this.asset,
    this.autoplay = false,
    bool looping = false,
    double volume = 1.0,
    double pitch = 1.0,
    bool positional = true,
    AudioAttenuation? attenuation,
    this.bus,
    this.busName,
  }) : _clip = clip,
       _looping = looping,
       _volume = volume,
       _pitch = pitch {
    this.positional = positional;
    if (attenuation != null) this.attenuation = attenuation;
  }

  /// Asset key loaded on first mount when [clip] is not set directly.
  String? asset;

  /// Begin playing as soon as the source is mounted and loaded.
  bool autoplay;

  /// Explicit bus to route through. Takes precedence over [busName].
  AudioBus? bus;

  /// Name of an engine bus to route through, resolved at [play] time.
  /// Useful from serialized scenes, where bus objects cannot be
  /// referenced directly.
  String? busName;

  AudioClip? _clip;
  bool _ownsClip = false;

  /// The clip this source plays. Assigning while playing takes effect
  /// on the next [play].
  AudioClip? get clip => _clip;
  set clip(AudioClip? value) {
    if (_ownsClip) _clip?.dispose();
    _ownsClip = false;
    _clip = value;
  }

  AudioVoice? _voice;
  bool _pendingPlay = false;

  // Drops the voice reference once the backend reports the playback
  // finished, so a completed non-looping clip reads as stopped.
  AudioVoice? get _liveVoice {
    final voice = _voice;
    if (voice != null && !voice.isPlaying) _voice = null;
    return _voice;
  }

  @override
  Future<void> onLoad() async {
    final engine = this.engine;
    if (_clip == null && asset != null && engine != null) {
      _clip = await engine.loadClip(asset!);
      _ownsClip = true;
    }
    if ((autoplay || _pendingPlay) && isMounted) play();
  }

  @override
  void onMount() {
    super.onMount();
    // onLoad handles the first mount; later remounts restart here.
    if (isLoaded && autoplay) play();
  }

  @override
  void onUnmount() {
    _voice?.stop();
    _voice = null;
    _pendingPlay = false;
    super.onUnmount();
  }

  @override
  void onDetach() {
    if (_ownsClip) _clip?.dispose();
    _clip = null;
    _ownsClip = false;
  }

  @override
  void play() {
    final paused = _liveVoice;
    if (paused != null && paused.isPaused) {
      paused.resume();
      return;
    }
    final engine = this.engine;
    final clip = _clip;
    if (engine == null || clip == null) {
      // Not ready yet (asset still loading, or mounted without an
      // engine). Remember the intent; onLoad retries.
      _pendingPlay = true;
      return;
    }
    _pendingPlay = false;
    _voice?.stop();
    final voice = engine.createVoice(clip)
      ..volume = _volume
      ..pitch = _pitch
      ..looping = _looping
      ..setBus(bus ?? (busName != null ? engine.findBus(busName!) : null))
      ..setPositional(positional);
    if (positional && isMounted) {
      voice.update3d(
        node.globalTransform.getTranslation(),
        Vector3.zero(),
        attenuation,
      );
    }
    voice.start();
    _voice = voice;
  }

  @override
  void pause() => _liveVoice?.pause();

  @override
  void stop() {
    _pendingPlay = false;
    _voice?.stop();
    _voice = null;
  }

  @override
  bool get isPlaying {
    final voice = _liveVoice;
    return voice != null && !voice.isPaused;
  }

  double _volume;

  @override
  double get volume => _volume;

  @override
  set volume(double value) {
    _volume = value;
    _liveVoice?.volume = value;
  }

  double _pitch;

  @override
  double get pitch => _pitch;

  @override
  set pitch(double value) {
    _pitch = value;
    _liveVoice?.pitch = value;
  }

  bool _looping;

  /// Whether playback repeats until stopped.
  bool get looping => _looping;
  set looping(bool value) {
    _looping = value;
    _liveVoice?.looping = value;
  }

  @override
  @protected
  void onTransformSync(Vector3 position, Vector3 velocity) {
    _liveVoice?.update3d(position, velocity, attenuation);
  }
}
