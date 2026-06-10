import 'dart:io';

import 'package:data_assets/data_assets.dart';
import 'package:flutter_scene/src/importer/build_cache.dart';
import 'package:hooks/hooks.dart';

import 'offline_import.dart';

/// Controls how [buildModels] exposes generated `.model` assets.
enum ModelAssetMode {
  /// Preserve the historical behavior: write generated `.model` files under
  /// `build/models/` and let users list those files in `flutter.assets`.
  legacyOnly,

  /// Register generated `.model` files as DataAssets when the current toolchain
  /// supports them, and otherwise fall back to [legacyOnly].
  dataAssetsIfAvailable,

  /// Require DataAssets support and fail the build with a targeted migration
  /// message when the current toolchain did not enable data assets for hooks.
  dataAssetsRequired,
}

const String _dataAssetsUnavailableMessage =
    'flutter_scene DataAssets mode requires Flutter support for Dart data '
    'assets. This feature is currently experimental and available on supported '
    'Flutter master builds. Run `flutter config --enable-dart-data-assets` or '
    'set `FLUTTER_DART_DATA_ASSETS=true`, then rebuild. If your Flutter '
    'toolchain does not recognize that setting, switch to a Flutter master '
    'channel build or use ModelAssetMode.legacyOnly and list the generated '
    '`build/models/*.model` files in `flutter.assets`.';

/// Returns the DataAsset name for a generated `.model` output, where
/// [relativeModelPath] is the source path relative to the package root with its
/// extension swapped to `.model` (for example `assets/vehicles/car.model`).
String modelDataAssetName(String relativeModelPath) =>
    'flutter_scene/model/$relativeModelPath';

/// Returns the DataAsset name for a generated `.fsceneb` output, where
/// [relativeScenePath] is the source path relative to the package root with its
/// extension swapped to `.fsceneb` (for example `assets/level.fsceneb`).
String sceneDataAssetName(String relativeScenePath) =>
    'flutter_scene/scene/$relativeScenePath';

/// Returns the Flutter asset-bundle key for a model DataAsset.
String modelFlutterAssetKey({required String package, required String name}) =>
    'packages/$package/$name';

/// Returns the Flutter asset-bundle key for a generated `.model` DataAsset.
String modelFlutterAssetKeyFor({
  required String package,
  required String relativeModelPath,
}) => modelFlutterAssetKey(
  package: package,
  name: modelDataAssetName(relativeModelPath),
);

/// Discovers `.glb` source files below [discoveryRoot] (default `assets/`,
/// relative to [packageRoot]), returned as paths relative to [packageRoot] in
/// stable (sorted) order.
List<String> discoverGlbModels(
  Uri packageRoot, {
  String discoveryRoot = 'assets/',
}) {
  final dir = discoveryRoot.endsWith('/') ? discoveryRoot : '$discoveryRoot/';
  final searchDirectory = Directory.fromUri(packageRoot.resolve(dir));
  if (!searchDirectory.existsSync()) {
    return const [];
  }
  final rootPath = packageRoot.toFilePath(windows: false);
  final models =
      searchDirectory
          .listSync(recursive: true, followLinks: false)
          .whereType<File>()
          .where((file) => file.path.endsWith('.glb'))
          .map((file) {
            final path = file.uri.toFilePath(windows: false);
            return path.substring(rootPath.length);
          })
          .toList()
        ..sort();
  return models;
}

/// Converts glTF (`.glb`) source assets to flutter_scene's `.model` format and
/// writes the result into [outputDirectory] (resolved relative to
/// [BuildInput.packageRoot]).
///
/// Call this from a consuming app's `hook/build.dart`:
///
/// ```dart
/// import 'package:hooks/hooks.dart';
/// import 'package:flutter_scene/build_hooks.dart';
///
/// void main(List<String> args) {
///   build(args, (config, output) async {
///     buildModels(
///       buildInput: config,
///       buildOutput: output,
///       assetMode: ModelAssetMode.dataAssetsIfAvailable,
///     );
///   });
/// }
/// ```
///
/// If [inputFilePaths] is omitted, every `.glb` under [discoveryRoot] (default
/// `assets/`, relative to the package root) is discovered automatically; set
/// [discoveryRoot] to search a different directory. Each path is resolved
/// relative to the package root and must end in `.glb`. Conversion runs
/// in-process (no subprocess, no native binary).
///
/// Each generated `.model` is written to `[outputDirectory]/<name>.model`, and
/// the corresponding source `.glb` is declared as a build dependency so that
/// re-exporting it retriggers the build (and hot reload). In a DataAssets mode
/// the `.model` is also registered as a DataAsset with the Flutter asset bundle
/// (key `packages/<package>/flutter_scene/model/<name>.model`); in
/// [ModelAssetMode.legacyOnly] the consumer lists `build/models/*.model` under
/// `flutter.assets` instead.
void buildModels({
  required BuildInput buildInput,
  required BuildOutputBuilder buildOutput,
  List<String>? inputFilePaths,
  String outputDirectory = 'build/models/',
  String discoveryRoot = 'assets/',
  ModelAssetMode assetMode = ModelAssetMode.legacyOnly,
}) {
  final dataAssetsAvailable = buildInput.config.buildDataAssets;
  if (assetMode == ModelAssetMode.dataAssetsRequired && !dataAssetsAvailable) {
    throw UnsupportedError(_dataAssetsUnavailableMessage);
  }
  final emitDataAssets =
      assetMode != ModelAssetMode.legacyOnly && dataAssetsAvailable;

  final packageRoot = buildInput.packageRoot;
  final inputs =
      inputFilePaths ??
      discoverGlbModels(packageRoot, discoveryRoot: discoveryRoot);
  if (inputs.isEmpty) {
    return;
  }

  final modelsRoot = packageRoot.resolve(outputDirectory);

  for (final inputFilePath in inputs) {
    if (!inputFilePath.endsWith('.glb')) {
      throw Exception(
        'Input file must be a .glb file. Given file path: $inputFilePath',
      );
    }
    if (inputFilePath.startsWith('../') || inputFilePath.contains('/../')) {
      throw Exception(
        'Model source must be inside the package: $inputFilePath. Place it '
        'under the package (for example in assets/), using a symlink if needed.',
      );
    }

    // Key models by their full path relative to the package root (extension
    // swapped to .model), so two models with the same file name in different
    // directories do not collide.
    final relativeModelPath =
        '${inputFilePath.substring(0, inputFilePath.length - '.glb'.length)}.model';
    final outputModelUri = modelsRoot.resolve(relativeModelPath);
    Directory.fromUri(outputModelUri.resolve('.')).createSync(recursive: true);

    // Skip the conversion when the source is unchanged since the output was
    // produced, so a hook rerun for an unrelated edit does not re-import
    // every model. Set FLUTTER_SCENE_DISABLE_BUILD_CACHE to always convert.
    final sourceHash = contentHash(
      File(packageRoot.resolve(inputFilePath).toFilePath()).readAsBytesSync(),
    );
    final stamp = 'rev=$buildCacheRevision model src=$sourceHash';
    final stampFile = File('${outputModelUri.toFilePath()}.inputs');
    if (!isBuildCacheFresh(stampFile, stamp, [
      File(outputModelUri.toFilePath()),
    ])) {
      importGltf(
        inputFilePath,
        outputModelUri.toFilePath(),
        workingDirectory: packageRoot.toFilePath(),
      );
      stampFile.writeAsStringSync(stamp);
    }

    // Declare the source GLB as a dependency so re-exporting it retriggers the
    // build (and hot reload).
    buildOutput.dependencies.add(packageRoot.resolve(inputFilePath));

    if (emitDataAssets) {
      buildOutput.assets.data.add(
        DataAsset(
          package: buildInput.packageName,
          name: modelDataAssetName(relativeModelPath),
          file: outputModelUri,
        ),
      );
    }
  }
}

