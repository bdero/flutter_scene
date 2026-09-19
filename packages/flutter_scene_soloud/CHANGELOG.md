## 0.2.0

* Move to `flutter_soloud` 5.1.2, which compiles the engine through a build hook and fetches prebuilt Ogg, Vorbis, Opus, and FLAC libraries for the target on first build, Linux arm64 included. Apps can instead link system packages, compile the codecs from source, or build without them through `hooks.user_defines.flutter_soloud` in their pubspec (see the README).
* The Linux bundle carries its codec libraries under their SONAMEs, so it loads on a machine without the distro codec packages.
* Web apps load `assets/packages/flutter_soloud/web/init_soloud.js` from `index.html` (renamed upstream).
* Requires Dart 3.11.
* Add `SoloudAudioEngine.bufferSize` (config key `bufferSize`) to start SoLoud with a smaller, lower-latency mix buffer.
* Fix mirrored, one-sided 3D panning when the listener pose was synced before any clip loaded and the camera then stayed still.

## 0.1.2

* Widen the `flutter_scene` constraint to `^0.23.0`. No API changes.

## 0.1.1

* Add `registerSoloudAudioBackend()`, so documents naming `soloud` as their audio engine realize a `SoloudAudioEngine`.
* Require `flutter_scene` `^0.22.0`.

## 0.1.0

* Initial release. Implements the flutter_scene audio contract (engine, voices, buses, clips) over SoLoud via flutter_soloud.
