## 0.1.0

* Implementation for the offline model importer.
* Importer Flatbuffer & Dart codegen.
* bin/import.dart command for invoking the model importer.
* Native assets build hook for compiling the model importer.

## 0.1.1

* Check in generated importer flatbuffer.

## 0.1.2-0

* Mark as pre-release.

## 0.1.2-1

* Use Platform.resolvedExecutable in `buildModels` for resolving the Dart executable.

## 0.1.2-2

* Add more flatbuffer import helpers.

## 0.1.2-3

* Fix erroneous inverse in the flatbuffer->Dart Matrix4 conversion.

## 0.2.0-0

* Remove constexpr qualifiers from matrix for better portability.
* Support non-embedded/URI-only image embeds.
* Fix path interpretation issues on Windows.

## 0.6.0-0

* Pin native_assets_cli to <0.9.0
  (https://github.com/bdero/flutter_gpu_shaders/issues/3)
* Place package version in lockstep with flutter_scene.

## 0.7.0-0

* Update to native_assets_cli 0.9.0.
  Breaking: `BuildOutput` is now `BuildOutputBuilder`

## 0.8.0-0

* Update to Flutter 3.29.0-1.0.pre.242.

## 0.9.0-0

* Update to native_assets_cli 0.13.0.
  Breaking: `BuildConfig` is now `BuildInput`
