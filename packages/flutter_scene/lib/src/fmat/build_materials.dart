import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:data_assets/data_assets.dart';
import 'package:flutter_gpu_shaders/build.dart';
import 'package:hooks/hooks.dart';

import 'package:flutter_scene/src/importer/build_cache.dart';

import 'fmat.dart';

/// Controls how [buildMaterials] exposes generated `.fmat` shader assets.
enum MaterialAssetMode {
  /// Preserve the historical behavior: write generated files under
  /// `build/shaderbundles/` and let users list those files in `flutter.assets`.
  legacyOnly,

  /// Register generated files as DataAssets when the current toolchain supports
  /// them, and otherwise fall back to [legacyOnly].
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
    'channel build or use MaterialAssetMode.legacyOnly and list the generated '
    '`build/shaderbundles/*.shaderbundle` and `.fmat.json` files in '
    '`flutter.assets`.';

/// Returns the DataAsset name for a generated `.fmat` output.
String fmatDataAssetName(String bundleName, String fileName) =>
    'flutter_scene/fmat/$bundleName/$fileName';

/// Returns the Flutter asset-bundle key for a DataAsset.
String fmatFlutterAssetKey({required String package, required String name}) =>
    'packages/$package/$name';

/// Returns the asset key for a generated `.fmat` DataAsset.
String fmatFlutterAssetKeyFor({
  required String package,
  required String bundleName,
  required String fileName,
}) => fmatFlutterAssetKey(
  package: package,
  name: fmatDataAssetName(bundleName, fileName),
);

/// Discovers `.fmat` material sources under [discoveryRoot] (default `assets/`,
/// matching [discoverGlbModels] for models), returned as paths relative to the
/// package root. Used when [buildMaterials] is called without an explicit list.
List<String> discoverFmatMaterials(
  Uri packageRoot, {
  String discoveryRoot = 'assets/',
}) {
  final dir = discoveryRoot.endsWith('/') ? discoveryRoot : '$discoveryRoot/';
  final searchDirectory = Directory.fromUri(packageRoot.resolve(dir));
  if (!searchDirectory.existsSync()) {
    return const [];
  }
  final rootPath = packageRoot.toFilePath(windows: false);
  final materials =
      searchDirectory
          .listSync(recursive: true, followLinks: false)
          .whereType<File>()
          .where((file) => file.path.endsWith('.fmat'))
          .map((file) {
            final path = file.uri.toFilePath(windows: false);
            return path.substring(rootPath.length);
          })
          .toList()
        ..sort();
  return materials;
}

/// The framework GLSL files (in flutter_scene's `shaders/` directory) that a
/// generated material shader can `#include`. Declared as build dependencies so
/// editing one retriggers a consumer's material build. Transitive `#include`s
/// inside these are not tracked until `impellerc --depfile` is consumed in
/// `--shader-bundle` mode (bdero/flutter_gpu_shaders#15).
const _frameworkShaderFiles = <String>[
  'material_varyings.glsl',
  'pbr.glsl',
  'texture.glsl',
  'normals.glsl',
  'material_inputs.glsl',
  'material_engine_lighting.glsl',
  'material_lighting.glsl',
];

/// Compiles `.fmat` custom-material files into a Flutter GPU shader bundle plus
/// a parameter-metadata sidecar, for use with `ShaderMaterial` /
/// `PreprocessedMaterial` at runtime.
///
/// Call this from a consuming app's `hook/build.dart`, alongside
/// [buildModels] and `buildShaderBundleJson`:
///
/// ```dart
/// import 'package:hooks/hooks.dart';
/// import 'package:flutter_scene/build_hooks.dart';
///
/// void main(List<String> args) {
///   build(args, (config, output) async {
///     await buildMaterials(
///       buildInput: config,
///       buildOutput: output,
///       materials: ['assets/toon.fmat'],
///     );
///   });
/// }
/// ```
///
/// Each path in [materials] is resolved relative to the package root. If
/// [materials] is omitted, `.fmat` files under [discoveryRoot] (default
/// `assets/`, the same root [buildModels] discovers `.glb` models under) are
/// discovered automatically; set [discoveryRoot] to search a different
/// directory.
/// The produced bundle is written to
/// `build/shaderbundles/[bundleName].shaderbundle` (one fragment entry per
/// material, named by the material's `name`), and the combined parameter
/// sidecar to `build/shaderbundles/[bundleName].fmat.json`. In
/// [MaterialAssetMode.legacyOnly], list both as assets in the app's pubspec.
/// In DataAssets modes, the generated files are registered as DataAssets when
/// the toolchain supports them.
///
/// The generated shaders `#include` flutter_scene's framework GLSL; this hook
/// puts flutter_scene's `shaders/` directory on `impellerc`'s include path (via
/// `buildShaderBundleJson`'s `includeDirectories`), so no framework files are
/// copied into the consumer's project.
Future<void> buildMaterials({
  required BuildInput buildInput,
  required BuildOutputBuilder buildOutput,
  List<String>? materials,
  String bundleName = 'materials',
  String discoveryRoot = 'assets/',
  MaterialAssetMode assetMode = MaterialAssetMode.legacyOnly,
}) async {
  final dataAssetsAvailable = buildInput.config.buildDataAssets;
  if (assetMode == MaterialAssetMode.dataAssetsRequired &&
      !dataAssetsAvailable) {
    throw UnsupportedError(_dataAssetsUnavailableMessage);
  }

  final packageRoot = buildInput.packageRoot;
  final materialPaths =
      materials ??
      discoverFmatMaterials(packageRoot, discoveryRoot: discoveryRoot);
  if (materialPaths.isEmpty) {
    return;
  }

  // Locate flutter_scene's framework shader directory. flutter_scene has no
  // top-level `flutter_scene.dart` library, so resolve through this package's
  // `build_hooks.dart` (which always exists) and hop to the sibling `shaders/`.
  final frameworkLib = await Isolate.resolvePackageUri(
    Uri.parse('package:flutter_scene/build_hooks.dart'),
  );
  if (frameworkLib == null) {
    throw Exception(
      'buildMaterials could not resolve the flutter_scene package location.',
    );
  }
  final frameworkShaders = frameworkLib.resolve('../shaders/');

  // Generated GLSL and the synthesized manifest live under the package's build
  // directory; they are regenerated each run.
  final generatedDir = Directory.fromUri(
    packageRoot.resolve('build/fmat/$bundleName/'),
  );
  generatedDir.createSync(recursive: true);

  final bundleFile = File(
    packageRoot
        .resolve('build/shaderbundles/$bundleName.shaderbundle')
        .toFilePath(),
  );
  final sidecarFile = File(
    packageRoot
        .resolve('build/shaderbundles/$bundleName.fmat.json')
        .toFilePath(),
  );
  final indexFile = File(
    packageRoot
        .resolve('build/shaderbundles/$bundleName.index.json')
        .toFilePath(),
  );

  final sidecars = <String, Object?>{};
  final materialSources = <String, String>{};

  // Skip the whole compile when every source (.fmat files and the framework
  // GLSL they include) is unchanged since the outputs were produced, so a
  // hook rerun for an unrelated edit costs nothing here. A recorded compile
  // error always forces a rebuild (the marker must clear once the source is
  // fixed). Set FLUTTER_SCENE_DISABLE_BUILD_CACHE to always compile.
  final stampBuffer = StringBuffer(
    'rev=$buildCacheRevision fmat package=${buildInput.packageName} '
    'bundle=$bundleName',
  );
  for (final materialPath in materialPaths) {
    final hash = contentHash(
      File(packageRoot.resolve(materialPath).toFilePath()).readAsBytesSync(),
    );
    stampBuffer.write(' $materialPath=$hash');
  }
  for (final name in _frameworkShaderFiles) {
    final hash = contentHash(
      File(frameworkShaders.resolve(name).toFilePath()).readAsBytesSync(),
    );
    stampBuffer.write(' $name=$hash');
  }
  final stamp = stampBuffer.toString();
  final stampFile = File(
    packageRoot.resolve('build/shaderbundles/$bundleName.inputs').toFilePath(),
  );
  final wantIndex =
      dataAssetsAvailable && assetMode != MaterialAssetMode.legacyOnly;
  var fresh = isBuildCacheFresh(stampFile, stamp, [
    bundleFile,
    sidecarFile,
    if (wantIndex) indexFile,
  ]);
  if (fresh) {
    try {
      fresh = !sidecarFile.readAsStringSync().contains('#compile_error');
    } catch (_) {
      fresh = false;
    }
  }
  if (fresh) {
    _registerOutputs(
      buildInput: buildInput,
      buildOutput: buildOutput,
      assetMode: assetMode,
      dataAssetsAvailable: dataAssetsAvailable,
      bundleName: bundleName,
      bundleFile: bundleFile,
      sidecarFile: sidecarFile,
      indexFile: indexFile,
      writeIndex: false,
      sidecars: const {},
      materialSources: const {},
      packageRoot: packageRoot,
      materialPaths: materialPaths,
      frameworkShaders: frameworkShaders,
    );
    return;
  }

  // Compile and bundle, but tolerate a broken material when the previous
  // outputs exist: a `.fmat` edit with a shader error during hot reload then
  // keeps the last good shaders on screen (with the error reported) instead
  // of failing the whole build and taking the session down. A first build
  // with no previous output still fails with the real error.
  try {
    final manifest = <String, Object?>{};
    for (final materialPath in materialPaths) {
      if (!materialPath.endsWith('.fmat')) {
        throw Exception('Material files must end with ".fmat": $materialPath');
      }
      final materialUri = packageRoot.resolve(materialPath);
      final source = File(materialUri.toFilePath()).readAsStringSync();
      final compiled = compileFmat(source, fileName: materialPath);
      final entryName = compiled.material.name;

      if (manifest.containsKey(entryName)) {
        throw Exception(
          'Two materials in bundle "$bundleName" share the name "$entryName"; '
          'material names must be unique within a bundle.',
        );
      }

      final fragFileName = '$entryName.frag';
      File(
        generatedDir.uri.resolve(fragFileName).toFilePath(),
      ).writeAsStringSync(compiled.glsl);

      manifest[entryName] = <String, Object?>{
        'type': 'fragment',
        // impellerc resolves a bundle entry's `file` relative to the package
        // root (its working directory), so reference the generated shader from
        // there, not relative to the manifest.
        'file': 'build/fmat/$bundleName/$fragFileName',
      };
      sidecars[entryName] = compiled.sidecar;
      materialSources[entryName] = materialPath;
    }

    // Write the synthesized shader-bundle manifest next to the generated
    // shaders, so its `file` entries resolve relative to it.
    final manifestRelativePath =
        'build/fmat/$bundleName/$bundleName.shaderbundle.json';
    File(
      packageRoot.resolve(manifestRelativePath).toFilePath(),
    ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(manifest));

    // Snapshot the previous bundle so a failed compile that left a partial
    // file behind can be rolled back to the last good bundle.
    final previousBundleBytes = bundleFile.existsSync()
        ? bundleFile.readAsBytesSync()
        : null;
    try {
      // Compile, with flutter_scene's shaders/ on the include path so the
      // generated shaders' framework `#include`s resolve directly (no copies).
      await buildShaderBundleJson(
        buildInput: buildInput,
        buildOutput: buildOutput,
        manifestFileName: manifestRelativePath,
        includeDirectories: [frameworkShaders],
      );
    } catch (_) {
      // Roll back only when the failed compile actually disturbed the bundle;
      // an unnecessary rewrite changes the file's timestamp mid-build, which
      // the tool flags as a modified file and reruns the build for.
      if (previousBundleBytes != null &&
          (!bundleFile.existsSync() ||
              !_sameBytes(bundleFile.readAsBytesSync(), previousBundleBytes))) {
        bundleFile.writeAsBytesSync(previousBundleBytes);
      }
      rethrow;
    }

    // Write the combined parameter sidecar next to the produced bundle.
    sidecarFile.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(sidecars),
    );
    stampFile.writeAsStringSync(stamp);
  } catch (error) {
    final shouldRegisterIndex =
        dataAssetsAvailable && assetMode != MaterialAssetMode.legacyOnly;
    final haveLastGood =
        bundleFile.existsSync() &&
        sidecarFile.existsSync() &&
        (!shouldRegisterIndex || indexFile.existsSync());
    if (!haveLastGood) {
      rethrow;
    }
    stderr.writeln(
      'flutter_scene: building .fmat materials failed; keeping the previous '
      'shaders.\n$error',
    );
    // Surface the error in the running app too: the sidecar's content hash
    // changes, so the hot-reload coordinator re-reads it and prints the
    // marker. The per-material entries are unchanged, so the live materials
    // keep their last good state. The success path below rewrites the sidecar
    // without the marker once the material compiles again.
    try {
      final lastGood = (jsonDecode(sidecarFile.readAsStringSync()) as Map)
          .cast<String, Object?>();
      // Skip the rewrite when the same error is already recorded, so repeated
      // failed reloads do not churn the file's timestamp.
      if (lastGood['#compile_error'] != '$error') {
        lastGood['#compile_error'] = '$error';
        sidecarFile.writeAsStringSync(
          const JsonEncoder.withIndent('  ').convert(lastGood),
        );
      }
    } catch (_) {
      // The previous sidecar was unreadable; the stderr report stands alone.
    }
    _registerOutputs(
      buildInput: buildInput,
      buildOutput: buildOutput,
      assetMode: assetMode,
      dataAssetsAvailable: dataAssetsAvailable,
      bundleName: bundleName,
      bundleFile: bundleFile,
      sidecarFile: sidecarFile,
      indexFile: indexFile,
      writeIndex: false,
      sidecars: const {},
      materialSources: const {},
      packageRoot: packageRoot,
      materialPaths: materialPaths,
      frameworkShaders: frameworkShaders,
    );
    return;
  }

