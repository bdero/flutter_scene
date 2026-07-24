// Smoke tests against a real FMOD Engine SDK. Skipped unless
// FMOD_SDK_PATH points at an extracted SDK (the directory containing
// api/), since the SDK cannot be redistributed or fetched in CI. Run
// locally with
//
//   FMOD_SDK_PATH="$HOME/projects/FMOD Programmers API" flutter test \
//       test/fmod_sdk_smoke_test.dart
//
// The engine-level tests drive internal component lifecycle hooks
// directly, hence the internal-member ignores.

import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter_scene/scene.dart';
import 'package:flutter_scene_fmod/flutter_scene_fmod.dart';
import 'package:flutter_scene_fmod/src/ffi/fmod_bindings.dart';
import 'package:flutter_scene_fmod/src/ffi/fmod_library.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' hide Colors;

final String? sdkPath = Platform.environment['FMOD_SDK_PATH'];

String get _media => '$sdkPath/api/studio/examples/media';

Future<void> _tick(
  FmodBindings fmod,
  Pointer<Void> system, {
  int frames = 20,
}) async {
  for (var i = 0; i < frames; i++) {
    fmod.check(fmod.Studio_System_Update(system), 'Studio_System_Update');
    await Future<void>.delayed(const Duration(milliseconds: 16));
  }
}

void main() {
  final skip = sdkPath == null
      ? 'FMOD_SDK_PATH is not set; SDK smoke tests need a local FMOD SDK.'
      : null;

  TestWidgetsFlutterBinding.ensureInitialized();

  test('raw bindings: init, banks, event, core sound', () async {
    final fmod = FmodBindings(FmodLibrary.open());
    final out = calloc<Pointer<Void>>();
    addTearDown(() => calloc.free(out));

    fmod.check(
      fmod.Studio_System_Create(out, kFmodDefaultHeaderVersion),
      'Studio_System_Create',
    );
    final system = out.value;
    fmod.check(
      fmod.Studio_System_Initialize(
        system,
        256,
        fmodStudioInitNormal,
        fmodInitNormal,
        nullptr,
      ),
      'Studio_System_Initialize',
    );
    addTearDown(() => fmod.Studio_System_Release(system));

    out.value = nullptr;
    fmod.check(
      fmod.Studio_System_GetCoreSystem(system, out),
      'Studio_System_GetCoreSystem',
    );
    final core = out.value;
    expect(core, isNot(nullptr));

    // Banks from the SDK's example content.
    for (final bank in ['Master.strings.bank', 'Master.bank', 'SFX.bank']) {
      final path = '$_media/$bank'.toNativeUtf8();
      out.value = nullptr;
      fmod.check(
        fmod.Studio_System_LoadBankFile(
          system,
          path,
          fmodStudioLoadBankNormal,
          out,
        ),
        'LoadBankFile $bank',
      );
      calloc.free(path);
    }

    // Fire an authored event and confirm it reaches a playing state.
    final eventPath = 'event:/Ambience/Country'.toNativeUtf8();
    out.value = nullptr;
    fmod.check(
      fmod.Studio_System_GetEvent(system, eventPath, out),
      'Studio_System_GetEvent',
    );
    calloc.free(eventPath);
    final description = out.value;
    out.value = nullptr;
    fmod.check(
      fmod.Studio_EventDescription_CreateInstance(description, out),
      'CreateInstance',
    );
    final instance = out.value;
    fmod.check(fmod.Studio_EventInstance_Start(instance), 'Start');
    await _tick(fmod, system);
    final state = calloc<Int32>();
    fmod.check(
      fmod.Studio_EventInstance_GetPlaybackState(instance, state),
      'GetPlaybackState',
    );
    expect(
      state.value,
      anyOf(
        fmodStudioPlaybackPlaying,
        fmodStudioPlaybackStarting,
        fmodStudioPlaybackSustaining,
      ),
    );
    calloc.free(state);
    fmod.check(
      fmod.Studio_EventInstance_Stop(instance, fmodStudioStopImmediate),
      'Stop',
    );
    fmod.check(fmod.Studio_EventInstance_Release(instance), 'Release');

    // Core layer: decode a wav and play a paused channel.
    final wavPath = '$sdkPath/api/core/examples/media/drumloop.wav'
        .toNativeUtf8();
    out.value = nullptr;
    fmod.check(
      fmod.System_CreateSound(
        core,
        wavPath,
        fmod3d | fmodCreateSample,
        nullptr,
        out,
      ),
      'System_CreateSound',
    );
    calloc.free(wavPath);
    final sound = out.value;
    final length = calloc<Uint32>();
    fmod.check(
      fmod.Sound_GetLength(sound, length, fmodTimeUnitMs),
      'Sound_GetLength',
    );
    expect(length.value, greaterThan(0));
    calloc.free(length);
    out.value = nullptr;
    fmod.check(
      fmod.System_PlaySound(core, sound, nullptr, 1, out),
      'System_PlaySound',
    );
    final channel = out.value;
    final playing = calloc<Int32>();
    expect(
      fmod.checkChannel(
        fmod.Channel_IsPlaying(channel, playing),
        'Channel_IsPlaying',
      ),
      isTrue,
    );
    expect(playing.value, 1);
    calloc.free(playing);
    fmod.checkChannel(fmod.Channel_Stop(channel), 'Channel_Stop');
    fmod.check(fmod.Sound_Release(sound), 'Sound_Release');
  }, skip: skip);

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
