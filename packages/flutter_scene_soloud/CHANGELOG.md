## 0.2.0

* Move to `flutter_soloud` 5, which compiles the engine from source through a build hook. Apps drop the bundled Xiph codec libraries by setting `hooks.user_defines.flutter_soloud.no_xiph_libs: true` in their pubspec.
* Web apps load `assets/packages/flutter_soloud/web/init_soloud.js` from `index.html` (renamed upstream).
* Requires Dart 3.11.

## 0.1.2

* Widen the `flutter_scene` constraint to `^0.23.0`. No API changes.

## 0.1.1

* Add `registerSoloudAudioBackend()`, so documents naming `soloud` as their audio engine realize a `SoloudAudioEngine`.
* Require `flutter_scene` `^0.22.0`.

## 0.1.0

* Initial release. Implements the flutter_scene audio contract (engine, voices, buses, clips) over SoLoud via flutter_soloud.
