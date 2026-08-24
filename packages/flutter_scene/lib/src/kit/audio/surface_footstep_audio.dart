import 'dart:math' as math;
import 'package:flutter_scene/src/audio/audio_clip.dart';
import 'package:flutter_scene/src/audio/audio_engine.dart';
import 'package:flutter_scene/src/kit/audio/sound_manager.dart';
import 'package:vector_math/vector_math.dart' as vm;

/// Surface material classification for footstep and impact sound playback.
/// {@category Audio}
enum SurfaceMaterialType { stone, grass, wood, sand, water, metal, dirt }

/// Helper mapping surface material tags to audio clip banks.
/// {@category Audio}
class SurfaceFootstepAudio {
  final math.Random _rng = math.Random();
  final Map<SurfaceMaterialType, List<AudioClip>> _banks = {};

  /// Registers a list of audio clips for a specific surface type.
  void registerClips(SurfaceMaterialType type, List<AudioClip> clips) {
    _banks[type] = List.from(clips);
  }

  /// Plays a random footstep sound for [type] at world position [position].
  void playFootstep(
    AudioEngine engine,
    SurfaceMaterialType type, {
    vm.Vector3? position,
    double volume = 0.8,
  }) {
    final clips = _banks[type];
    if (clips == null || clips.isEmpty) return;

    final clip = clips[_rng.nextInt(clips.length)];
    SoundManager.playOneShot(
      engine,
      clip,
      position: position,
      volume: volume,
      pitchJitter: 0.08,
    );
  }
}
