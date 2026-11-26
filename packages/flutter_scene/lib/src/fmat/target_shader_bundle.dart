import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:code_assets/code_assets.dart';
import 'package:data_assets/data_assets.dart';
import 'package:flutter_gpu_shaders/build.dart';
import 'package:flutter_gpu_shaders/environment.dart' show findImpellerC;
import 'package:hooks/hooks.dart';

import '../generated_assets/engine_identity.dart';
import '../generated_assets/generated_assets.dart';
import '../generated_assets/generated_file_names.dart';
import '../generated_assets/generated_tree.dart';
import '../generated_assets/tint_binary.dart' show kTintReleaseTag;
import '../generated_assets/wgsl_sidecar.dart';
import '../gpu/shared/sidecar_hash.dart';
import '../gpu/web/shader_bundle_generated.dart' as fb;
import '../importer/build_cache.dart' show buildCacheRevision;
import 'framework_shaders.dart';

export '../generated_assets/generated_assets.dart' show ShaderBundleBackend;

/// Controls where a target-specific shader bundle is published.
enum TargetShaderBundleAssetMode {
  /// Copy the trimmed bundle into the app's `flutter_scene_generated/`
  /// directory, resolvable by bundle name with `resolveShaderBundleKey`. The
  /// default, and identical on every Flutter channel.
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
///
/// [pruneGeneratedTree] drops a tree copy the data-asset registration replaces.
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
  bool pruneGeneratedTree = true,
  String? owner,
  String? stamp,
  String? fileVariant,
}) async {
  const suffix = '.shaderbundle.json';
  final fileName = Uri(path: manifestFileName).pathSegments.last;
  if (!fileName.endsWith(suffix) || fileName.length == suffix.length) {
    throw Exception(
      'Shader bundle manifest file names must end with "$suffix": '
      '$manifestFileName',
    );
  }
  final manifestUri = buildInput.packageRoot.resolve(manifestFileName);
  final manifest =
      (jsonDecode(File.fromUri(manifestUri).readAsStringSync()) as Map)
          .cast<String, Object?>();
  buildOutput.dependencies.add(manifestUri);
  await buildTargetShaderBundle(
    buildInput: buildInput,
    buildOutput: buildOutput,
    bundleName: fileName.substring(0, fileName.length - suffix.length),
    manifest: manifest,
    entryRoot: buildInput.packageRoot,
    manifestDirectory: manifestUri.resolve('./'),
    includeDirectories: includeDirectories,
    assetMode: assetMode,
    dataAssetName: dataAssetName,
    glesLanguageVersion: glesLanguageVersion,
    copyToGeneratedTree: copyToGeneratedTree,
    pruneGeneratedTree: pruneGeneratedTree,
    owner: owner,
    stamp: stamp,
    fileVariant: fileVariant,
  );
}

