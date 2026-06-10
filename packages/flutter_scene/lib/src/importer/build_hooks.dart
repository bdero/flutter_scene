import 'dart:io';

import 'package:data_assets/data_assets.dart';
import 'package:flutter_scene/src/importer/build_cache.dart';
import 'package:hooks/hooks.dart';

import 'offline_import.dart';

/// Controls how [buildScenes] exposes generated `.fsceneb` assets.
enum SceneAssetMode {
  /// Only write the generated `.fsceneb` files under `build/scenes/`. The app
  /// lists them in `flutter.assets` and loads them by explicit asset key with
  /// `loadFscenebAsset`; `loadScene` (source-path resolution) needs a
  /// DataAssets mode.
  legacyOnly,

  /// Register generated `.fsceneb` files as DataAssets when the current
  /// toolchain supports them, and otherwise fall back to [legacyOnly].
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
    'channel build, or use SceneAssetMode.legacyOnly, list the generated '
    '`build/scenes/*.fsceneb` files in `flutter.assets`, and load them with '
    'loadFscenebAsset.';

/// Returns the DataAsset name for a generated `.fsceneb` output, where
/// [relativeScenePath] is the source path relative to the package root with its
/// extension swapped to `.fsceneb` (for example `assets/level.fsceneb`).
String sceneDataAssetName(String relativeScenePath) =>
    'flutter_scene/scene/$relativeScenePath';

/// Discovers `.glb` source files below [discoveryRoot] (default `assets/`,
/// relative to [packageRoot]), returned as paths relative to [packageRoot] in
/// stable (sorted) order.
List<String> discoverGlbSources(
  Uri packageRoot, {
  String discoveryRoot = 'assets/',
}) {
  final dir = discoveryRoot.endsWith('/') ? discoveryRoot : '$discoveryRoot/';
  final searchDirectory = Directory.fromUri(packageRoot.resolve(dir));
  if (!searchDirectory.existsSync()) {
    return const [];
  }
  final rootPath = packageRoot.toFilePath(windows: false);
  final sources =
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
  return sources;
}

/// Converts glTF (`.glb`) source assets to flutter_scene's `.fsceneb` package
/// format and writes the result into [outputDirectory] (resolved relative to
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
///     buildScenes(
///       buildInput: config,
///       buildOutput: output,
///       assetMode: SceneAssetMode.dataAssetsIfAvailable,
///     );
///   });
/// }
/// ```
///
/// Load the result by source path with `loadScene`. When [inputFilePaths] is
/// omitted, every `.glb` under [discoveryRoot] (default `assets/`, relative to
/// the package root) is discovered; each generated `.fsceneb` is written under
/// [outputDirectory] and, in a DataAssets mode, registered as a DataAsset (key
/// `packages/<package>/flutter_scene/scene/<name>.fsceneb`); the source `.glb`
/// is declared as a build dependency so re-exporting it retriggers the build
/// (and hot reload). Conversion runs in-process (no subprocess, no native
/// binary).
void buildScenes({
  required BuildInput buildInput,
  required BuildOutputBuilder buildOutput,
  List<String>? inputFilePaths,
  String outputDirectory = 'build/scenes/',
  String discoveryRoot = 'assets/',
  SceneAssetMode assetMode = SceneAssetMode.legacyOnly,
  bool compressTextures = false,
}) {
  final dataAssetsAvailable = buildInput.config.buildDataAssets;
  if (assetMode == SceneAssetMode.dataAssetsRequired && !dataAssetsAvailable) {
    throw UnsupportedError(_dataAssetsUnavailableMessage);
  }
  final emitDataAssets =
      assetMode != SceneAssetMode.legacyOnly && dataAssetsAvailable;

  final packageRoot = buildInput.packageRoot;
  final inputs =
      inputFilePaths ??
      discoverGlbSources(packageRoot, discoveryRoot: discoveryRoot);
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
    // the output was produced, so a hook rerun for an unrelated edit does not
    // re-import every scene. Set FLUTTER_SCENE_DISABLE_BUILD_CACHE to always
    // convert.
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
