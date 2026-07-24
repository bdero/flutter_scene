// Engine-level smoke test against a real FMOD Engine SDK. The raw
// bindings have their own smoke suite in the fmod package; this covers
// the flutter_scene contract adapter. Skipped unless FMOD_SDK_PATH
// points at an extracted SDK (the directory containing api/). Run
// locally with
//
//   FMOD_SDK_PATH="$HOME/projects/FMOD Programmers API" flutter test \
//       test/fmod_sdk_smoke_test.dart
//
// The test drives internal component lifecycle hooks directly, hence
// the internal-member ignores.

import 'dart:io';

import 'package:flutter_scene/scene.dart';
import 'package:flutter_scene_fmod/flutter_scene_fmod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' hide Colors;

final String? sdkPath = Platform.environment['FMOD_SDK_PATH'];

String get _media => '$sdkPath/api/studio/examples/media';

void main() {
  final skip = sdkPath == null
      ? 'FMOD_SDK_PATH is not set; SDK smoke tests need a local FMOD SDK.'
      : null;

  TestWidgetsFlutterBinding.ensureInitialized();

  test('FmodAudioEngine end to end: banks, events, clips, buses', () async {
    final root = Node();
    final engine = FmodAudioEngine();
    root.addComponent(engine);
    // ignore: invalid_use_of_internal_member
    engine.mount();
    await engine.ready;
    expect(engine.isAvailable, isTrue);

    await engine.loadBankFile('$_media/Master.strings.bank');
    await engine.loadBankFile('$_media/Master.bank');
    await engine.loadBankFile('$_media/SFX.bank');

    // Studio master bus resolves and takes a volume.
    engine.studioBus('bus:/').volume = 0.8;

    // Contract-level bus and clip playback through FMOD Core.
    final sfx = engine.createBus('sfx');
    final bytes = await File(
      '$sdkPath/api/core/examples/media/drumloop.wav',
    ).readAsBytes();
    final clip = await engine.loadClipFromBytes('drumloop', bytes);
    expect(clip.duration, isNotNull);
    expect(clip.duration!.inMilliseconds, greaterThan(0));
    final voice = engine.playOneShot(
      clip,
      position: Vector3(2, 0, 5),
      volume: 0.5,
      bus: sfx,
    );
    expect(voice.isPlaying, isTrue);

    // An authored event on a mounted source, spatialized by the frame
    // driver.
    final eventNode = Node();
    root.add(eventNode);
    eventNode.localTransform = Matrix4.translation(Vector3(0, 0, 4));
    final source = FmodEventSource('event:/Ambience/Country', autoplay: true);
    eventNode.addComponent(source);
    // ignore: invalid_use_of_internal_member
    source.mount();
    // Wait for the async onLoad (engine ready + event resolution).
    for (var i = 0; i < 50 && !source.isLoaded; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 16));
    }
    expect(source.isLoaded, isTrue);

    for (var i = 0; i < 20; i++) {
      // ignore: invalid_use_of_internal_member
      source.tick(1 / 60);
      // ignore: invalid_use_of_internal_member
      engine.frameSync(1 / 60);
      await Future<void>.delayed(const Duration(milliseconds: 16));
    }
    expect(source.isPlaying, isTrue);
    source.stop();
    voice.stop();

    // Parameters, on the event the SDK's own parameter example uses.
    final steps = FmodEventSource(
      'event:/Character/Player Footsteps',
      parameters: {'Surface': 1.0},
    );
    eventNode.addComponent(steps);
    // ignore: invalid_use_of_internal_member
    steps.mount();
    for (var i = 0; i < 50 && !steps.isLoaded; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 16));
    }
    steps.play();
    steps.setParameter('Surface', 2.0);
    expect(steps.parameters['Surface'], 2.0);
    // An unknown parameter surfaces the FMOD error rather than failing
    // silently.
    expect(
      () => steps.setParameter('Bogus', 1.0),
      throwsA(isA<FmodException>()),
    );
    // ignore: invalid_use_of_internal_member
    steps.unmount();

    // ignore: invalid_use_of_internal_member
    source.unmount();
    // ignore: invalid_use_of_internal_member
    engine.unmount();
    root.removeComponent(engine);
  }, skip: skip);
}
