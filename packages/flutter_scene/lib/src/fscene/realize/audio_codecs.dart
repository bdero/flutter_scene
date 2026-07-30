import 'package:flutter_scene/src/audio/audio_attenuation.dart';
import 'package:flutter_scene/src/audio/audio_listener.dart';
import 'package:flutter_scene/src/audio/clip_audio_source.dart';
import 'package:flutter_scene/src/components/component.dart';
import 'package:scene/scene.dart';
import 'package:flutter_scene/src/fscene/realize/component_codec.dart';
import 'package:flutter_scene/src/fscene/realize/component_schema.dart';
import 'package:flutter_scene/src/fscene/realize/property_read.dart';

/// Codec for [ClipAudioSource]. The clip is carried as a Flutter asset
/// key; playback needs an `AudioEngine` mounted by the app, and a scene
/// realized without one keeps the component inert.
// TODO(audio): support embedding clip payloads as document resources
// (an audio ResourceSpec mirroring textures) so a .fsceneb is
// self-contained without a matching asset bundle.
class AudioSourceCodec extends ComponentCodec {
  @override
  String get type => 'audioSource';

  // Empty strings stand in for "unset" on the asset and bus, since the
  // derived serialize requires a value for every declared property.
  static final List<ComponentPropertyDef> _schema = [
    ComponentPropertyDef(
      'asset',
      ComponentPropertyKind.string,
      const StringValue(''),
      doc: 'Asset key of the audio file this source plays.',
      read: (c) => StringValue((c as ClipAudioSource).asset ?? ''),
    ),
    ComponentPropertyDef(
      'autoplay',
      ComponentPropertyKind.boolean,
      const BoolValue(false),
      doc: 'Begin playing as soon as the source mounts.',
      read: (c) => BoolValue((c as ClipAudioSource).autoplay),
    ),
    ComponentPropertyDef(
      'looping',
      ComponentPropertyKind.boolean,
      const BoolValue(false),
      doc: 'Repeat until stopped.',
      read: (c) => BoolValue((c as ClipAudioSource).looping),
    ),
    ComponentPropertyDef(
      'volume',
      ComponentPropertyKind.number,
      const DoubleValue(1.0),
      doc: 'Gain, 1.0 is unity.',
      min: 0,
      read: (c) => DoubleValue((c as ClipAudioSource).volume),
    ),
    ComponentPropertyDef(
      'pitch',
      ComponentPropertyKind.number,
      const DoubleValue(1.0),
      doc: 'Playback rate multiplier.',
      min: 0,
      read: (c) => DoubleValue((c as ClipAudioSource).pitch),
    ),
    ComponentPropertyDef(
      'positional',
      ComponentPropertyKind.boolean,
      const BoolValue(true),
      doc: 'Spatialize at the node, or play flat when false.',
      read: (c) => BoolValue((c as ClipAudioSource).positional),
    ),
    ComponentPropertyDef(
      'minDistance',
      ComponentPropertyKind.number,
      const DoubleValue(1.0),
      doc: 'Distance where attenuation begins.',
      min: 0,
      read: (c) => DoubleValue((c as ClipAudioSource).attenuation.minDistance),
    ),
    ComponentPropertyDef(
      'maxDistance',
      ComponentPropertyKind.number,
      const DoubleValue(500.0),
      doc: 'Distance beyond which attenuation stops.',
      min: 0,
      read: (c) => DoubleValue((c as ClipAudioSource).attenuation.maxDistance),
    ),
    ComponentPropertyDef(
      'rolloff',
      ComponentPropertyKind.string,
      const StringValue('inverse'),
      doc: 'Distance rolloff model.',
      options: const ['none', 'inverse', 'linear', 'exponential'],
      read: (c) => StringValue((c as ClipAudioSource).attenuation.rolloff.name),
    ),
    ComponentPropertyDef(
      'rolloffFactor',
      ComponentPropertyKind.number,
      const DoubleValue(1.0),
      doc: 'Steepness multiplier for the rolloff curve.',
      min: 0,
      read: (c) =>
          DoubleValue((c as ClipAudioSource).attenuation.rolloffFactor),
    ),
    ComponentPropertyDef(
      'dopplerFactor',
      ComponentPropertyKind.number,
      const DoubleValue(1.0),
      doc: 'Doppler strength, 0 disables.',
      min: 0,
      read: (c) =>
          DoubleValue((c as ClipAudioSource).attenuation.dopplerFactor),
    ),
    ComponentPropertyDef(
      'bus',
      ComponentPropertyKind.string,
      const StringValue(''),
      doc: 'Name of the engine bus to route through.',
      read: (c) => StringValue((c as ClipAudioSource).busName ?? ''),
    ),
  ];

  @override
  List<ComponentPropertyDef> get propertySchema => _schema;

  @override
  bool claims(Component component) => component is ClipAudioSource;

  @override
  Component realize(ComponentSpec spec, RealizeContext context) {
    final p = spec.properties;
    final asset = readString(p, 'asset', stringDefault('asset'));
    final bus = readString(p, 'bus', stringDefault('bus'));
    return ClipAudioSource(
      asset: asset.isEmpty ? null : asset,
      autoplay: readBool(p, 'autoplay', boolDefault('autoplay')),
      looping: readBool(p, 'looping', boolDefault('looping')),
      volume: readDouble(p, 'volume', numberDefault('volume')),
      pitch: readDouble(p, 'pitch', numberDefault('pitch')),
      positional: readBool(p, 'positional', boolDefault('positional')),
      attenuation: AudioAttenuation(
        minDistance: readDouble(p, 'minDistance', numberDefault('minDistance')),
        maxDistance: readDouble(p, 'maxDistance', numberDefault('maxDistance')),
        rolloff:
            AudioRolloff.values.asNameMap()[readString(
              p,
              'rolloff',
              stringDefault('rolloff'),
            )] ??
            AudioRolloff.inverse,
        rolloffFactor: readDouble(
          p,
          'rolloffFactor',
          numberDefault('rolloffFactor'),
        ),
        dopplerFactor: readDouble(
          p,
          'dopplerFactor',
          numberDefault('dopplerFactor'),
        ),
      ),
      busName: bus.isEmpty ? null : bus,
    );
  }
}

/// Codec for [AudioListener]. No properties; the node transform is the
/// listener pose.
class AudioListenerCodec extends ComponentCodec {
  @override
  String get type => 'audioListener';

  @override
  bool claims(Component component) => component is AudioListener;

  @override
  Component realize(ComponentSpec spec, RealizeContext context) =>
      AudioListener();
}
