import 'dart:io';
import 'dart:typed_data';

import 'package:code_assets/code_assets.dart';
import 'package:data_assets/data_assets.dart';
import 'package:flutter_gpu_shaders/build.dart';
import 'package:hooks/hooks.dart';

import '../generated_assets/engine_identity.dart';
import '../generated_assets/generated_assets.dart';
import '../generated_assets/generated_file_names.dart';
import '../generated_assets/generated_tree.dart';
import '../gpu/web/shader_bundle_generated.dart' as fb;
import '../importer/build_cache.dart' show buildCacheRevision;

/// Shader backends stored in a Flutter GPU shader bundle.
// TODO(shader-bundle): add desktop OpenGL selection when Flutter GPU exposes
// that target.
enum ShaderBundleBackend { metalIos, metalDesktop, openglEs, vulkan }

/// Controls where a target-specific shader bundle is published.
enum TargetShaderBundleAssetMode {
  /// Copy the trimmed bundle into the app's `flutter_scene_generated/`
  /// directory, resolvable by bundle name with `resolveShaderBundleKey`. The
  /// default, and identical on every Flutter channel.
  generatedTree,

  /// Register the bundle as a Dart data asset when the current toolchain
  /// supports them, and otherwise fall back to [generatedTree].
  dataAssetsIfAvailable,

  /// Require Dart data assets and fail the build when the current toolchain did
  /// not enable them for hooks.
  dataAssetsRequired,
}

/// Builds a shader bundle and removes backends the target cannot use.
///
/// TODO(shader-bundle-cache): the compiler runs on every hook rerun, since only
/// [stamp] callers skip it. Stamping the manifest and its sources here would let
/// an unrelated asset edit skip the compile.
///
/// In [TargetShaderBundleAssetMode.generatedTree] the trimmed bundle is copied
/// into the app's generated tree, recorded under the manifest name it was built
/// from. [copyToGeneratedTree] turns that off for a caller that publishes the
/// bundle itself (`buildMaterials`), and [owner] names the package the bundle
/// belongs to when the app's hook builds a dependency's shaders.
Future<void> buildTargetShaderBundleJson({
  required BuildInput buildInput,
  required BuildOutputBuilder buildOutput,
  required String manifestFileName,
  List<Uri> includeDirectories = const [],
  TargetShaderBundleAssetMode assetMode =
      TargetShaderBundleAssetMode.generatedTree,
  String? dataAssetName,
  int? glesLanguageVersion,
  bool copyToGeneratedTree = true,
  String? owner,
  String? stamp,
}) async {
  final emitDataAssets =
      buildInput.config.buildDataAssets &&
      assetMode != TargetShaderBundleAssetMode.generatedTree;
  final result = await buildShaderBundleJson(
    buildInput: buildInput,
    buildOutput: buildOutput,
    manifestFileName: manifestFileName,
    includeDirectories: includeDirectories,
    assetMode: switch (assetMode) {
      TargetShaderBundleAssetMode.generatedTree =>
        ShaderBundleAssetMode.legacyOnly,
      TargetShaderBundleAssetMode.dataAssetsIfAvailable =>
        ShaderBundleAssetMode.dataAssetsIfAvailable,
      TargetShaderBundleAssetMode.dataAssetsRequired =>
        ShaderBundleAssetMode.dataAssetsRequired,
    },
    dataAssetName: dataAssetName,
    glesLanguageVersion: glesLanguageVersion,
  );
  final output = File.fromUri(result.outputFile);
  final bytes = trimShaderBundle(
    output.readAsBytesSync(),
    shaderBundleBackendsForBuild(buildInput),
  );
  output.writeAsBytesSync(bytes);

  if (!copyToGeneratedTree) return;

  final bundleFileName = result.outputFile.pathSegments.last;
  final id = bundleFileName.endsWith('.shaderbundle')
      ? bundleFileName.substring(
          0,
          bundleFileName.length - '.shaderbundle'.length,
        )
      : bundleFileName;
  if (emitDataAssets) {
    // A tree left by an earlier build would ship the same bundle twice.
    GeneratedAssetTree.openExisting(
        buildInput.packageRoot,
        buildInput.packageName,
      )
      ?..dropOwned(
        GeneratedAssetFamily.shaderBundle,
        owner: owner ?? buildInput.packageName,
      )
      ..save();
    return;
  }

  final tree = GeneratedAssetTree.open(
    buildInput.packageRoot,
    buildInput.packageName,
  )..requireAssetEntry();
  final copyUri = tree.fileUri(
    GeneratedAssetFamily.shaderBundle,
    nameId: id,
    extension: '.shaderbundle',
  );
  writeGeneratedBytes(copyUri, bytes);
  tree
    ..recordFile(
      family: GeneratedAssetFamily.shaderBundle,
      id: id,
      uri: copyUri,
      stamp: stamp ?? fnv1aHex(bytes),
      owner: owner,
    )
    ..save();
}

