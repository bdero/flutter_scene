## 0.12.0

* `.model` flatbuffer now carries `MeshPrimitive.bounds_aabb`,
  `MeshPrimitive.bounds_sphere`, and `Node.combined_local_aabb` so
  the runtime can cull subtrees without re-scanning vertex
  positions on every load. Older `.model` files (without these
  fields) continue to load.
* New `MeshPrimitive.skinned_pose_union_aabb` baked offline by
  sampling every animation that drives any joint of the bound
  skin, building the joint palette per keyframe, and unioning
  per-joint vertex influence AABBs transformed by the palette.
  Lets the runtime cull skinned content soundly instead of
  treating it as always visible.
* Read POSITION accessor `min` / `max` from glTF when present so
  the bake can skip the vertex scan for unskinned primitives.

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

## 0.11.0

* Replace the C++ build-time importer with a pure-Dart pipeline. `.glb` →
  `.model` conversion now runs in-process during `buildModels`; CMake and
  the bundled native binary are no longer required to consume the package.
  Output is byte-equivalent to the previous C++ output for vertex/index
  data; lossy-PNG textures may decode slightly differently between
  `package:image` and the prior `stb_image`-via-tinygltf decoder. (#12)
* Remove the `findBuiltExecutable`, `findImporterPackageRoot`, and
  `generateImporterFlatbufferDart` helpers from `offline_import.dart`.
  These existed only to drive the cmake build; they have no replacement
  because the build hook no longer needs them.

## 0.10.0

* Migrate from `native_assets_cli` (discontinued) to `hooks` 1.0.
  Breaking: build hook authors must now `import 'package:hooks/hooks.dart'`
  instead of `package:native_assets_cli/native_assets_cli.dart`. (#82)
* Drop the `--enable-experiment=native-assets` flag from the
  `flutter_scene_importer:import` process invocation. (#82)
* Reorganize the repository as a pub workspace. Package contents
  are unchanged. (#36)
