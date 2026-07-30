/// Audio for flutter_scene, an optional pluggable-backend contract.
///
/// The spatial-audio scene-graph surface, [AudioEngine] (the contract a
/// backend implements), [AudioListener], [AudioSource] / [ClipAudioSource],
/// [AudioBus], [AudioClip], and the attenuation model. Attach a backend
/// engine, `SoloudAudioEngine` from `package:flutter_scene_soloud` or
/// `FmodAudioEngine` from `package:flutter_scene_fmod`. Import this only when
/// a build needs audio; the core `package:flutter_scene/scene.dart` does not
/// carry it.
library;

export 'src/audio/audio_attenuation.dart' show AudioAttenuation, AudioRolloff;
export 'src/audio/audio_bus.dart' show AudioBus;
export 'src/audio/audio_clip.dart' show AudioClip;
export 'src/audio/audio_engine.dart' show AudioEngine;
export 'src/audio/audio_listener.dart' show AudioListener;
export 'src/audio/audio_source.dart' show AudioSource;
export 'src/audio/audio_voice.dart' show AudioVoice;
export 'src/audio/clip_audio_source.dart' show ClipAudioSource;
