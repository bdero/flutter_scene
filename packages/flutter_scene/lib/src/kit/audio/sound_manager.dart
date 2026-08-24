import 'dart:math' as math;
import 'package:flutter_scene/src/audio/audio_bus.dart';
import 'package:flutter_scene/src/audio/audio_clip.dart';
import 'package:flutter_scene/src/audio/audio_engine.dart';
import 'package:flutter_scene/src/audio/audio_voice.dart';
import 'package:vector_math/vector_math.dart' as vm;

/// High-level audio utility with automatic voice pooling, pitch jitter, and spatial one-shots.
/// {@category Audio}
class SoundManager {
  static final math.Random _rng = math.Random(1337);

  /// Plays an audio clip once with pitch jitter and optional 3D positioning.
  static AudioVoice playOneShot(
    AudioEngine engine,
    AudioClip clip, {
    vm.Vector3? position,
    double volume = 1.0,
    double pitchJitter = 0.05,
    AudioBus? bus,
  }) {
    var pitch = 1.0;
    if (pitchJitter > 0.0) {
      pitch = 1.0 + (_rng.nextDouble() * 2.0 - 1.0) * pitchJitter;
      pitch = pitch.clamp(0.5, 2.0);
    }

    return engine.playOneShot(
      clip,
      position: position,
      volume: volume.clamp(0.0, 1.0),
      pitch: pitch,
      bus: bus,
    );
  }
}
