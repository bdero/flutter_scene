/// Builds flutter_scene's own engine assets, the base shader bundle and the
/// physical material bundle.
///
/// flutter_scene's own `hook/build.dart` calls [buildOwnEngineAssets], so a
/// consumer needs no hook of their own. It registers data assets where the
/// toolchain has them, and otherwise writes into flutter_scene's own
/// `flutter_scene_generated/`, which its pubspec lists. Every output is stamped
/// with the identity of the engine that compiled it, because a shader bundle is
/// only valid for that engine, so one pub cache shared by projects on different
/// Flutter versions rebuilds on each switch instead of loading a bundle the
/// engine cannot read.
///
/// [buildEngineAssets] is the app-side override: the same build, into the app's
/// own tree, from the app's hook.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:data_assets/data_assets.dart';
import 'package:hooks/hooks.dart';

import '../fmat/build_materials.dart'
    show MaterialAssetMode, buildBundledPhysicalMaterials;
import '../fmat/target_shader_bundle.dart';
import '../importer/build_cache.dart';
import 'engine_identity.dart';
import 'generated_assets.dart';
import 'generated_tree.dart';

/// The package flutter_scene's engine assets are recorded as belonging to.
const String _engineOwner = 'flutter_scene';

/// The manifest of the engine's shader bundle, relative to flutter_scene's root.
const String _baseBundleManifest = 'shaders/base.shaderbundle.json';

/// GLSL ES 3.00 for the OpenGL ES dialect. The radiance sampling uses
/// textureLod, which is core in 300 es; the 1.00 form needs
/// GL_EXT_shader_texture_lod, which software GL stacks (Mesa llvmpipe, Android
/// emulators) reject at compile time. Sets the native GLES floor at OpenGL
/// ES 3.0.
const int _glesLanguageVersion = 300;

/// Builds the engine's shaders from flutter_scene's own hook, into whichever
/// place this toolchain can ship them from.
Future<void> buildOwnEngineAssets({
  required BuildInput buildInput,
  required BuildOutputBuilder buildOutput,
}) => _build(
  buildInput: buildInput,
  buildOutput: buildOutput,
  // Data assets are the tidiest home when they exist, no writes into the
  // package directory at all. One build runs this hook several times with
  // different asset types though, so a run that has them must not delete the
  // tree copy a run without them wrote.
  dataAssets: buildInput.config.buildDataAssets,
  prune: false,
);

/// Builds the engine's shaders into the app's generated tree, from the app's
/// `hook/build.dart` (which `dart run flutter_scene:init` writes for you).
///
/// Optional. flutter_scene's own hook already builds them; this puts the
/// outputs in the app's tree instead, which is what an app wants when it
/// prefers to own every generated asset it ships.
Future<void> buildEngineAssets({
  required BuildInput buildInput,
  required BuildOutputBuilder buildOutput,
}) =>
    _build(buildInput: buildInput, buildOutput: buildOutput, dataAssets: false);

Future<void> _build({
  required BuildInput buildInput,
  required BuildOutputBuilder buildOutput,
  required bool dataAssets,
  bool prune = true,
}) async {
  final root = await _flutterSceneRoot();
  await _buildBaseShaderBundle(
    buildInput: buildInput,
    buildOutput: buildOutput,
    sourceRoot: root,
    dataAssets: dataAssets,
    prune: prune,
  );
  await buildBundledPhysicalMaterials(
    buildInput: buildInput,
    buildOutput: buildOutput,
    sourceRoot: root,
    owner: _engineOwner,
    assetMode: dataAssets
        ? MaterialAssetMode.dataAssetsRequired
        : MaterialAssetMode.generatedTree,
    pruneGeneratedTree: prune,
    // Engine-compiled like the base bundle, so its name separates engines too.
    fileVariant: await engineIdentity(),
  );
}

/// flutter_scene's package root. There is no top-level `flutter_scene.dart`
/// library, so this resolves through `build_hooks.dart` (which always exists).
Future<Uri> _flutterSceneRoot() async {
  final lib = await Isolate.resolvePackageUri(
    Uri.parse('package:flutter_scene/build_hooks.dart'),
  );
  if (lib == null) {
    throw Exception(
      'flutter_scene: could not resolve the flutter_scene package location.',
    );
  }
  return lib.resolve('../');
}

