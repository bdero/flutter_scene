import 'package:flutter_scene/fscene.dart';
import 'package:flutter_scene/scene.dart';
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

/// Codec for [FmodEventSource] (`fmodEvent` components). Scenes using it
/// realize correctly only with this package's registry (see
/// [registerFmodComponentCodecs]); other apps skip the component.
class FmodEventCodec extends ComponentCodec {
  @override
  String get type => 'fmodEvent';

  static final List<ComponentPropertyDef> _schema = [
    ComponentPropertyDef(
      'event',
      ComponentPropertyKind.string,
      const StringValue(''),
      doc: 'The FMOD Studio event path (event:/...).',
      read: (c) => StringValue((c as FmodEventSource).eventPath),
    ),
    ComponentPropertyDef(
      'autoplay',
      ComponentPropertyKind.boolean,
      const BoolValue(false),
      doc: 'Start the event as soon as the source mounts.',
      read: (c) => BoolValue((c as FmodEventSource).autoplay),
    ),
    ComponentPropertyDef(
      'volume',
      ComponentPropertyKind.number,
      const DoubleValue(1.0),
      doc: 'Gain, 1.0 is unity.',
      min: 0,
      read: (c) => DoubleValue((c as FmodEventSource).volume),
    ),
    ComponentPropertyDef(
      'pitch',
      ComponentPropertyKind.number,
      const DoubleValue(1.0),
      doc: 'Playback rate multiplier.',
      min: 0,
      read: (c) => DoubleValue((c as FmodEventSource).pitch),
    ),
    ComponentPropertyDef(
      'positional',
      ComponentPropertyKind.boolean,
      const BoolValue(true),
      doc: 'Spatialize at the node, or play flat when false.',
      read: (c) => BoolValue((c as FmodEventSource).positional),
    ),
    ComponentPropertyDef(
      'parameters',
      ComponentPropertyKind.map,
      MapValue(const {}),
      doc: 'Initial event parameter values by name.',
      read: (c) => MapValue({
        for (final entry in (c as FmodEventSource).parameters.entries)
          entry.key: DoubleValue(entry.value),
      }),
    ),
  ];

  @override
  List<ComponentPropertyDef> get propertySchema => _schema;

  @override
  bool claims(Component component) => component is FmodEventSource;

  @override
  Component realize(ComponentSpec spec, RealizeContext context) {
    final p = spec.properties;
    final parametersValue = p['parameters'];
    return FmodEventSource(
      readString(p, 'event', stringDefault('event')),
      autoplay: readBool(p, 'autoplay', boolDefault('autoplay')),
      volume: readDouble(p, 'volume', numberDefault('volume')),
      pitch: readDouble(p, 'pitch', numberDefault('pitch')),
      positional: readBool(p, 'positional', boolDefault('positional')),
      parameters: {
        if (parametersValue is MapValue)
          for (final entry in parametersValue.values.entries)
            if (entry.value is DoubleValue)
              entry.key: (entry.value as DoubleValue).value
            else if (entry.value is IntValue)
              entry.key: (entry.value as IntValue).value.toDouble(),
      },
    );
  }
}
