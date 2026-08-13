import 'package:flutter_scene/fscene.dart';
import 'package:flutter_scene_fmod/src/fmod_audio.dart';

/// Registers this package's component codecs into [registry], letting
/// `.fscene`/`.fsceneb` documents carry FMOD Studio events.
///
/// Pass the augmented registry to the load or realize call:
///
/// ```dart
/// final registry = defaultComponentRegistry();
/// registerFmodComponentCodecs(registry);
/// await loadScene('assets/level.fsceneb', registry: registry);
/// ```
void registerFmodComponentCodecs(FsceneComponentRegistry registry) {
  registry.register(FmodEventCodec());
}

/// Registers the `fmod` audio backend, letting documents whose `audioEngine`
/// component names it realize an [FmodAudioEngine]. Call once at startup.
///
/// Recognized `config` keys are `maxChannels` (int), `liveUpdate` (bool),
/// and `pauseWhenBackgrounded` (bool).
void registerFmodAudioBackend() {
  registerAudioEngineBackend(
    'fmod',
    (config) => FmodAudioEngine(
      maxChannels: readInt(config, 'maxChannels', 256),
      liveUpdate: readBool(config, 'liveUpdate', false),
      pauseWhenBackgrounded: readBool(config, 'pauseWhenBackgrounded', true),
    ),
  );
}

/// Codec for [FmodEventSource] (`fmodEvent` components). Scenes using it
/// realize correctly only with this package's registry (see
/// [registerFmodComponentCodecs]); other apps skip the component.
class FmodEventCodec extends DeclarativeComponentCodec<FmodEventSource> {
  @override
  String get type => 'fmodEvent';

  @override
  List<ComponentField<FmodEventSource>> get fields => [
    ComponentField(
      const ComponentPropertyDef(
        'event',
        ComponentPropertyKind.string,
        defaultValue: StringValue(''),
        doc: 'The FMOD Studio event path (event:/...).',
        constraints: [TextPattern(r'^event:/.+')],
      ),
      read: (c, _) => StringValue(c.eventPath),
    ),
    ComponentField.boolean(
      'autoplay',
      defaultValue: false,
      doc: 'Start the event as soon as the source mounts.',
      get: (c) => c.autoplay,
      set: (c, v) => c.autoplay = v,
    ),
    ComponentField.number(
      'volume',
      defaultValue: 1.0,
      doc: 'Gain, 1.0 is unity.',
      constraints: const [Range.nonNegative(), SoftRange(0, 1)],
      get: (c) => c.volume,
      set: (c, v) => c.volume = v,
    ),
    ComponentField.number(
      'pitch',
      defaultValue: 1.0,
      doc: 'Playback rate multiplier.',
      constraints: const [Range.nonNegative(), SoftRange(0, 2)],
      get: (c) => c.pitch,
      set: (c, v) => c.pitch = v,
    ),
    ComponentField.boolean(
      'positional',
      defaultValue: true,
      doc: 'Spatialize at the node, or play flat when false.',
      get: (c) => c.positional,
      set: (c, v) => c.positional = v,
    ),
    ComponentField.boolean(
      'overrideDistances',
      defaultValue: false,
      doc:
          'Override the event\'s authored min/max distances with the '
          'attenuation settings.',
      get: (c) => c.overrideDistances,
      set: (c, v) => c.overrideDistances = v,
    ),
    ComponentField.number(
      'minDistance',
      defaultValue: 1.0,
      doc: 'Distance where attenuation begins (with overrideDistances).',
      constraints: const [Range.nonNegative()],
      get: (c) => c.attenuation.minDistance,
      set: (c, v) => c.attenuation.minDistance = v,
    ),
    ComponentField.number(
      'maxDistance',
      defaultValue: 500.0,
      doc:
          'Distance beyond which attenuation stops (with '
          'overrideDistances).',
      constraints: const [Range.nonNegative()],
      get: (c) => c.attenuation.maxDistance,
      set: (c, v) => c.attenuation.maxDistance = v,
    ),
    ComponentField(
      ComponentPropertyDef(
        'parameters',
        ComponentPropertyKind.map,
        defaultValue: MapValue(const {}),
        doc: 'Initial event parameter values by name.',
      ),
      read: (c, _) => MapValue({
        for (final entry in c.parameters.entries)
          entry.key: DoubleValue(entry.value),
      }),
      write: (c, v, _) {
        if (v is! MapValue) return;
        for (final entry in v.values.entries) {
          final value = entry.value;
          if (value is DoubleValue) {
            c.setParameter(entry.key, value.value);
          } else if (value is IntValue) {
            c.setParameter(entry.key, value.value.toDouble());
          }
        }
      },
    ),
  ];

  @override
  FmodEventSource create(PropertyReader props) {
    final parameters = props.value('parameters');
    return FmodEventSource(
      props.string('event'),
      parameters: {
        if (parameters is MapValue)
          for (final entry in parameters.values.entries)
            if (entry.value is DoubleValue)
              entry.key: (entry.value as DoubleValue).value
            else if (entry.value is IntValue)
              entry.key: (entry.value as IntValue).value.toDouble(),
      },
    );
  }
}
