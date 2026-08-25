import 'dart:convert';
import 'dart:io';

import 'package:data_assets/data_assets.dart';
import 'package:hooks/hooks.dart';

import 'package:flutter_scene/src/importer/build_cache.dart';
import 'package:flutter_scene/src/importer/build_hooks.dart'
    show discoveryDependencyDirectory;

import '../generated_assets/engine_identity.dart' show engineIdentity;
import '../generated_assets/generated_assets.dart';
import '../generated_assets/generated_tree.dart';
import 'fmat.dart';
import 'fmat_emitter.dart'
    show
        kLightmapDefine,
        kRadianceCubeDefine,
        lightmapEntryName,
        materialSamplesEnvironment,
        radianceCubeEntryName;
import 'framework_shaders.dart';
import 'target_shader_bundle.dart';

/// Controls where [buildMaterials] puts generated `.fmat` shader assets.
enum MaterialAssetMode {
  /// Write the compiled bundle, its parameter sidecar, and its index into the
  /// app's `flutter_scene_generated/` directory, which `loadFmatMaterial`
  /// resolves by source path. The default, and identical on every Flutter
  /// channel.
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

const String _dataAssetsUnavailableMessage =
    'flutter_scene: MaterialAssetMode.dataAssetsRequired needs Flutter support '
    'for Dart data assets, which this toolchain does not have enabled. Use '
    'MaterialAssetMode.generatedTree (the default), which compiles the same '
    'materials into $generatedAssetsEntry on every channel.';

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
  'contact_shadow.glsl',
  'depth_bias.glsl',
  'depth_mask.glsl',
  'diffuse_sh.glsl',
  'filtered_scene_color.glsl',
  'flutter_scene_morph.glsl',
  'flutter_scene_skinned_body.glsl',
  'flutter_scene_unskinned_body.glsl',
  'flutter_scene_unskinned_depth_body.glsl',
  'fog.glsl',
  'interleaved_gradient_noise.glsl',
  'irradiance_field.glsl',
  'irradiance_receiver.glsl',
  'lightmap.glsl',
  'lod_fade.glsl',
  'material_engine_lighting.glsl',
  'material_inputs.glsl',
  'material_lighting.glsl',
  'material_shadow_sampling.glsl',
  'material_varyings.glsl',
  'material_vertex.glsl',
  'noise.glsl',
  'normals.glsl',
  'octahedral.glsl',
  'pbr.glsl',
  'scene_inputs.glsl',
  'smaa.glsl',
  'ssao_geometry.glsl',
  'texture.glsl',
  'tone_mapping.glsl',
];

/// Compiles `.fmat` custom-material files into a Flutter GPU shader bundle plus
/// a parameter-metadata sidecar, for use with `ShaderMaterial` /
/// `PreprocessedMaterial` at runtime.
///
/// Call this from a consuming app's `hook/build.dart`, alongside
/// `buildScenes` and `buildShaderBundleJson`:
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
/// `assets/`, the same root `buildScenes` discovers `.glb` sources under) are
/// discovered automatically; set [discoveryRoot] to search a different
/// directory.
/// The bundle carries one fragment entry per material, named by the material's
/// `name`, alongside a combined parameter sidecar and an index. They are written
/// into the app's `flutter_scene_generated/` directory, and `loadFmatMaterial`
/// resolves them by source path.
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
  MaterialAssetMode assetMode = MaterialAssetMode.generatedTree,
}) => _buildMaterials(
  buildInput: buildInput,
  buildOutput: buildOutput,
  materials: materials,
  bundleName: bundleName,
  discoveryRoot: discoveryRoot,
  assetMode: assetMode,
);