Future<void> _buildBaseShaderBundle({
  required BuildInput buildInput,
  required BuildOutputBuilder buildOutput,
  required Uri sourceRoot,
  required bool dataAssets,
  required bool prune,
}) async {
  final shaders = sourceRoot.resolve('shaders/');
  final manifestFile = File.fromUri(sourceRoot.resolve(_baseBundleManifest));
  if (!manifestFile.existsSync()) {
    throw Exception(
      'flutter_scene: the engine shader manifest is missing at '
      '${manifestFile.path}.',
    );
  }

  // Every framework GLSL file is an input, since the entries `#include` each
  // other and the manifest names only the entry points. They are small, so
  // hashing all of them is cheaper than tracking includes.
  final sources =
      Directory.fromUri(
          shaders,
        ).listSync(followLinks: false).whereType<File>().toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  for (final file in sources) {
    buildOutput.dependencies.add(file.uri);
  }

  final options = HookOptions.of(buildInput);
  final stampBuffer = StringBuffer(
    await shaderBundleStamp(buildInput, 'engine bundle=base'),
  );
  for (final file in sources) {
    stampBuffer.write(
      ' ${file.uri.pathSegments.last}='
      '${sourceFingerprint(file, strict: options.strictHashing)}',
    );
  }
  final stamp = stampBuffer.toString();

  final assetMode = dataAssets
      ? TargetShaderBundleAssetMode.dataAssetsRequired
      : TargetShaderBundleAssetMode.generatedTree;
  if (!dataAssets) {
    final tree = GeneratedAssetTree.open(
      buildInput.packageRoot,
      buildInput.packageName,
      options: options,
    )..requireAssetEntry();
    // The compiled bundle is valid only for the engine that produced it and
    // only for the backends it was trimmed to, so both are part of the file
    // name. Builds on different Flutter versions, or for different platforms,
    // sharing this directory then write different files instead of racing on
    // one, and the sweep drops the one no longer named by the manifest.
    final target = shaderBundleTargetKey(buildInput);
    final outputUri = tree.fileUri(
      GeneratedAssetFamily.shaderBundle,
      nameId: 'base',
      extension: '.shaderbundle',
      variant: await engineIdentity(),
      target: target,
    );
    if (tree.isFresh(GeneratedAssetFamily.shaderBundle, 'base', stamp, [
      outputUri,
    ], target: target)) {
      tree
        ..recordFile(
          family: GeneratedAssetFamily.shaderBundle,
          id: 'base',
          uri: outputUri,
          stamp: stamp,
          owner: _engineOwner,
          target: target,
        )
        ..save();
      return;
    }
  }

  // The compiler resolves a manifest entry's `file` against its own working
  // directory, the building package's root. That is flutter_scene's own root
  // for its own hook; an app's hook building these needs the entries rebased to
  // absolute paths first.
  var manifestPath = _baseBundleManifest;
  if (buildInput.packageRoot != sourceRoot) {
    final rebased = rebaseShaderBundleManifest(
      (jsonDecode(manifestFile.readAsStringSync()) as Map)
          .cast<String, Object?>(),
      sourceRoot,
      packageRoot: buildInput.packageRoot,
    );
    manifestPath = 'build/flutter_scene_engine/base.shaderbundle.json';
    final rebasedFile = File.fromUri(
      buildInput.packageRoot.resolve(manifestPath),
    );
    guardGeneratedWrite(rebasedFile.uri, () {
      rebasedFile.parent.createSync(recursive: true);
    });
    writeGeneratedString(
      rebasedFile.uri,
      const JsonEncoder.withIndent('  ').convert(rebased),
    );
  }

  stdout.writeln('flutter_scene: compiling the engine shader bundle');
  await buildTargetShaderBundleJson(
    buildInput: buildInput,
    buildOutput: buildOutput,
    manifestFileName: manifestPath,
    includeDirectories: [shaders],
    glesLanguageVersion: _glesLanguageVersion,
    assetMode: assetMode,
    pruneGeneratedTree: prune,
    owner: _engineOwner,
    stamp: stamp,
    fileVariant: await engineIdentity(),
  );
}

/// Rewrites a shader-bundle manifest's `file` entries so they resolve from
/// [packageRoot], for a hook whose working directory is a different package
/// from the [sourceRoot] holding the sources.
///
/// Entries stay relative, because they have two consumers that want opposite
/// things from an absolute path. The compiler opens the value as a path, so it
/// would need the host's own separators, while `collectShaderBundleDependencies`
/// feeds it to `Uri.resolve`, where a Windows path's drive letter parses as a
/// scheme. A relative path with posix separators is correct for both on every
/// platform. Falls back to a file URI when no relative path exists, which on
/// Windows means the two roots are on different drives.
Map<String, Object?> rebaseShaderBundleManifest(
  Map<String, Object?> manifest,
  Uri sourceRoot, {
  required Uri packageRoot,
}) => <String, Object?>{
  for (final MapEntry(:key, :value) in manifest.entries)
    key: {
      ...(value as Map).cast<String, Object?>(),
      'file': _relativeFile(
        sourceRoot.resolve(value['file'] as String),
        packageRoot,
      ),
    },
};

String _relativeFile(Uri file, Uri from) {
  final target = file.pathSegments;
  final base = from.pathSegments.where((s) => s.isNotEmpty).toList();
  // Only a genuinely different root has no relative path. Sharing no first
  // directory is an ordinary posix layout (a workdir and a pub cache under
  // different top-level directories) that walks up fine.
  if (file.scheme != from.scheme || _drive(target) != _drive(base)) {
    return file.toString();
  }
  var common = 0;
  while (common < base.length &&
      common < target.length - 1 &&
      base[common] == target[common]) {
    common++;
  }
  return [
    ...List.filled(base.length - common, '..'),
    ...target.sublist(common),
  ].join('/');
}

/// The `C:` of a Windows file URI's segments, or null for a posix path.
String? _drive(List<String> segments) {
  final first = segments.where((s) => s.isNotEmpty).firstOrNull;
  if (first == null || first.length != 2 || !first.endsWith(':')) return null;
  final letter = first.codeUnitAt(0) | 0x20;
  if (letter < 0x61 || letter > 0x7a) return null;
  return String.fromCharCode(letter);
}
