# flutter_scene_fmod

FMOD Studio audio backend for [flutter_scene](https://pub.dev/packages/flutter_scene), built on the standalone [fmod](https://pub.dev/packages/fmod) bindings package. The flutter_scene audio contract (`ClipAudioSource`, buses, one-shots) plays through FMOD Core, and `FmodEventSource` plays events authored in FMOD Studio, with bank loading and Studio bus control. The full bindings are reachable through `FmodAudioEngine.system` for anything beyond the contract.

## FMOD SDK setup

FMOD is proprietary and its license does not permit redistributing the SDK, so nothing here ships binaries. To use it

1. Register at [fmod.com](https://www.fmod.com) and download the FMOD Engine SDK for your target platforms (free license tiers are available; check the terms and the attribution requirement for your project).
2. Extract the SDK and set `FMOD_SDK_PATH` to the extracted root (the directory containing `api/`). Alternatively set `FMOD_LIBRARY_PATH` to any directory holding the core and studio dynamic libraries.
3. On macOS, clear the download quarantine from the extracted SDK or the system refuses to load the dylibs (`library load disallowed by system policy`): `xattr -dr com.apple.quarantine "<sdk root>"`.
4. Build and run. With `FMOD_SDK_PATH` set, the build hook bundles the libraries into the app; the runtime also falls back to the same environment variables during development.

The package's SDK smoke tests run with `FMOD_SDK_PATH="<sdk root>" flutter test test/fmod_sdk_smoke_test.dart` (they skip when the variable is unset, so CI needs no SDK); the fmod package carries its own suite for the bindings themselves. Verified against FMOD Engine 2.03.14.

Your app is responsible for FMOD's attribution requirement (the FMOD logo in your credits or splash).

## Usage

```dart
import 'package:flutter_scene/scene.dart';
import 'package:flutter_scene_fmod/flutter_scene_fmod.dart';

final scene = Scene();
final engine = FmodAudioEngine();
scene.root.addComponent(engine);

await engine.loadBankAsset('assets/banks/Master.bank');
await engine.loadBankAsset('assets/banks/Master.strings.bank');

final campfire = Node();
campfire.addComponent(FmodEventSource('event:/Ambience/Campfire', autoplay: true));
scene.add(campfire);
```

The engine works with the backend-agnostic contract too, `ClipAudioSource` and `AudioEngine.playOneShot` route through FMOD Core channels, and `createBus` creates core channel groups. Buses authored in FMOD Studio are reached with `engine.studioBus('bus:/SFX')`.

Serialized scenes can carry `fmodEvent` components; register the codec into the realize registry with `registerFmodComponentCodecs`.
