/// Builds flutter_scene's own engine assets (the base shader bundle and the
/// physical material bundle) into the app's generated tree.
///
/// These are compiled outputs tied to the Flutter engine that built them, so
/// flutter_scene cannot ship them prebuilt, and it cannot write them into its
/// own directory either (that directory is published to pub.dev and shared
/// across every project through the pub cache). The app's hook therefore builds
/// them from flutter_scene's committed GLSL and `.fmat` sources into the app's
/// own `flutter_scene_generated/`.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:hooks/hooks.dart';

import '../fmat/build_materials.dart' show buildBundledPhysicalMaterials;
import '../fmat/target_shader_bundle.dart';
import '../importer/build_cache.dart';
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

/// Builds the engine assets flutter_scene needs at runtime into the app's
/// generated tree. Call this from the app's `hook/build.dart` (which
/// `dart run flutter_scene:init` writes for you).
///
/// Without this, `Scene.initializeStaticResources` has no shaders to load and
/// nothing renders.
Future<void> buildEngineAssets({
  required BuildInput buildInput,
  required BuildOutputBuilder buildOutput,
}) async {
  final root = await _flutterSceneRoot();
  await _buildBaseShaderBundle(
    buildInput: buildInput,
    buildOutput: buildOutput,
    sourceRoot: root,
  );
  await buildBundledPhysicalMaterials(
    buildInput: buildInput,
    buildOutput: buildOutput,
    sourceRoot: root,
    owner: _engineOwner,
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

  final stampBuffer = StringBuffer(
    'rev=$buildCacheRevision engine bundle=base '
    'target=${shaderBundleTargetKey(buildInput)}',
  );
  for (final file in sources) {
    stampBuffer.write(
      ' ${file.uri.pathSegments.last}=${contentHash(file.readAsBytesSync())}',
    );
  }
  final stamp = stampBuffer.toString();

  final tree = GeneratedAssetTree.open(
    buildInput.packageRoot,
    buildInput.packageName,
  )..requireAssetEntry();
  final outputUri = tree.fileUri(
    GeneratedAssetFamily.shaderBundle,
    nameId: 'base',
    extension: '.shaderbundle',
  );
  if (tree.isFresh(GeneratedAssetFamily.shaderBundle, 'base', stamp, [
    outputUri,
  ])) {
    tree
      ..recordFile(
        family: GeneratedAssetFamily.shaderBundle,
        id: 'base',
        uri: outputUri,
        stamp: stamp,
        owner: _engineOwner,
      )
      ..save();
    return;
  }

  // The compiler resolves a manifest entry's `file` against its own working
  // directory, which is the app's root, so rewrite flutter_scene's relative
  // entries to absolute paths and compile that copy.
  final manifest = (jsonDecode(manifestFile.readAsStringSync()) as Map)
      .cast<String, Object?>();
  final rebased = <String, Object?>{
    for (final MapEntry(:key, :value) in manifest.entries)
      key: {
        ...(value as Map).cast<String, Object?>(),
        'file': sourceRoot
            .resolve((value['file'] as String))
            .toFilePath(windows: false),
      },
  };
  final rebasedPath = 'build/flutter_scene_engine/base.shaderbundle.json';
  final rebasedFile = File.fromUri(buildInput.packageRoot.resolve(rebasedPath));
  rebasedFile.parent.createSync(recursive: true);
  rebasedFile.writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(rebased),
  );

  stdout.writeln('flutter_scene: compiling the engine shader bundle');
  await buildTargetShaderBundleJson(
    buildInput: buildInput,
    buildOutput: buildOutput,
    manifestFileName: rebasedPath,
    includeDirectories: [shaders],
    glesLanguageVersion: _glesLanguageVersion,
    owner: _engineOwner,
    stamp: stamp,
  );
}