/// Builds flutter_scene's bundled physical material shaders.
///
/// [sourceRoot] is flutter_scene's own package root, which the `.fmat` sources
/// resolve against; it defaults to the building package's root (flutter_scene's
/// own hook). The app's hook passes flutter_scene's root so the outputs land in
/// the app's generated tree while the inputs come from the package.
Future<void> buildBundledPhysicalMaterials({
  required BuildInput buildInput,
  required BuildOutputBuilder buildOutput,
  Uri? sourceRoot,
  String? owner,
  MaterialAssetMode assetMode = MaterialAssetMode.generatedTree,
  bool pruneGeneratedTree = true,
  String? fileVariant,
}) => _buildMaterials(
  buildInput: buildInput,
  buildOutput: buildOutput,
  materials: const [
    'assets/materials/physical_opaque.fmat',
    'assets/materials/physical_transmission.fmat',
    'assets/materials/shadow_catcher.fmat',
  ],
  bundleName: 'physical',
  discoveryRoot: 'assets/',
  assetMode: assetMode,
  generateShadowVariants: true,
  // Baked lightmaps go on static opaque surfaces. Transmissive materials are
  // refractive glass, which nothing bakes, and the axis doubles their entries.
  // TODO(lightmap-transmission): generate the axis for PhysicalTransmission
  // too if a transmissive lightmapped surface ever comes up.
  lightmapVariantMaterials: const {'PhysicalOpaque'},
  sourceRoot: sourceRoot,
  owner: owner,
  pruneGeneratedTree: pruneGeneratedTree,
  fileVariant: fileVariant,
);

