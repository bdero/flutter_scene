import 'package:flutter/foundation.dart';
import 'package:scene/scene.dart';

import 'package:flutter_scene/src/audio/audio_attenuation.dart';
import 'package:flutter_scene/src/audio/audio_engine.dart';
import 'package:flutter_scene/src/audio/audio_listener.dart';
import 'package:flutter_scene/src/audio/clip_audio_source.dart';
import 'package:flutter_scene/src/components/component.dart';
import 'package:flutter_scene/src/fscene/realize/component_codec.dart';
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
  String? get category => 'Audio';

  @override
  ComponentSchema get schema => ComponentSchema(
    type,
    category: category,
    icon: 'audio',
    properties: propertySchema,
    gizmo: const GizmoSpec([
      GizmoIcon(),
      GizmoWireSphere(
        radius: GizmoScalar.bind('attenuation.minDistance'),
        visibility: GizmoVisibility.selected,
        when: GizmoCondition('positional', 'true'),
      ),
      GizmoWireSphere(
        radius: GizmoScalar.bind('attenuation.maxDistance'),
        visibility: GizmoVisibility.selected,
        color: GizmoColor(1, 1, 1, 0.3),
        when: GizmoCondition('positional', 'true'),
      ),
    ]),
  );

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
  String? get category => 'Audio';

  @override
  ComponentSchema get schema => ComponentSchema(
    type,
    category: category,
    icon: 'audio-listener',
    properties: propertySchema,
    gizmo: const GizmoSpec([GizmoIcon()]),
  );

  @override
  List<ComponentField<AudioListener>> get fields => const [];

  @override
  AudioListener create(PropertyReader props) => AudioListener();
}

// --- Audio engine backend registry ---

/// Creates a fresh [AudioEngine] for a realized `audioEngine` component.
/// [config] is the spec's open backend-specific configuration bag.
typedef AudioEngineBackendFactory =
    AudioEngine Function(Map<String, PropertyValue> config);

final Map<String, AudioEngineBackendFactory> _audioBackends = {};

/// Registers [factory] under backend [id], replacing any existing entry.
///
/// A document's `audioEngine` component names its backend by id; backend
/// packages register their factory at app startup
/// (`registerFmodAudioBackend()`) so documents authored against them realize.
/// flutter_scene itself ships no backend, so an app without one skips the
/// component.
/// {@category Audio}
void registerAudioEngineBackend(String id, AudioEngineBackendFactory factory) {
  _audioBackends[id] = factory;
}

/// The registered factory for backend [id], or null.
/// {@category Audio}
AudioEngineBackendFactory? audioEngineBackendFactory(String id) =>
    _audioBackends[id];

/// Codec for [AudioEngine] components. The `backend` id names the concrete
/// engine through the backend registry ([registerAudioEngineBackend]); an
/// unregistered backend skips the component so the scene still loads,
/// without audio. The open `config` bag passes through to the factory.
class AudioEngineCodec extends DeclarativeComponentCodec<AudioEngine> {
  @override
  String get type => 'audioEngine';

  @override
  String? get category => 'Audio';

  // The document backend id and construction config, stamped at realize so
  // serialize writes the registry key (not the engine's self-reported name)
  // and keeps the config the factory consumed. Hand-built engines fall back
  // to backendName and serialize without a config.
  static final Expando<String> _backendId = Expando('audio engine backend');
  static final Expando<Map<String, PropertyValue>> _config = Expando(
    'audio engine config',
  );

  @override
  List<ComponentField<AudioEngine>> get fields => [
    // No default; every audioEngine spec names its backend.
    ComponentField(
      const ComponentPropertyDef(
        'backend',
        ComponentPropertyKind.string,
        doc: 'Registered id of the audio backend this engine runs on.',
      ),
      read: (c, _) => StringValue(_backendId[c] ?? c.backendName),
    ),
    ComponentField.number(
      'masterVolume',
      defaultValue: 1.0,
      doc: 'Gain applied to all playback, 1.0 is unity.',
      constraints: const [Range(0, 1), SoftRange(0, 1)],
      get: (c) => c.masterVolume,
      set: (c, v) => c.masterVolume = v,
    ),
    // No default; absent means the backend's construction defaults.
    ComponentField(
      const ComponentPropertyDef(
        'config',
        ComponentPropertyKind.map,
        doc: 'Backend-specific construction options, passed to the factory.',
      ),
      read: (c, _) {
        final config = _config[c];
        return config == null || config.isEmpty ? null : MapValue({...config});
      },
    ),
  ];

  @override
  Component? realize(ComponentSpec spec, RealizeContext context) {
    final backend = spec.properties['backend'];
    final id = backend is StringValue ? backend.value : '';
    if (audioEngineBackendFactory(id) == null) {
      debugPrint(
        'fscene: audioEngine skipped (backend "$id" is not registered; '
        'call registerAudioEngineBackend at startup)',
      );
      return null;
    }
    return super.realize(spec, context);
  }

  @override
  AudioEngine create(PropertyReader props) {
    final id = props.string('backend');
    final config = switch (props.value('config')) {
      MapValue(:final values) => Map<String, PropertyValue>.of(values),
      _ => <String, PropertyValue>{},
    };
    final engine = audioEngineBackendFactory(id)!(config);
    _backendId[engine] = id;
    if (config.isNotEmpty) _config[engine] = config;
    return engine;
  }
}
