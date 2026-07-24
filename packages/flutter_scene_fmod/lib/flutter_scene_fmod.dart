/// FMOD Studio audio backend for flutter_scene, over the `fmod`
/// bindings package.
///
/// Attach an [FmodAudioEngine] to the scene root. The flutter_scene
/// audio contract (`ClipAudioSource`, buses, one-shots) plays through
/// FMOD Core; [FmodEventSource] plays events authored in FMOD Studio.
/// Requires a user-supplied FMOD Engine SDK; see the README.
library;

export 'package:fmod/fmod.dart'
    show FmodBank, FmodException, FmodStudioBus, FmodStudioSystem;

export 'src/fmod_audio.dart'
    show
        FmodAudioBus,
        FmodAudioClip,
        FmodAudioEngine,
        FmodAudioVoice,
        FmodEventSource;
export 'src/fmod_event_codec.dart'
    show FmodEventCodec, registerFmodComponentCodecs;
