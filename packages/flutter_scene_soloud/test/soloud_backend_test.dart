// Backend-registry wiring. Engine construction never touches the native
// SoLoud runtime (initialization happens lazily on load), so this runs
// without audio hardware.

import 'package:flutter_scene/fscene.dart';
import 'package:flutter_scene_soloud/flutter_scene_soloud.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('registerSoloudAudioBackend realizes an engine from its config', () {
    registerSoloudAudioBackend();
    final registry = defaultComponentRegistry();
    final document = SceneDocument();

    final spec = ComponentSpec(
      'audioEngine',
      properties: {
        'backend': const StringValue('soloud'),
        'config': MapValue({
          'maxActiveVoices': const IntValue(48),
          'pauseWhenBackgrounded': const BoolValue(false),
        }),
      },
    );

    final engine =
        registry.realize(spec, RealizeContext(document)) as SoloudAudioEngine;
    expect(engine.maxActiveVoices, 48);
    expect(engine.pauseWhenBackgrounded, isFalse);

    final serialized = registry.serialize(engine, SerializeContext(document))!;
    expect(serialized.type, 'audioEngine');
    expect((serialized.properties['backend']! as StringValue).value, 'soloud');
  });
}