  _registerOutputs(
    buildInput: buildInput,
    buildOutput: buildOutput,
    assetMode: assetMode,
    dataAssetsAvailable: dataAssetsAvailable,
    bundleName: bundleName,
    bundleFile: bundleFile,
    sidecarFile: sidecarFile,
    indexFile: indexFile,
    writeIndex: true,
    sidecars: sidecars,
    materialSources: materialSources,
    packageRoot: packageRoot,
    materialPaths: materialPaths,
    frameworkShaders: frameworkShaders,
  );
}

bool _sameBytes(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

// Registers the bundle/sidecar/index outputs and declares the source
// dependencies. Shared by the success path (which also rewrites the index)
// and the kept-last-good failure path (which registers the existing files;
// the index on disk matches them).
void _registerOutputs({
  required BuildInput buildInput,
  required BuildOutputBuilder buildOutput,
  required MaterialAssetMode assetMode,
  required bool dataAssetsAvailable,
  required String bundleName,
  required File bundleFile,
  required File sidecarFile,
  required File indexFile,
  required bool writeIndex,
  required Map<String, Object?> sidecars,
  required Map<String, String> materialSources,
  required Uri packageRoot,
  required List<String> materialPaths,
  required Uri frameworkShaders,
}) {
  final shouldRegisterDataAssets =
      dataAssetsAvailable && assetMode != MaterialAssetMode.legacyOnly;
  if (shouldRegisterDataAssets) {
    final shaderBundleFile = bundleFile.uri;
    final shaderBundleAssetName = fmatDataAssetName(
      bundleName,
      '$bundleName.shaderbundle',
    );
    final sidecarAssetName = fmatDataAssetName(
      bundleName,
      '$bundleName.fmat.json',
    );
    final indexAssetName = fmatDataAssetName(
      bundleName,
      '$bundleName.index.json',
    );
    final shaderBundleAssetKey = fmatFlutterAssetKey(
      package: buildInput.packageName,
      name: shaderBundleAssetName,
    );
    final sidecarAssetKey = fmatFlutterAssetKey(
      package: buildInput.packageName,
      name: sidecarAssetName,
    );
    final indexAssetKey = fmatFlutterAssetKey(
      package: buildInput.packageName,
      name: indexAssetName,
    );
    if (writeIndex) {
      final index = <String, Object?>{
        'schema': 1,
        'package': buildInput.packageName,
        'bundleName': bundleName,
        'shaderBundleAssetKey': shaderBundleAssetKey,
        'sidecarAssetKey': sidecarAssetKey,
        'materials': {
          for (final key in sidecars.keys)
            key: {'entryName': key, 'source': materialSources[key]},
        },
      };
      indexFile.writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert(index),
      );
    }

    buildOutput.assets.data.addAll([
      DataAsset(
        package: buildInput.packageName,
        name: shaderBundleAssetName,
        file: shaderBundleFile,
      ),
      DataAsset(
        package: buildInput.packageName,
        name: sidecarAssetName,
        file: sidecarFile.uri,
      ),
      DataAsset(
        package: buildInput.packageName,
        name: indexAssetName,
        file: indexFile.uri,
      ),
    ]);
    buildOutput.metadata['flutter_scene.fmat.$bundleName.indexAssetKey'] =
        indexAssetKey;
  }

  // Declare the real inputs as dependencies. buildShaderBundleJson declares the
  // (generated) .frag files; the sources that actually drive a rebuild are the
  // .fmat files and the framework GLSL they include. Every source is declared
  // even when one failed to compile, so fixing it retriggers the hook.
  buildOutput.dependencies.addAll(materialPaths.map(packageRoot.resolve));
  buildOutput.dependencies.addAll(
    _frameworkShaderFiles.map(frameworkShaders.resolve),
  );
}