Future<void> _buildMaterials({
  required BuildInput buildInput,
  required BuildOutputBuilder buildOutput,
  List<String>? materials,
  required String bundleName,
  required String discoveryRoot,
  required MaterialAssetMode assetMode,
  bool generateShadowVariants = false,
  Set<String> lightmapVariantMaterials = const {},
  Uri? sourceRoot,
  String? owner,
  bool pruneGeneratedTree = true,
  String? fileVariant,
}) async {
  // ignore: deprecated_member_use_from_same_package
  if (assetMode == MaterialAssetMode.legacyOnly) {
    throwRemovedAssetMode(
      'MaterialAssetMode.legacyOnly',
      'MaterialAssetMode.generatedTree',
    );
  }
  // ignore: deprecated_member_use_from_same_package
  if (assetMode == MaterialAssetMode.dataAssetsIfAvailable) {
    throwRemovedAssetMode(
      'MaterialAssetMode.dataAssetsIfAvailable',
      'MaterialAssetMode.generatedTree',
    );
  }
  final emitDataAssets = assetMode == MaterialAssetMode.dataAssetsRequired;
  if (emitDataAssets && !buildInput.config.buildDataAssets) {
    throw UnsupportedError(_dataAssetsUnavailableMessage);
  }

  final options = HookOptions.of(buildInput);
  final packageRoot = buildInput.packageRoot;
  // Sources come from the owning package, outputs go to the building package.
  final materialRoot = sourceRoot ?? packageRoot;
  final assetOwner = owner ?? buildInput.packageName;
  final materialPaths =
      materials ??
      discoverFmatMaterials(materialRoot, discoveryRoot: discoveryRoot);
  if (materials == null) {
    // Hashed as the names of its direct children, so an added or removed
    // material reruns the hook for nothing.
    buildOutput.dependencies.add(
      discoveryDependencyDirectory(materialRoot, discoveryRoot),
    );
  }
  if (materialPaths.isEmpty) {
    return;
  }
  if (emitDataAssets && pruneGeneratedTree) {
    // A tree left by an earlier build would ship the same bundle twice.
    GeneratedAssetTree.openExisting(packageRoot, buildInput.packageName)
      ?..dropOwned(GeneratedAssetFamily.material, owner: assetOwner)
      ..save();
  }
  // The outputs go into the app's persistent flutter_scene_generated/ tree,
  // whose manifest records them for the runtime registry (and stores the build
  // stamp).
  final tree = emitDataAssets
      ? null
      : (GeneratedAssetTree.open(
          packageRoot,
          buildInput.packageName,
          options: options,
        )..requireAssetEntry());
  // The compiled bundle only runs on the backends it was trimmed to, so every
  // output keyed to it is separated by target. Several builds share one tree.
  final target = shaderBundleTargetKey(buildInput);

  final frameworkShaders = await frameworkShaderInclude();

  // Generated GLSL and the synthesized manifest live under the package's build
  // directory; they are regenerated each run.
  final generatedDir = Directory.fromUri(
    packageRoot.resolve('build/fmat/$bundleName/'),
  );
  generatedDir.createSync(recursive: true);

  // impellerc always writes the compiled bundle under build/shaderbundles/;
  // the generated tree gets a copy of it, and the sidecar and index are written
  // straight into whichever tree ships them.
  final bundleFile = File(
    packageRoot
        .resolve('build/shaderbundles/$bundleName.shaderbundle')
        .toFilePath(),
  );
  final variant = fileVariant ?? await engineIdentity();
  final shippedBundleFile = tree == null
      ? bundleFile
      : File.fromUri(
          tree.fileUri(
            GeneratedAssetFamily.material,
            nameId: bundleName,
            extension: '.shaderbundle',
            variant: variant,
            target: target,
          ),
        );
  final sidecarFile = File.fromUri(
    tree?.fileUri(
          GeneratedAssetFamily.material,
          nameId: bundleName,
          extension: '.fmat.json',
          variant: variant,
          target: target,
        ) ??
        packageRoot.resolve('build/shaderbundles/$bundleName.fmat.json'),
  );
  final indexFile = File.fromUri(
    tree?.fileUri(
          GeneratedAssetFamily.material,
          nameId: bundleName,
          extension: '.index.json',
          variant: variant,
          target: target,
        ) ??
        packageRoot.resolve('build/shaderbundles/$bundleName.index.json'),
  );

  final sidecars = <String, Object?>{};
  final materialSources = <String, String>{};

  // Skip the whole compile when every source (.fmat files and the framework
  // GLSL they include) is unchanged since the outputs were produced, so a
  // hook rerun for an unrelated edit costs nothing here. A recorded compile
  // error always forces a rebuild (the marker must clear once the source is
  // fixed). Set FLUTTER_SCENE_DISABLE_BUILD_CACHE to always compile.
  final stampBuffer = StringBuffer(
    await shaderBundleStamp(
      buildInput,
      'fmat package=$assetOwner bundle=$bundleName '
      'shadows=$generateShadowVariants '
      'lightmaps=${(lightmapVariantMaterials.toList()..sort()).join(',')}',
    ),
  );
  for (final materialPath in materialPaths) {
    final hash = sourceFingerprint(
      File(materialRoot.resolve(materialPath).toFilePath()),
      strict: options.strictHashing,
    );
    stampBuffer.write(' $materialPath=$hash');
  }
  for (final name in _frameworkShaderFiles) {
    final hash = sourceFingerprint(
      File(frameworkShaders.resolve(name).toFilePath()),
      strict: options.strictHashing,
    );
    stampBuffer.write(' $name=$hash');
  }
  final stamp = stampBuffer.toString();
  final stampFile = File(
    packageRoot.resolve('build/shaderbundles/$bundleName.inputs').toFilePath(),
  );
  final outputs = [shippedBundleFile, sidecarFile, indexFile];
  var fresh = tree != null
      ? tree.isFresh(
          GeneratedAssetFamily.material,
          bundleName,
          stamp,
          outputs.map((file) => file.uri).toList(),
          target: target,
        )
      : isBuildCacheFresh(stampFile, stamp, outputs);
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
      bundleName: bundleName,
      bundleFile: shippedBundleFile,
      sidecarFile: sidecarFile,
      indexFile: indexFile,
      tree: tree,
      stamp: stamp,
      owner: assetOwner,
      target: target,
      writeIndex: false,
      sidecars: const {},
      materialSources: const {},
      packageRoot: materialRoot,
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
      final materialUri = materialRoot.resolve(materialPath);
      final source = File(materialUri.toFilePath()).readAsStringSync();
      final compiled = compileFmat(source, fileName: materialPath);
      final entryName = compiled.material.name;

      if (manifest.containsKey(entryName)) {
        throw Exception(
          'Two materials in bundle "$bundleName" share the name "$entryName"; '
          'material names must be unique within a bundle.',
        );
      }

      final hasShadowVariant =
          generateShadowVariants &&
          compiled.material.shadingModel != FmatShadingModel.unlit;
      final fragmentVariants = emitFragmentShaderVariants(
        compiled,
        generateShadowVariant: hasShadowVariant,
        generateLightmapVariant:
            lightmapVariantMaterials.contains(entryName) &&
            compiled.material.shadingModel != FmatShadingModel.unlit,
      );
      for (final variant in fragmentVariants.entries) {
        final variantEntryName = variant.key;
        final fragFileName = '$variantEntryName.frag';
        File(
          generatedDir.uri.resolve(fragFileName).toFilePath(),
        ).writeAsStringSync(variant.value);
        manifest[variantEntryName] = <String, Object?>{
          'type': 'fragment',
          // impellerc resolves a bundle entry's `file` relative to the package
          // root, so reference it from there instead of from the manifest.
          'file': 'build/fmat/$bundleName/$fragFileName',
        };
      }

      // A material with a `vertex { }` block also contributes one vertex shader
      // per mesh-type/pass variant, compiled into the same bundle and selected
      // at render time by the runtime.
      compiled.vertexGlsl.forEach((vertexEntry, vertexGlsl) {
        if (manifest.containsKey(vertexEntry)) {
          throw Exception(
            'Generated vertex entry "$vertexEntry" for material "$entryName" '
            'in bundle "$bundleName" collides with another entry; rename the '
            'material.',
          );
        }
        final vertFileName = '$vertexEntry.vert';
        File(
          generatedDir.uri.resolve(vertFileName).toFilePath(),
        ).writeAsStringSync(vertexGlsl);
        manifest[vertexEntry] = <String, Object?>{
          'type': 'vertex',
          'file': 'build/fmat/$bundleName/$vertFileName',
        };
      });

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
      await buildTargetShaderBundleJson(
        buildInput: buildInput,
        buildOutput: buildOutput,
        manifestFileName: manifestRelativePath,
        includeDirectories: [frameworkShaders],
        // Match the engine bundle's GLES dialect (GLSL ES 3.00); the
        // framework radiance sampling these materials can `#include` uses
        // textureLod, which is not available in 1.00 without an extension.
        glesLanguageVersion: 300,
        // The material bundle ships under materials/ next to its sidecar and
        // index, not as a standalone shader bundle.
        copyToGeneratedTree: false,
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

    // Publish the freshly compiled bundle into the tree that ships it.
    if (tree != null) {
      writeGeneratedBytes(shippedBundleFile.uri, bundleFile.readAsBytesSync());
    }
    // Write the combined parameter sidecar next to the produced bundle.
    writeGeneratedString(
      sidecarFile.uri,
      const JsonEncoder.withIndent('  ').convert(sidecars),
    );
    if (tree == null) stampFile.writeAsStringSync(stamp);
    stdout.writeln(
      'flutter_scene: compiled ${materialPaths.length} .fmat '
      '${materialPaths.length == 1 ? 'material' : 'materials'} into '
      '"$bundleName"',
    );
  } catch (error) {
    final haveLastGood =
        shippedBundleFile.existsSync() &&
        sidecarFile.existsSync() &&
        indexFile.existsSync();
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
        writeGeneratedString(
          sidecarFile.uri,
          const JsonEncoder.withIndent('  ').convert(lastGood),
        );
      }
    } catch (_) {
      // The previous sidecar was unreadable; the stderr report stands alone.
    }
    _registerOutputs(
      buildInput: buildInput,
      buildOutput: buildOutput,
      bundleName: bundleName,
      bundleFile: shippedBundleFile,
      sidecarFile: sidecarFile,
      indexFile: indexFile,
      tree: tree,
      stamp: stamp,
      owner: assetOwner,
      target: target,
      writeIndex: false,
      sidecars: const {},
      materialSources: const {},
      packageRoot: materialRoot,
      materialPaths: materialPaths,
      frameworkShaders: frameworkShaders,
    );
    return;
  }

  _registerOutputs(
    buildInput: buildInput,
    buildOutput: buildOutput,
    bundleName: bundleName,
    bundleFile: shippedBundleFile,
    sidecarFile: sidecarFile,
    indexFile: indexFile,
    tree: tree,
    stamp: stamp,
    owner: assetOwner,
    target: target,
    writeIndex: true,
    sidecars: sidecars,
    materialSources: materialSources,
    packageRoot: materialRoot,
    materialPaths: materialPaths,
    frameworkShaders: frameworkShaders,
  );
}

