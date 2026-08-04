import 'dart:io';
import 'dart:typed_data';

import 'package:code_assets/code_assets.dart';
import 'package:flutter_gpu_shaders/build.dart';
import 'package:hooks/hooks.dart';

import '../gpu/web/shader_bundle_generated.dart' as fb;

/// Shader backends stored in a Flutter GPU shader bundle.
enum ShaderBundleBackend { metalIos, metalDesktop, openglEs, vulkan }

/// Controls DataAsset registration for a target-specific shader bundle.
enum TargetShaderBundleAssetMode {
  legacyOnly,
  dataAssetsIfAvailable,
  dataAssetsRequired,
}

/// Builds a shader bundle and removes backends the target cannot use.
Future<void> buildTargetShaderBundleJson({
  required BuildInput buildInput,
  required BuildOutputBuilder buildOutput,
  required String manifestFileName,
  List<Uri> includeDirectories = const [],
  TargetShaderBundleAssetMode assetMode =
      TargetShaderBundleAssetMode.legacyOnly,
  String? dataAssetName,
  int? glesLanguageVersion,
}) async {
  final result = await buildShaderBundleJson(
    buildInput: buildInput,
    buildOutput: buildOutput,
    manifestFileName: manifestFileName,
    includeDirectories: includeDirectories,
    assetMode: switch (assetMode) {
      TargetShaderBundleAssetMode.legacyOnly =>
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
  output.writeAsBytesSync(
    trimShaderBundle(
      output.readAsBytesSync(),
      shaderBundleBackendsForBuild(buildInput),
    ),
  );
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
