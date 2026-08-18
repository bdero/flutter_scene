import 'dart:io';

import 'package:data_assets/data_assets.dart';
import 'package:flutter_scene/src/importer/build_cache.dart';
import 'package:hooks/hooks.dart';

import 'package:scene/scene.dart';
import '../generated_assets/generated_assets.dart';
import '../generated_assets/generated_tree.dart';
import 'inline_assets.dart';
import 'offline_import.dart';

/// Controls where [buildScenes] puts generated `.fsceneb` assets.
enum SceneAssetMode {
  /// Write the generated `.fsceneb` files into the app's
  /// `flutter_scene_generated/` directory and record them in its manifest,
  /// which `loadScene` resolves by source path. The default, and identical on
  /// every Flutter channel.
  generatedTree,

  /// Require Dart data assets and fail the build when the current toolchain did
  /// not enable them for hooks.
  dataAssetsRequired,

  /// Removed. Kept so an upgraded hook fails with instructions instead
  /// of an undefined name.
  @Deprecated(
    'Removed in 0.21.0. Generated assets go into flutter_scene_generated/ and load by source path on every channel. Use generatedTree, then run `dart run flutter_scene:init`.',
  )
  legacyOnly,

  /// Removed. Kept so an upgraded hook fails with instructions instead
  /// of an undefined name.
  @Deprecated(
    'Removed in 0.21.0. Generated assets go into flutter_scene_generated/ and load by source path on every channel. Use generatedTree, then run `dart run flutter_scene:init`.',
  )
  dataAssetsIfAvailable,
}

// Where a data-asset build stages its files before registering them.
const String _dataAssetStagingDirectory = 'build/scenes/';

const String _dataAssetsUnavailableMessage =
    'flutter_scene: SceneAssetMode.dataAssetsRequired needs Flutter support for '
    'Dart data assets, which this toolchain does not have enabled. Use '
    'SceneAssetMode.generatedTree (the default), which writes the same scenes '
    'into $generatedAssetsEntry on every channel.';

/// Returns the DataAsset name for a generated `.fsceneb` output, where
/// [relativeScenePath] is the source path relative to the package root with its
/// extension swapped to `.fsceneb` (for example `assets/level.fsceneb`).
String sceneDataAssetName(String relativeScenePath) =>
    'flutter_scene/scene/$relativeScenePath';

/// The source extensions [buildScenes] discovers and registers: glTF binaries
/// (converted), authored `.fscene` text (compiled to binary), and already-built
/// `.fsceneb` (an editor's imported assets, registered as-is).
const List<String> _sceneSourceExtensions = ['.glb', '.fscene', '.fsceneb'];

/// Discovers scene source files (`.glb`/`.fscene`/`.fsceneb`) below
/// [discoveryRoot] (default `assets/`, relative to [packageRoot]), returned as
/// paths relative to [packageRoot] in stable (sorted) order.
List<String> discoverSceneSources(
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
          .where((f) => _sceneSourceExtensions.any(f.path.endsWith))
          .map((file) {
            final path = file.uri.toFilePath(windows: false);
            return path.substring(rootPath.length);
          })
          .toList()
        ..sort();
  return sources;
}

/// The directory a hook declares to notice sources appearing under
/// [discoveryRoot]. The build system lists every declared directory, so a
/// discovery root that does not exist yet (a fresh `flutter create` app has no
/// `assets/`) would fail the build. The nearest existing ancestor stands in,
/// and creating the root changes that ancestor's children, so the hook still
/// reruns.
Uri discoveryDependencyDirectory(Uri packageRoot, String discoveryRoot) {
  var dir = discoveryRoot.endsWith('/') ? discoveryRoot : '$discoveryRoot/';
  while (dir.isNotEmpty) {
    final candidate = packageRoot.resolve(dir);
    if (Directory.fromUri(candidate).existsSync()) {
      return candidate;
    }
    final parentEnd = dir.lastIndexOf('/', dir.length - 2);
    dir = parentEnd < 0 ? '' : dir.substring(0, parentEnd + 1);
  }
  return packageRoot;
}

