import 'package:scene/scene.dart';

import 'package:flutter_scene/src/audio/audio_attenuation.dart';
import 'package:flutter_scene/src/audio/audio_listener.dart';
import 'package:flutter_scene/src/audio/clip_audio_source.dart';
import 'package:flutter_scene/src/fscene/realize/component_schema.dart';
import 'package:flutter_scene/src/fscene/realize/declarative_codec.dart';

/// The nested attenuation object's field descriptors, shared by the schema
/// and the codec's read/write bindings.
const List<ComponentPropertyDef> _attenuationFields = [
  ComponentPropertyDef(
    'minDistance',
    ComponentPropertyKind.number,
    defaultValue: DoubleValue(1.0),
    doc: 'Distance where attenuation begins.',
    constraints: [Range.nonNegative()],
  ),
  ComponentPropertyDef(
    'maxDistance',
    ComponentPropertyKind.number,
    defaultValue: DoubleValue(500.0),
    doc: 'Distance beyond which attenuation stops.',
    constraints: [Range.nonNegative()],
  ),
  ComponentPropertyDef(
    'rolloff',
    ComponentPropertyKind.string,
    defaultValue: StringValue('inverse'),
    doc: 'Distance rolloff model.',
    options: ['none', 'inverse', 'linear', 'exponential'],
  ),
  ComponentPropertyDef(
    'rolloffFactor',
    ComponentPropertyKind.number,
    defaultValue: DoubleValue(1.0),
    doc: 'Steepness multiplier for the rolloff curve.',
    constraints: [Range.nonNegative()],
  ),
  ComponentPropertyDef(
    'dopplerFactor',
    ComponentPropertyKind.number,
    defaultValue: DoubleValue(1.0),
    doc: 'Doppler strength, 0 disables.',
    constraints: [Range.nonNegative()],
  ),
];

/// Reads an [AudioAttenuation] from a spec's properties, accepting the nested
/// `attenuation` object and the older five flattened sibling keys.
AudioAttenuation attenuationFromProperties(Map<String, PropertyValue> p) {
  final nested = p['attenuation'];
  final values = nested is MapValue ? nested.values : p;
  double number(String key, double fallback) => switch (values[key]) {
    DoubleValue(:final value) => value,
    IntValue(:final value) => value.toDouble(),
    _ => fallback,
  };
  final rolloff = values['rolloff'];
  return AudioAttenuation(
    minDistance: number('minDistance', 1.0),
    maxDistance: number('maxDistance', 500.0),
    rolloff: rolloff is StringValue
        ? AudioRolloff.values.asNameMap()[rolloff.value] ?? AudioRolloff.inverse
        : AudioRolloff.inverse,
    rolloffFactor: number('rolloffFactor', 1.0),
    dopplerFactor: number('dopplerFactor', 1.0),
  );
}

MapValue _encodeAttenuation(AudioAttenuation attenuation) => MapValue({
  'minDistance': DoubleValue(attenuation.minDistance),
  'maxDistance': DoubleValue(attenuation.maxDistance),
  'rolloff': StringValue(attenuation.rolloff.name),
  'rolloffFactor': DoubleValue(attenuation.rolloffFactor),
  'dopplerFactor': DoubleValue(attenuation.dopplerFactor),
});

final MapValue _defaultAttenuation = _encodeAttenuation(AudioAttenuation());

/// Codec for [ClipAudioSource]. The clip is carried as an asset key;
/// playback needs an `AudioEngine` mounted by the app, and a scene realized
/// without one keeps the component inert.
// TODO(audio): support embedding clip payloads as document resources
// (an audio ResourceSpec mirroring textures) so a .fsceneb is
// self-contained without a matching asset bundle.
class AudioSourceCodec extends DeclarativeComponentCodec<ClipAudioSource> {
  @override
  String get type => 'audioSource';

  @override
  List<ComponentField<ClipAudioSource>> get fields => [
    ComponentField(
      const ComponentPropertyDef(
        'asset',
        ComponentPropertyKind.assetRef,
        doc: 'Asset key of the audio file this source plays.',
        constraints: [
          AssetExtensions(['.wav', '.mp3', '.ogg', '.flac']),
        ],
      ),
      read: (c, _) {
        final asset = c.asset;
        // Older documents carried '' for "unset"; absent is the delta form.
        return asset == null || asset.isEmpty ? null : StringValue(asset);
      },
      write: (c, v, _) {
        if (v is StringValue) c.asset = v.value.isEmpty ? null : v.value;
      },
    ),
    ComponentField.boolean(
      'autoplay',
      defaultValue: false,
      doc: 'Begin playing as soon as the source mounts.',
      get: (c) => c.autoplay,
      set: (c, v) => c.autoplay = v,
    ),
    ComponentField.boolean(
      'looping',
      defaultValue: false,
      doc: 'Repeat until stopped.',
      get: (c) => c.looping,
      set: (c, v) => c.looping = v,
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
    ComponentField(
      ComponentPropertyDef(
        'attenuation',
        ComponentPropertyKind.object,
        defaultValue: _defaultAttenuation,
        doc: 'Distance attenuation for positional playback.',
        objectFields: _attenuationFields,
      ),
      read: (c, _) => _encodeAttenuation(c.attenuation),
      write: (c, v, _) {
        if (v is MapValue) {
          c.attenuation = attenuationFromProperties({'attenuation': v});
        }
      },
    ),
    ComponentField(
      const ComponentPropertyDef(
        'bus',
        ComponentPropertyKind.string,
        doc: 'Name of the engine bus to route through.',
      ),
      read: (c, _) {
        final bus = c.busName;
        return bus == null || bus.isEmpty ? null : StringValue(bus);
      },
      write: (c, v, _) {
        if (v is StringValue) c.busName = v.value.isEmpty ? null : v.value;
      },
    ),
  ];

  @override
  ClipAudioSource create(PropertyReader props) {
    final asset = props.string('asset');
    final bus = props.string('bus');
    return ClipAudioSource(
      asset: asset.isEmpty ? null : asset,
      // Accepts the nested object and the legacy flattened sibling keys.
      attenuation: attenuationFromProperties(props.properties),
      busName: bus.isEmpty ? null : bus,
    );
  }
}

/// Codec for [AudioListener]. No properties; the node transform is the
/// listener pose.
class AudioListenerCodec extends DeclarativeComponentCodec<AudioListener> {
  @override
  String get type => 'audioListener';

  @override
  List<ComponentField<AudioListener>> get fields => const [];

  @override
  AudioListener create(PropertyReader props) => AudioListener();
}
