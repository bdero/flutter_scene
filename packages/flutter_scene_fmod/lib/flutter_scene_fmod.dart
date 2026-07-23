/// FMOD Studio audio backend for flutter_scene.
///
/// Attach an [FmodAudioEngine] to the scene root. The flutter_scene
/// audio contract (`ClipAudioSource`, buses, one-shots) plays through
/// FMOD Core; [FmodEventSource] plays events authored in FMOD Studio.
/// Requires a user-supplied FMOD Engine SDK; see the README.
library;

export 'src/ffi/fmod_bindings.dart' show FmodException;
export 'src/fmod_audio.dart'
    show
        FmodAudioBus,
        FmodAudioClip,
        FmodAudioEngine,
        FmodAudioVoice,
        FmodBank,
        FmodEventSource,
        FmodStudioBus;
export 'src/fmod_event_codec.dart'
    show FmodEventCodec, registerFmodComponentCodecs;
