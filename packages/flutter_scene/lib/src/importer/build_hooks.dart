import 'dart:io';

import 'package:data_assets/data_assets.dart';
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

/// Returns the DataAsset name for a generated `.model` output.
String modelDataAssetName(String fileName) => 'flutter_scene/model/$fileName';

/// Returns the Flutter asset-bundle key for a model DataAsset.
String modelFlutterAssetKey({required String package, required String name}) =>
    'packages/$package/$name';

/// Returns the Flutter asset-bundle key for a generated `.model` DataAsset.
String modelFlutterAssetKeyFor({
  required String package,
  required String fileName,
}) =>
    modelFlutterAssetKey(package: package, name: modelDataAssetName(fileName));

/// Discovers `.glb` source files below the package's `assets/` directory,
/// returned as paths relative to [packageRoot] in stable (sorted) order.
List<String> discoverGlbModels(Uri packageRoot) {
  final assetsDirectory = Directory.fromUri(packageRoot.resolve('assets/'));
  if (!assetsDirectory.existsSync()) {
    return const [];
  }
  final rootPath = packageRoot.toFilePath(windows: false);
  final models =
      assetsDirectory
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
/// If [inputFilePaths] is omitted, every `.glb` under the package's `assets/`
/// directory is discovered automatically. Each path is resolved relative to the
/// package root and must end in `.glb`. Conversion runs in-process (no
/// subprocess, no native binary).
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
  ModelAssetMode assetMode = ModelAssetMode.legacyOnly,
}) {
  final dataAssetsAvailable = buildInput.config.buildDataAssets;
  if (assetMode == ModelAssetMode.dataAssetsRequired && !dataAssetsAvailable) {
    throw UnsupportedError(_dataAssetsUnavailableMessage);
  }
  final emitDataAssets =
      assetMode != ModelAssetMode.legacyOnly && dataAssetsAvailable;

  final packageRoot = buildInput.packageRoot;
  final inputs = inputFilePaths ?? discoverGlbModels(packageRoot);
  if (inputs.isEmpty) {
    return;
  }

  final outDir = Directory.fromUri(packageRoot.resolve(outputDirectory));
  outDir.createSync(recursive: true);

  for (final inputFilePath in inputs) {
    String outputFileName = Uri(path: inputFilePath).pathSegments.last;
    if (!outputFileName.endsWith('.glb')) {
      throw Exception(
        'Input file must be a .glb file. Given file path: $inputFilePath',
      );
    }
    outputFileName =
        '${outputFileName.substring(0, outputFileName.lastIndexOf('.'))}.model';

    final outputModelUri = outDir.uri.resolve(outputFileName);
    importGltf(
      inputFilePath,
      outputModelUri.toFilePath(),
      workingDirectory: packageRoot.toFilePath(),
    );

    // Declare the source GLB as a dependency so re-exporting it retriggers the
    // build (and hot reload).
    buildOutput.dependencies.add(packageRoot.resolve(inputFilePath));

    if (emitDataAssets) {
      buildOutput.assets.data.add(
        DataAsset(
          package: buildInput.packageName,
          name: modelDataAssetName(outputFileName),
          file: outputModelUri,
        ),
      );
    }
  }
}
