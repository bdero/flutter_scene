// Codec and component-surface tests. These never touch FMOD native
// code (the FFI is looked up lazily on engine load), so they run
// without an SDK installed.

import 'package:flutter_scene/fscene.dart';
import 'package:flutter_scene_fmod/flutter_scene_fmod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('fmodEvent realizes from a spec and round-trips', () {
    final registry = defaultComponentRegistry();
    registerFmodComponentCodecs(registry);
    final document = SceneDocument();
    final context = RealizeContext(document);

    final spec = ComponentSpec(
      'fmodEvent',
      properties: {
        'event': const StringValue('event:/Ambience/Campfire'),
        'autoplay': const BoolValue(true),
        'volume': const DoubleValue(0.7),
        'parameters': MapValue({
          'Intensity': const DoubleValue(0.5),
          'Size': const IntValue(2),
        }),
      },
    );

    final component = registry.realize(spec, context) as FmodEventSource;
    expect(component.eventPath, 'event:/Ambience/Campfire');
    expect(component.autoplay, isTrue);
    expect(component.volume, 0.7);
    expect(component.pitch, 1.0);
    expect(component.positional, isTrue);
    expect(component.parameters, {'Intensity': 0.5, 'Size': 2.0});

    final serialized = registry.serialize(
      component,
      SerializeContext(document),
    )!;
    expect(serialized.type, 'fmodEvent');
    expect(
      (serialized.properties['event']! as StringValue).value,
      'event:/Ambience/Campfire',
    );
    final parameters = serialized.properties['parameters']! as MapValue;
    expect((parameters.values['Intensity']! as DoubleValue).value, 0.5);
  });

  test('an unmounted FmodEventSource is inert and safe to drive', () {
    final source = FmodEventSource('event:/UI/Click');
    expect(source.isPlaying, isFalse);
    source.play();
    source.setParameter('Pan', 1.0);
    source.stop();
    expect(source.parameters['Pan'], 1.0);
  });
}