/// [buildTargetShaderBundleJson] over an in-memory [manifest], whose entry
/// `file` paths resolve against [entryRoot]. The compiler runs there and only
/// reads it. [manifestDirectory] heads the include path and defaults to
/// [entryRoot].
Future<void> buildTargetShaderBundle({
  required BuildInput buildInput,
  required BuildOutputBuilder buildOutput,
  required String bundleName,
  required Map<String, Object?> manifest,
  required Uri entryRoot,
  Uri? manifestDirectory,
  List<Uri> includeDirectories = const [],
  TargetShaderBundleAssetMode assetMode =
      TargetShaderBundleAssetMode.generatedTree,
  String? dataAssetName,
  int? glesLanguageVersion,
  bool copyToGeneratedTree = true,
  bool pruneGeneratedTree = true,
  String? owner,
  String? stamp,
  String? fileVariant,
}) async {
  // ignore: deprecated_member_use_from_same_package
  if (assetMode == TargetShaderBundleAssetMode.legacyOnly) {
    throwRemovedAssetMode(
      'TargetShaderBundleAssetMode.legacyOnly',
      'TargetShaderBundleAssetMode.generatedTree',
    );
  }
  // ignore: deprecated_member_use_from_same_package
  if (assetMode == TargetShaderBundleAssetMode.dataAssetsIfAvailable) {
    throwRemovedAssetMode(
      'TargetShaderBundleAssetMode.dataAssetsIfAvailable',
      'TargetShaderBundleAssetMode.generatedTree',
    );
  }
  final output = File.fromUri(shaderBundleIntermediate(buildInput, bundleName));
  final emitDataAssets =
      assetMode == TargetShaderBundleAssetMode.dataAssetsRequired;
  void registerDataAsset() => registerShaderBundleDataAsset(
    buildInput: buildInput,
    buildOutput: buildOutput,
    outputBundleFile: output.uri,
    legacyAssetKey: '$bundleName.shaderbundle',
    assetMode: ShaderBundleAssetMode.dataAssetsRequired,
    dataAssetName: dataAssetName,
  );
  // Throws the toolchain's explanation before anything compiles.
  if (emitDataAssets && !buildInput.config.buildDataAssets) registerDataAsset();

  // Compiled beside the shipped name, never trimmed in place, so a failed
  // compile leaves the last good bundle and the trim never reads its own output.
  final compiled = Uri.file('${output.path}.untrimmed');
  await _compileShaderBundle(
    buildInput: buildInput,
    buildOutput: buildOutput,
    manifest: manifest,
    entryRoot: entryRoot,
    manifestDirectory: manifestDirectory ?? entryRoot,
    outputFile: compiled,
    includeDirectories: [
      ...includeDirectories,
      // flutter_scene's own shaders/ goes last, so a raw shader can
      // `#include <scene_inputs.glsl>` (or the noise library) without the
      // caller resolving the package, and a same-named file of the caller's
      // still wins.
      await engineShaderIncludeDirectory(buildInput),
    ],
    glesLanguageVersion: glesLanguageVersion,
  );
  final untrimmed = File.fromUri(compiled).readAsBytesSync();
  final backends = shaderBundleBackendsForBuild(buildInput);
  final bytes = trimShaderBundle(untrimmed, backends);
  output.writeAsBytesSync(bytes);
  // Translated before trimming, since a web build keeps no Vulkan SPIR-V.
  final wgsl = File(wgslSidecarPathFor(output.path));
  if (wgslSidecarsForBuild(buildInput)) {
    final translator = await TintProcessTranslator.resolve(buildInput);
    wgsl.writeAsStringSync(
      await buildWgslSidecar(
        untrimmed,
        translator,
        shippedBundleHash: sidecarBundleHash(bytes),
      ),
    );
  } else if (wgsl.existsSync()) {
    wgsl.deleteSync();
  }
  if (emitDataAssets) registerDataAsset();

  if (!copyToGeneratedTree) return;

  final id = bundleName;
  if (emitDataAssets) {
    if (!pruneGeneratedTree) return;
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
  final target = shaderBundleTargetKey(buildInput);
  final variant = fileVariant ?? await engineIdentity();
  final copyUri = tree.fileUri(
    GeneratedAssetFamily.shaderBundle,
    nameId: id,
    extension: '.shaderbundle',
    variant: variant,
    target: target,
  );
  writeGeneratedBytes(copyUri, bytes);
  tree.recordFile(
    family: GeneratedAssetFamily.shaderBundle,
    id: id,
    uri: copyUri,
    stamp: stamp ?? fnv1aHex(bytes),
    owner: owner,
    target: target,
  );
  if (!wgsl.existsSync()) {
    tree.drop(GeneratedAssetFamily.wgsl, id, target: target);
  } else {
    final wgslUri = Uri.file(wgslSidecarPathFor(copyUri.toFilePath()));
    writeGeneratedBytes(wgslUri, wgsl.readAsBytesSync());
    tree.recordFile(
      family: GeneratedAssetFamily.wgsl,
      id: id,
      uri: wgslUri,
      stamp: stamp ?? fnv1aHex(bytes),
      owner: owner,
      target: target,
    );
  }
  tree.save();
}

/// A directory named [name] for this hook run's intermediates, the files that
/// never ship.
///
/// Inside the hook's own output directory, under the building app's
/// `.dart_tool/`, and never the package root. For a pub-cache dependency that
/// root is shared by every project on the machine, so builds running at once
/// would rewrite one another's inputs (on Windows, failing outright while the
/// other build's compiler has the file mapped). The invoker serializes runs
/// that share an output directory.
Uri hookIntermediateDirectory(BuildInput buildInput, String name) {
  final directory = Directory.fromUri(
    buildInput.outputDirectory.resolve('$name/'),
  )..createSync(recursive: true);
  return directory.uri;
}

/// Where [buildTargetShaderBundle] writes the trimmed [bundleName] bundle.
Uri shaderBundleIntermediate(BuildInput buildInput, String bundleName) =>
    hookIntermediateDirectory(
      buildInput,
      'shaderbundles',
    ).resolve('$bundleName.shaderbundle');

/// Runs `impellerc` over [manifest] into [outputFile] and declares the sources
/// it read as dependencies.
///
/// The compile flutter_gpu_shaders' `buildShaderBundleJson` does, which can
/// only write under the package root.
Future<void> _compileShaderBundle({
  required BuildInput buildInput,
  required BuildOutputBuilder buildOutput,
  required Map<String, Object?> manifest,
  required Uri entryRoot,
  required Uri manifestDirectory,
  required Uri outputFile,
  required List<Uri> includeDirectories,
  int? glesLanguageVersion,
}) async {
  final impellerc = await findImpellerC();
  final depfile = File('${outputFile.toFilePath()}.d');
  if (depfile.existsSync()) depfile.deleteSync();
  final useDepfile = await _impellercWritesDepfile(impellerc);
  final result = await Process.run(
    impellerc.toFilePath(),
    shaderBundleImpellercArguments(
      outputBundleFilePath: outputFile,
      manifestJson: jsonEncode(manifest),
      manifestDirectory: manifestDirectory,
      shaderLibDirectory: impellerc.resolve('./shader_lib'),
      includeDirectories: includeDirectories,
      depfilePath: useDepfile ? depfile.uri : null,
      glesLanguageVersion: glesLanguageVersion,
    ),
    workingDirectory: entryRoot.toFilePath(),
  );
  if (result.exitCode != 0) {
    throw Exception(
      'Failed to build shader bundle: ${result.stderr}\n${result.stdout}',
    );
  }
  final dependencies = [
    // The compiler is versioned with the engine, so a new one recompiles.
    impellerc,
    for (final entry in manifest.values)
      if (entry case {'file': final String file}) entryRoot.resolve(file),
    if (useDepfile && depfile.existsSync())
      ...parseImpellerCDepfileDependencies(
        depfile.readAsStringSync(),
        relativeTo: entryRoot,
      ),
  ];
  // Generated sources are rewritten on every run, so depending on them would
  // rerun the hook on every build. Whatever generated them declares the real
  // sources.
  final generated = [
    buildInput.outputDirectoryShared,
    buildInput.packageRoot.resolve('build/'),
  ].map(_comparablePath).toList();
  buildOutput.dependencies.addAll(
    dependencies.where((uri) {
      final path = _comparablePath(uri);
      return !generated.any(path.startsWith);
    }),
  );
}

String _comparablePath(Uri uri) {
  final path = uri.toFilePath(windows: false);
  return Platform.isWindows ? path.toLowerCase() : path;
}

final Map<Uri, bool> _depfileSupport = {};

Future<bool> _impellercWritesDepfile(Uri impellerc) async {
  if (_depfileSupport[impellerc] case final known?) return known;
  final help = await Process.run(impellerc.toFilePath(), ['--help']);
  return _depfileSupport[impellerc] =
      help.exitCode == 0 &&
      impellerCHelpSupportsDepfile('${help.stdout}\n${help.stderr}');
}

/// Whether [buildInput] writes WGSL sidecars: the WebGPU opt-in is on and the
/// target takes the GLES-only set, the one the web, their only reader, loads.
/// Every check for an expected sidecar goes through here, so a build that
/// never writes one does not count it missing and recompile.
bool wgslSidecarsForBuild(BuildInput buildInput) {
  if (!webGpuShadersRequested(buildInput)) return false;
  final backends = shaderBundleBackendsForBuild(buildInput);
  return backends.length == 1 &&
      backends.contains(ShaderBundleBackend.openglEs);
}

/// Returns the backend set needed by [buildInput].
///
/// A config with no code assets names no target OS, which is web and also the
/// data-asset-only invocation `flutter run` makes for a native target. Both
/// resolve to GLES, so the native one must never overwrite the target build's
/// outputs; [shaderBundleTargetKey] is what keeps them apart in the tree.
///
/// That native data-only pass still compiles a GLES set no native app loads. A
/// tree that lists its target directories (flutter_scene's own does) puts it in
/// the web-only directory, so a native app does not ship it, but the compile
/// cannot be dropped here. Its hook input is byte-identical to a real web
/// build's (both just `data_assets/data`, no code config, no target OS), and
/// web genuinely needs the GLES set, so nothing the hook can read tells the
/// wasteful native pass from the required web one. The invoker knows the target
/// platform but never puts it on a data-asset-only input.
/// `generated_target_isolation_test.dart` locks that indistinguishability.
///
/// TODO(hook-target-invocations): dropping the compile needs an upstream change,
/// the invoker naming the target platform (or final artifact) on data-asset-only
/// inputs, or flutter_tools not making the redundant native data pass. Revisit
/// if a Flutter release adds such a field.
Set<ShaderBundleBackend> shaderBundleBackendsForBuild(BuildInput buildInput) =>
    buildInput.config.buildCodeAssets
    ? shaderBundleBackendsForOS(_targetOSName(buildInput) ?? _unnamedTargetOS)
    : shaderBundleBackendsForOS(null);

/// Stands in for a code-asset config that names no target OS.
///
/// No arm claims it, so it selects the portable set, which is what an
/// unrecognized name gets. A config this malformed should not reach a hook, and
/// if one does it must not be mistaken for the unset case, which means web and
/// takes the GLES set alone.
const String _unnamedTargetOS = 'unnamed';

/// The target OS named in [buildInput]'s code-asset config, or null when no
/// string is there to read.
///
/// Read off the config JSON rather than through `config.code.targetOS`, which
/// parses the name into an `OS`. That set was closed until
/// `package:code_assets` 2.0.0, and the older versions this package still
/// supports throw on a name they do not know instead of minting one, so the
/// typed accessor turns an embedder for a platform `dart:ffi` cannot name into
/// a crashed build hook. Apple's tvOS and watchOS are two of those.
///
/// The name is a plain string in the protocol syntax on both sides, and a
/// string is all backend selection needs. Nothing here may throw on a shape it
/// did not expect, since not throwing on an unfamiliar config is the whole
/// point.
String? _targetOSName(BuildInput buildInput) {
  final extensions = buildInput.config.json['extensions'];
  final code = extensions is Map ? extensions['code_assets'] : null;
  final os = code is Map ? code['target_os'] : null;
  return os is String ? os : null;
}

/// The leading part of a compiled bundle's build stamp, before its shader
/// sources: the format revision, the backends this target needs, and the
/// engine the bundle is being compiled for.
///
/// The engine belongs in the stamp because a shader bundle is only valid for
/// the engine that consumes it, so switching Flutter versions must recompile
/// even when every shader source is untouched. [what] names the bundle. The
/// WGSL switch is in it too, so turning `flutter_scene_webgpu` on recompiles.
Future<String> shaderBundleStamp(BuildInput buildInput, String what) async =>
    'rev=$buildCacheRevision $what target=${shaderBundleTargetKey(buildInput)} '
    '${await engineIdentity()}'
    '${wgslSidecarsForBuild(buildInput) ? ' wgsl=$kTintReleaseTag' : ''}';

/// Stable build-cache key for the selected shader backends. Recorded on every
/// output that is only valid for them, and matched against
/// `currentShaderTarget` at runtime.
String shaderBundleTargetKey(BuildInput buildInput) =>
    shaderTargetKey(shaderBundleBackendsForBuild(buildInput));

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
