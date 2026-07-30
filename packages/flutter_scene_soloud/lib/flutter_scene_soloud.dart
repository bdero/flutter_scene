/// SoLoud audio backend for flutter_scene.
///
/// Attach a [SoloudAudioEngine] to the scene root; `ClipAudioSource`,
/// `AudioListener`, and the rest of the flutter_scene audio contract
/// then play through SoLoud.
library;

export 'src/soloud_audio.dart'
    show SoloudAudioBus, SoloudAudioClip, SoloudAudioEngine, SoloudAudioVoice;