/// Converts scene assets so an app loads them by source path with `loadScene`
/// without hand-editing the asset manifest. Discovers three source kinds under
/// [discoveryRoot]: `.glb` (converted to `.fsceneb`), authored `.fscene`
/// (compiled to `.fsceneb`, with referenced images embedded and prefab instances
/// intact for runtime compose), and already-built `.fsceneb` (an editor's
/// `imported/` assets, copied in as-is).
///
/// Call this from a consuming app's `hook/build.dart`:
///
/// ```dart
/// import 'package:hooks/hooks.dart';
/// import 'package:flutter_scene/build_hooks.dart';
///
/// void main(List<String> args) {
///   build(args, (config, output) async {
///     buildScenes(buildInput: config, buildOutput: output);
///   });
/// }
/// ```
///
/// When [inputFilePaths] is omitted, every `.glb`/`.fscene`/`.fsceneb` under
/// [discoveryRoot] (default `assets/`, relative to the package root) is
/// discovered, and each source is declared as a build dependency so changing it
/// retriggers the build (and hot reload). Conversion runs in-process (no
/// subprocess, no native binary).
///
/// Outputs land in the app's `flutter_scene_generated/` directory.
/// [SceneAssetMode.dataAssetsRequired] registers them as data assets keyed
/// `packages/<package>/flutter_scene/scene/<name>.fsceneb` instead.
///
/// Set [compressTextures] to store embedded images as supercompressed block
/// payloads that transcode to the device's format at load, shrinking the
/// container and the GPU footprint. Sources must be a multiple of 4 in both
/// dimensions; anything else is stored uncompressed, with a warning naming it.
/// Textures are mipmapped either way.
void buildScenes({
  required BuildInput buildInput,
  required BuildOutputBuilder buildOutput,
  List<String>? inputFilePaths,
  String discoveryRoot = 'assets/',
  SceneAssetMode assetMode = SceneAssetMode.generatedTree,
  bool compressTextures = false,
  bool alignForCompression = false,
}) {
  // ignore: deprecated_member_use_from_same_package
  if (assetMode == SceneAssetMode.legacyOnly) {
    throwRemovedAssetMode(
      'SceneAssetMode.legacyOnly',
      'SceneAssetMode.generatedTree',
    );
  }
  // ignore: deprecated_member_use_from_same_package
  if (assetMode == SceneAssetMode.dataAssetsIfAvailable) {
    throwRemovedAssetMode(
      'SceneAssetMode.dataAssetsIfAvailable',
      'SceneAssetMode.generatedTree',
    );
  }
  final emitDataAssets = assetMode == SceneAssetMode.dataAssetsRequired;
  if (emitDataAssets && !buildInput.config.buildDataAssets) {
    throw UnsupportedError(_dataAssetsUnavailableMessage);
  }

  final options = HookOptions.of(buildInput);
  final packageRoot = buildInput.packageRoot;
  final inputs =
      inputFilePaths ??
      discoverSceneSources(packageRoot, discoveryRoot: discoveryRoot);
  if (inputFilePaths == null) {
    // A directory dependency is hashed as the names of its direct children, so
    // it costs nothing and catches an added or removed source. Edits are caught
    // by each source's own declared dependency below.
    // TODO(hook-dep-cost): the hash covers direct children only, so a source
    // added in a subdirectory is not seen until something else reruns the hook.
    // Declaring each subdirectory found during discovery would close that.
    buildOutput.dependencies.add(
      discoveryDependencyDirectory(packageRoot, discoveryRoot),
    );
  }

  if (emitDataAssets) {
    // A tree left by an earlier build would ship the same scenes twice, so the
    // data assets this run registers replace it.
    GeneratedAssetTree.openExisting(packageRoot, buildInput.packageName)
      ?..dropOwned(GeneratedAssetFamily.scene, owner: buildInput.packageName)
      ..save();
  }

  // The outputs go into the app's persistent flutter_scene_generated/ tree,
  // whose manifest maps each source path to its generated asset (and stores the
  // build stamp).
  final tree = emitDataAssets
      ? null
      : GeneratedAssetTree.open(
          packageRoot,
          buildInput.packageName,
          options: options,
        );
  if (tree != null &&
      (inputs.isNotEmpty || tree.hasFamily(GeneratedAssetFamily.scene))) {
    tree.requireAssetEntry();
  }
  if (inputs.isEmpty) {
    if (tree != null) {
      tree
        ..pruneMissingSources()
        ..save();
    }
    return;
  }

  final scenesRoot = packageRoot.resolve(_dataAssetStagingDirectory);

  for (final inputFilePath in inputs) {
    final extension = _sceneSourceExtensions.firstWhere(
      inputFilePath.endsWith,
      orElse: () => throw Exception(
        'Scene source must be a .glb, .fscene, or .fsceneb file. Given: '
        '$inputFilePath',
      ),
    );
    if (inputFilePath.startsWith('../') || inputFilePath.contains('/../')) {
      throw Exception(
        'Scene source must be inside the package: $inputFilePath. Place it '
        'under the package (for example in assets/), using a symlink if needed.',
      );
    }

    final sourceUri = packageRoot.resolve(inputFilePath);

    // The source path without its extension, which `loadScene` resolves by.
    final sceneId = inputFilePath.substring(
      0,
      inputFilePath.length - extension.length,
    );

    // An already-built `.fsceneb` (an editor's imported asset) needs no
    // conversion. A DataAsset registers it from its source location; the
    // generated tree has to hold a copy, since only that tree is a listed
    // asset directory.
    if (extension == '.fsceneb') {
      buildOutput.dependencies.add(sourceUri);
      if (emitDataAssets) {
        buildOutput.assets.data.add(
          DataAsset(
            package: buildInput.packageName,
            name: sceneDataAssetName(inputFilePath),
            file: sourceUri,
          ),
        );
        continue;
      }
      final sourceFile = File(sourceUri.toFilePath());
      final stamp =
          'rev=$buildCacheRevision scene kind=.fsceneb '
          'src=${sourceFingerprint(sourceFile, strict: options.strictHashing)}';
      final copyUri = tree!.fileUri(
        GeneratedAssetFamily.scene,
        nameId: sceneId,
        extension: '.fsceneb',
      );
      if (!tree.isFresh(GeneratedAssetFamily.scene, sceneId, stamp, [
        copyUri,
      ])) {
        writeGeneratedBytes(copyUri, sourceFile.readAsBytesSync());
        stdout.writeln('flutter_scene: copied $inputFilePath');
      }
      tree.recordFile(
        family: GeneratedAssetFamily.scene,
        id: sceneId,
        uri: copyUri,
        stamp: stamp,
        source: inputFilePath,
      );
      continue;
    }

    // `.glb` and `.fscene` produce a generated `.fsceneb`.
    final relativeScenePath = '$sceneId.fsceneb';
    final outputSceneUri =
        tree?.fileUri(
          GeneratedAssetFamily.scene,
          nameId: sceneId,
          extension: '.fsceneb',
        ) ??
        scenesRoot.resolve(relativeScenePath);
    Directory.fromUri(outputSceneUri.resolve('.')).createSync(recursive: true);

    // An authored `.fscene` references its imported images by path; read it up
    // front so those files can be embedded into the self-contained `.fsceneb`
    // and tracked as build dependencies (editing a referenced image then
    // retriggers conversion and hot reload). The document is reused for the
    // conversion below when the cache is stale.
    SceneDocument? fsceneDocument;
    List<ExternalImageAsset> imageAssets = const [];
    ExternalPayloadAsset? payloadAsset;
    if (extension == '.fscene') {
      fsceneDocument = readFscene(
        File(sourceUri.toFilePath()).readAsStringSync(),
      );
      imageAssets = resolveExternalImageAssets(fsceneDocument, sourceUri);
      payloadAsset = resolveExternalPayloadAsset(fsceneDocument, sourceUri);
    }

    // Skip the work when the source and settings are unchanged since the
    // output was produced, so a hook rerun for an unrelated edit does not
    // reconvert every scene. Set FLUTTER_SCENE_DISABLE_BUILD_CACHE to always
    // run, or FLUTTER_SCENE_STRICT_HASH to content-hash every source.
    final sourceHash = sourceFingerprint(
      File(sourceUri.toFilePath()),
      strict: options.strictHashing,
    );
    // Fold each referenced image into the stamp, so editing an embedded image
    // (not just the scene text) invalidates the cache and rebuilds the
    // dependent `.fsceneb`.
    final assetHashes = imageAssets
        .map(
          (a) =>
              '${a.key}='
              '${sourceFingerprint(a.file, strict: options.strictHashing)}',
        )
        .toList();
    if (payloadAsset != null) {
      assetHashes.add(
        '${payloadAsset.key}='
        '${sourceFingerprint(payloadAsset.file, strict: options.strictHashing)}',
      );
    }
    final assetStamp = (assetHashes..sort()).join(',');
    final stamp =
        'rev=$buildCacheRevision scene compress=$compressTextures '
        'kind=$extension src=$sourceHash assets=[$assetStamp]';
    final stampFile = File('${outputSceneUri.toFilePath()}.inputs');
    // The generated tree ships every file in it, so the stamp lives in the
    // manifest there rather than in a sidecar next to the output.
    final fresh = tree != null
        ? tree.isFresh(GeneratedAssetFamily.scene, sceneId, stamp, [
            outputSceneUri,
          ])
        : isBuildCacheFresh(stampFile, stamp, [
            File(outputSceneUri.toFilePath()),
          ]);
    if (!fresh) {
      stdout.writeln('flutter_scene: converting $inputFilePath');
      if (extension == '.glb') {
        importGltfToFsceneb(
          inputFilePath,
          outputSceneUri.toFilePath(),
          workingDirectory: packageRoot.toFilePath(),
          compressTextures: compressTextures,
          alignForCompression: alignForCompression,
        );
      } else {
        // `.fscene` (authored text) -> `.fsceneb` (binary), embedding referenced
        // images so the container is self-contained and keeping prefab instances
        // intact for the runtime to compose.
        inlineExternalImageAssets(
          fsceneDocument!,
          imageAssets,
          compressTextures: compressTextures,
          alignForCompression: alignForCompression,
        );
        if (payloadAsset != null) {
          inlineExternalPayloadAsset(fsceneDocument, payloadAsset);
        }
        // `.fmat` refs are authored relative to the document; the built app
        // resolves them through the DataAssets material registry, which keys
        // sources package-relative.
        final documentDirEnd = inputFilePath
            .replaceAll('\\', '/')
            .lastIndexOf('/');
        rebaseFmatMaterialRefs(
          fsceneDocument,
          documentDirEnd < 0
              ? ''
              : inputFilePath
                    .replaceAll('\\', '/')
                    .substring(0, documentDirEnd),
          exists: (key) => File.fromUri(packageRoot.resolve(key)).existsSync(),
        );
        writeGeneratedBytes(outputSceneUri, writeFsceneb(fsceneDocument));
      }
      if (tree == null) stampFile.writeAsStringSync(stamp);
    }
    tree?.recordFile(
      family: GeneratedAssetFamily.scene,
      id: sceneId,
      uri: outputSceneUri,
      stamp: stamp,
      source: inputFilePath,
    );

    buildOutput.dependencies.add(sourceUri);
    // Declare each embedded image as a dependency every run (not only when the
    // cache is stale), so editing it retriggers the hook and the dependent
    // scene's hot reload. The payload sidecar is deliberately not declared: the
    // build system hashes every declared dependency in full, the payload is the
    // largest file in the project, and the `.fscene` text carries its manifest,
    // so any payload change rewrites the text that is declared.
    for (final asset in imageAssets) {
      buildOutput.dependencies.add(asset.file.uri);
    }

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

  if (tree != null) {
    tree
      ..pruneMissingSources()
      ..save();
  }
}