/// Returns the backend set needed by [buildInput].
Set<ShaderBundleBackend> shaderBundleBackendsForBuild(BuildInput buildInput) {
  if (!buildInput.config.buildCodeAssets) {
    return const {ShaderBundleBackend.openglEs};
  }
  final os = buildInput.config.code.targetOS;
  if (os == OS.iOS) return const {ShaderBundleBackend.metalIos};
  if (os == OS.macOS) return const {ShaderBundleBackend.metalDesktop};
  if (os == OS.fuchsia) return const {ShaderBundleBackend.vulkan};
  return const {ShaderBundleBackend.openglEs, ShaderBundleBackend.vulkan};
}

/// The leading part of a compiled bundle's build stamp, before its shader
/// sources: the format revision, the backends this target needs, and the
/// engine the bundle is being compiled for.
///
/// The engine belongs in the stamp because a shader bundle is only valid for
/// the engine that consumes it, so switching Flutter versions must recompile
/// even when every shader source is untouched. [what] names the bundle.
Future<String> shaderBundleStamp(BuildInput buildInput, String what) async =>
    'rev=$buildCacheRevision $what target=${shaderBundleTargetKey(buildInput)} '
    '${await engineIdentity()}';

/// Stable build-cache key for the selected shader backends.
String shaderBundleTargetKey(BuildInput buildInput) =>
    shaderBundleBackendsForBuild(
      buildInput,
    ).map((backend) => backend.name).join(',');

/// Rebuilds [bytes] with only [backends].
Uint8List trimShaderBundle(Uint8List bytes, Set<ShaderBundleBackend> backends) {
  final bundle = fb.ShaderBundle(bytes);
  final shaders = bundle.shaders;
  if (shaders == null) {
    throw const FormatException('Shader bundle has no shaders.');
  }
  return fb.ShaderBundleObjectBuilder(
    formatVersion: bundle.formatVersion,
    shaders: [for (final shader in shaders) _copyShader(shader, backends)],
  ).toBytes('IPSB');
}

fb.ShaderObjectBuilder _copyShader(
  fb.Shader shader,
  Set<ShaderBundleBackend> backends,
) => fb.ShaderObjectBuilder(
  name: shader.name,
  metalIos: backends.contains(ShaderBundleBackend.metalIos)
      ? _copyBackend(shader.metalIos)
      : null,
  metalDesktop: backends.contains(ShaderBundleBackend.metalDesktop)
      ? _copyBackend(shader.metalDesktop)
      : null,
  openglEs: backends.contains(ShaderBundleBackend.openglEs)
      ? _copyBackend(shader.openglEs)
      : null,
  vulkan: backends.contains(ShaderBundleBackend.vulkan)
      ? _copyBackend(shader.vulkan)
      : null,
);

fb.BackendShaderObjectBuilder? _copyBackend(fb.BackendShader? shader) {
  if (shader == null) return null;
  return fb.BackendShaderObjectBuilder(
    stage: shader.stage,
    entrypoint: shader.entrypoint,
    inputs: shader.inputs?.map(_copyInput).toList(),
    uniformStructs: shader.uniformStructs?.map(_copyUniformStruct).toList(),
    uniformTextures: shader.uniformTextures?.map(_copyUniformTexture).toList(),
    shader: shader.shader,
  );
}

fb.ShaderInputObjectBuilder _copyInput(fb.ShaderInput input) =>
    fb.ShaderInputObjectBuilder(
      name: input.name,
      location: input.location,
      $set: input.$set,
      binding: input.binding,
      type: input.type,
      bitWidth: input.bitWidth,
      vecSize: input.vecSize,
      columns: input.columns,
      offset: input.offset,
    );

fb.ShaderUniformStructObjectBuilder _copyUniformStruct(
  fb.ShaderUniformStruct uniform,
) => fb.ShaderUniformStructObjectBuilder(
  name: uniform.name,
  extRes0: uniform.extRes0,
  $set: uniform.$set,
  binding: uniform.binding,
  sizeInBytes: uniform.sizeInBytes,
  fields: uniform.fields?.map(_copyUniformField).toList(),
);

fb.ShaderUniformStructFieldObjectBuilder _copyUniformField(
  fb.ShaderUniformStructField field,
) => fb.ShaderUniformStructFieldObjectBuilder(
  name: field.name,
  type: field.type,
  offsetInBytes: field.offsetInBytes,
  elementSizeInBytes: field.elementSizeInBytes,
  totalSizeInBytes: field.totalSizeInBytes,
  arrayElements: field.arrayElements,
  vecSize: field.vecSize,
  columns: field.columns,
);

fb.ShaderUniformTextureObjectBuilder _copyUniformTexture(
  fb.ShaderUniformTexture texture,
) => fb.ShaderUniformTextureObjectBuilder(
  name: texture.name,
  extRes0: texture.extRes0,
  $set: texture.$set,
  binding: texture.binding,
);