/// Converts glTF (`.glb`) source assets to flutter_scene's `.fsceneb` package
/// format, the `.fscene` counterpart of [buildModels].
///
/// Call this from a consuming app's `hook/build.dart` alongside (or instead of)
/// [buildModels]; load the result by source path with `loadScene`. Behaves like
/// [buildModels]: when [inputFilePaths] is omitted, every `.glb` under
/// [discoveryRoot] is discovered; each generated `.fsceneb` is written under
/// [outputDirectory] and, in a DataAssets mode, registered as a DataAsset (key
/// `packages/<package>/flutter_scene/scene/<name>.fsceneb`); the source `.glb`
/// is declared as a build dependency.
void buildScenes({
  required BuildInput buildInput,
  required BuildOutputBuilder buildOutput,
  List<String>? inputFilePaths,
  String outputDirectory = 'build/scenes/',
  String discoveryRoot = 'assets/',
  ModelAssetMode assetMode = ModelAssetMode.legacyOnly,
  bool compressTextures = false,
}) {
  final dataAssetsAvailable = buildInput.config.buildDataAssets;
  if (assetMode == ModelAssetMode.dataAssetsRequired && !dataAssetsAvailable) {
    throw UnsupportedError(_dataAssetsUnavailableMessage);
  }
  final emitDataAssets =
      assetMode != ModelAssetMode.legacyOnly && dataAssetsAvailable;

  final packageRoot = buildInput.packageRoot;
  final inputs =
      inputFilePaths ??
      discoverGlbModels(packageRoot, discoveryRoot: discoveryRoot);
  if (inputs.isEmpty) {
    return;
  }

  final scenesRoot = packageRoot.resolve(outputDirectory);

  for (final inputFilePath in inputs) {
    if (!inputFilePath.endsWith('.glb')) {
      throw Exception(
        'Input file must be a .glb file. Given file path: $inputFilePath',
      );
    }
    if (inputFilePath.startsWith('../') || inputFilePath.contains('/../')) {
      throw Exception(
        'Scene source must be inside the package: $inputFilePath. Place it '
        'under the package (for example in assets/), using a symlink if needed.',
      );
    }

    final relativeScenePath =
        '${inputFilePath.substring(0, inputFilePath.length - '.glb'.length)}'
        '.fsceneb';
    final outputSceneUri = scenesRoot.resolve(relativeScenePath);
    Directory.fromUri(outputSceneUri.resolve('.')).createSync(recursive: true);

    // Skip the conversion when the source and settings are unchanged since
    // the output was produced (see buildModels).
    final sourceHash = contentHash(
      File(packageRoot.resolve(inputFilePath).toFilePath()).readAsBytesSync(),
    );
    final stamp =
        'rev=$buildCacheRevision scene compress=$compressTextures '
        'src=$sourceHash';
    final stampFile = File('${outputSceneUri.toFilePath()}.inputs');
    if (!isBuildCacheFresh(stampFile, stamp, [
      File(outputSceneUri.toFilePath()),
    ])) {
      importGltfToFsceneb(
        inputFilePath,
        outputSceneUri.toFilePath(),
        workingDirectory: packageRoot.toFilePath(),
        compressTextures: compressTextures,
      );
      stampFile.writeAsStringSync(stamp);
    }

    buildOutput.dependencies.add(packageRoot.resolve(inputFilePath));

    if (emitDataAssets) {
      buildOutput.assets.data.add(
        DataAsset(
          package: buildInput.packageName,
          name: sceneDataAssetName(relativeScenePath),
          file: outputSceneUri,
        ),
      );
    }
  }
}