/// Emits the fragment entries contributed by [compiled].
Map<String, String> emitFragmentShaderVariants(
  FmatCompilation compiled, {
  required bool generateShadowVariant,
  bool generateLightmapVariant = false,
}) {
  final material = compiled.material;
  final entryName = material.name;
  // The outermost axis, so a Lightmap entry still gets its Shadow and Cube
  // twins. Only materials expected to carry a bake generate it; it doubles
  // the entries of the ones that do.
  final byLightmap = <String, List<String>>{
    entryName: const [],
    if (generateLightmapVariant)
      lightmapEntryName(entryName): const [kLightmapDefine],
  };
  // The unsuffixed entry is the no-shadow fast path. The Shadow entry keeps
  // the complete sampler layout used when the scene binds a shadow atlas.
  final byShadow = <String, List<String>>{};
  byLightmap.forEach((name, defines) {
    if (generateShadowVariant) {
      byShadow[name] = [...defines, 'FLUTTER_SCENE_SKIP_SHADOWS'];
      byShadow['${name}Shadow'] = defines;
    } else {
      byShadow[name] = defines;
    }
  });
  if (!materialSamplesEnvironment(material)) {
    return <String, String>{
      for (final entry in byShadow.entries)
        entry.key: entry.value.isEmpty
            ? compiled.glsl
            : emitFragmentGlsl(material, defines: entry.value),
    };
  }
  // Backends build the prefiltered radiance in one of two layouts and each
  // entry declares only its own sampler, so every entry gets a Cube twin that
  // the runtime picks from the bound environment.
  final variants = <String, String>{};
  byShadow.forEach((name, defines) {
    variants[name] = defines.isEmpty
        ? compiled.glsl
        : emitFragmentGlsl(material, defines: defines);
    variants[radianceCubeEntryName(name)] = emitFragmentGlsl(
      material,
      defines: [...defines, kRadianceCubeDefine],
    );
  });
  return variants;
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
  required String bundleName,
  required File bundleFile,
  required File sidecarFile,
  required File indexFile,
  required GeneratedAssetTree? tree,
  required String stamp,
  required String owner,
  required String target,
  required bool writeIndex,
  required Map<String, Object?> sidecars,
  required Map<String, String> materialSources,
  required Uri packageRoot,
  required List<String> materialPaths,
  required Uri frameworkShaders,
}) {
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
  if (writeIndex) {
    // The bundle and its sidecar always sit in the same directory as the index,
    // so the registry resolves them from the index's own asset key by file name.
    // That holds for data assets (one directory per bundle) and for the
    // generated tree (one flat directory) alike.
    final index = <String, Object?>{
      'schema': 2,
      'package': owner,
      'bundleName': bundleName,
      'shaderBundleFileName': bundleFile.uri.pathSegments.last,
      'sidecarFileName': sidecarFile.uri.pathSegments.last,
      'materials': {
        for (final key in sidecars.keys)
          key: {'entryName': key, 'source': materialSources[key]},
      },
    };
    writeGeneratedString(
      indexFile.uri,
      const JsonEncoder.withIndent('  ').convert(index),
    );
  }

  if (tree != null) {
    tree
      ..recordFile(
        family: GeneratedAssetFamily.material,
        id: bundleName,
        uri: indexFile.uri,
        stamp: stamp,
        owner: owner,
        target: target,
      )
      ..recordFile(
        family: GeneratedAssetFamily.material,
        id: '$bundleName#shaderbundle',
        uri: bundleFile.uri,
        stamp: stamp,
        owner: owner,
        target: target,
      )
      ..recordFile(
        family: GeneratedAssetFamily.material,
        id: '$bundleName#sidecar',
        uri: sidecarFile.uri,
        stamp: stamp,
        owner: owner,
        target: target,
      )
      ..save();
  } else {
    buildOutput.assets.data.addAll([
      DataAsset(
        package: buildInput.packageName,
        name: shaderBundleAssetName,
        file: bundleFile.uri,
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
        fmatFlutterAssetKey(
          package: buildInput.packageName,
          name: indexAssetName,
        );
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
