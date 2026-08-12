import 'package:flutter_scene/fscene.dart';
import 'package:flutter_scene_soloud/src/soloud_audio.dart';

/// Registers the `soloud` audio backend, letting documents whose
/// `audioEngine` component names it realize a [SoloudAudioEngine]. Call once
/// at startup.
///
/// Recognized `config` keys are `maxActiveVoices` (int) and
/// `pauseWhenBackgrounded` (bool).
void registerSoloudAudioBackend() {
  registerAudioEngineBackend(
    'soloud',
    (config) => SoloudAudioEngine(
      maxActiveVoices: switch (config['maxActiveVoices']) {
        IntValue(:final value) => value,
        DoubleValue(:final value) => value.round(),
        _ => 32,
      },
      pauseWhenBackgrounded: switch (config['pauseWhenBackgrounded']) {
        BoolValue(:final value) => value,
        _ => true,
      },
    ),
  );
}
