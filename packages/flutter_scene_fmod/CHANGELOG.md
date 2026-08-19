## 0.1.1

* Add `registerFmodAudioBackend()`, so documents naming `fmod` as their audio engine realize an `FmodAudioEngine`.
* Ship a `flutter_scene_components.json` manifest for the `fmodEvent` component, kept in sync by a test.
* Fix codec round-trip losses and registry lifecycle holes in `FmodEventCodec`.
* Require `flutter_scene` `^0.22.0`.

## 0.1.0

* Initial release. Implements the flutter_scene audio contract over FMOD Core, plus FMOD Studio banks, events, and buses, against a user-supplied FMOD Engine SDK.
