## 0.0.1-dev.1

* Initial render box.

## 0.1.0

* Rewrite for Flutter GPU.
* Physically based rendering.
* More conventional interface for scene construction.

## 0.1.1

* Rename PhysicallyBasedMaterial and UnlitMaterial
* Fix environment lighting problems in PhysicallyBasedMaterial.
* Add default environment map.

## 0.2.0

* Skinned mesh import.
* Fix readme for pub.dev.

## 0.2.1-0

* Switch to pre-release versioning.
* Bump version of flutter_scene_importer.

## 0.2.1-1

* Bump flutter_scene_importer version.

## 0.3.0-0

* Add Animation/playback support (Animation, AnimationPlayer, and AnimationClip).
* Import animations from scene models.
* Add support for cloning nodes.

## 0.4.0-0

* Support node cloning for skins.
* Fix default/animation-less pose.

## 0.5.0-0

* Support non-embedded/URI-only image embeds.

## 0.6.0-0

* Fix memory leak in transients buffer.
* Optional MSAA support on iOS and Android (enabled by default).
* Cull backfaces by default.
* Fix animation blending bugs.
* Pin native_assets_cli to <0.9.0
  (https://github.com/bdero/flutter_gpu_shaders/issues/3)
* Add car model and animation blending examples.
* Fancy readme and FAQ.

## 0.7.0-0

* Update to native_assets_cli 0.9.0.
* Update to flutter_gpu_shaders 0.2.0.

## 0.8.0-0

* Update to Flutter 3.29.0-1.0.pre.242.

## 0.9.0-0

* Update to native_assets_cli 0.13.0.
* Update to flutter_gpu_shaders 0.3.0.

## 0.9.1-0

* Fix invalid usage of textureLod on desktop platforms.

## 0.9.2-0

* Fix globalTransform calculation.

## 0.11.1

* Fix `Node.globalTransform` setter. The previous implementation
  computed `transform * parent.globalTransform.invert()`, but
  `Matrix4.invert()` returns the determinant (a `double`) and mutates
  the receiver, so this was scalar-multiplying `transform` by the
  parent's determinant rather than composing with the parent's inverse.
  Coincidentally produced correct results when the parent had `det=1`,
  but produced garbage for any negative-determinant or non-uniformly-
  scaled parent.

## 0.11.0

* Add a runtime GLB importer. `Node.fromGlbBytes(Uint8List)` and
  `Node.fromGlbAsset(String)` decode a glTF binary directly at runtime —
  no offline `.model` conversion, no build-hook step. Useful for
  user-uploaded models, network-loaded assets, and model editors. (#12)
* Bump `flutter_scene_importer` to `^0.11.0` (pure-Dart `.glb` → `.model`
  build hook; CMake is no longer required).

## 0.10.0

* Migrate from `native_assets_cli` (discontinued) to `hooks` 1.0.
  Breaking: build hook authors must now `import 'package:hooks/hooks.dart'`
  instead of `package:native_assets_cli/native_assets_cli.dart`. (#82)
* Drop the `--enable-experiment=native-assets` flag from the importer
  process invocation. The flag was rejected by Dart 3.10+ and was the
  literal cause of build failures for users on recent Dart channels. (#82)
* Reorganize the repository as a pub workspace with separate `flutter_scene`
  and `flutter_scene_importer` packages and an `examples/` sibling. No
  user-facing surface changes from this; consumers see a cleaner package. (#36)
* Update `flutter_gpu_shaders` to `^0.4.0` (also migrated to `hooks`).
