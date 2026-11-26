/// Builds flutter_scene's own engine assets, the base shader bundle and the
/// physical material bundle.
///
/// flutter_scene's own `hook/build.dart` calls [buildOwnEngineAssets], so a
/// consumer needs no hook of their own. It writes into flutter_scene's own
/// `flutter_scene_generated/`, one directory per target, which its pubspec
/// lists with a platform filter each. Every output is stamped
/// with the identity of the engine that compiled it, because a shader bundle is
/// only valid for that engine, so one pub cache shared by projects on different
/// Flutter versions rebuilds on each switch instead of loading a bundle the
/// engine cannot read.
///
/// [buildEngineAssets] is the app-side override: the same build, into the app's
/// own tree, from the app's hook.
///
/// The surface debug views are compiled out unless the app sets flutter_scene's
/// `debug_views` hook user-define in its pubspec (the workspace root's, in a
/// pub workspace). An app hook calling [buildEngineAssets] reads
/// `flutter_scene_debug_views` under the app's own name instead, since a hook
/// sees only its own package's defines:
///
/// ```yaml
/// hooks:
///   user_defines:
///     flutter_scene:
///       debug_views: true
///     my_app:
///       flutter_scene_debug_views: true
/// ```
///
/// `lighting_features` (`flutter_scene_lighting_features` for an app hook)
/// compiles lit features a project never uses out of every lit shader, which
/// shortens their first-draw compile (see [LightingFeature]):
///
/// ```yaml
/// hooks:
///   user_defines:
///     flutter_scene:
///       lighting_features:
///         irradiance_field: false
///         rect_area_lights: false
/// ```
library;

import 'dart:convert';
import 'dart:io';

import 'package:hooks/hooks.dart';

import '../fmat/build_materials.dart'
    show MaterialAssetMode, buildBundledPhysicalMaterials;
import '../fmat/framework_shaders.dart';
import '../fmat/target_shader_bundle.dart';
import '../importer/build_cache.dart';
import 'engine_identity.dart';
import 'generated_assets.dart';
import 'generated_tree.dart';
import 'lighting_features.dart';
import 'wgsl_sidecar.dart' show wgslSidecarPathFor;

/// The package flutter_scene's engine assets are recorded as belonging to.
const String _engineOwner = 'flutter_scene';

/// The manifest of the engine's shader bundle, relative to flutter_scene's root.
const String _baseBundleManifest = 'shaders/base.shaderbundle.json';

/// GLSL ES 3.00 for the OpenGL ES dialect. The radiance sampling uses
/// textureLod, which is core in 300 es; the 1.00 form needs
/// GL_EXT_shader_texture_lod, which software GL stacks (Mesa llvmpipe, Android
/// emulators) reject at compile time. Sets the native GLES floor at OpenGL
/// ES 3.0.
const int engineGlesLanguageVersion = 300;

/// Builds the engine's shaders from flutter_scene's own hook into its own
/// generated tree.
///
/// Always the tree, even when the toolchain has data assets. One build runs
/// this hook several times, and only some runs carry data assets, so a run
/// without them would write the tree anyway and the app would ship both
/// copies. Nothing a run can read says whether another run in the same build
/// registers data assets.
Future<void> buildOwnEngineAssets({
  required BuildInput buildInput,
  required BuildOutputBuilder buildOutput,
}) => _build(
  buildInput: buildInput,
  buildOutput: buildOutput,
  options: HookOptions.of(buildInput),
);

/// Builds the engine's shaders into the app's generated tree, from the app's
/// `hook/build.dart` (which `dart run flutter_scene:init` writes for you).
///
/// Optional. flutter_scene's own hook already builds them; this puts the
/// outputs in the app's tree instead, which is what an app wants when it
/// prefers to own every generated asset it ships.
///
/// [debugViews] compiles the surface debug views in. It defaults to the app's
/// `flutter_scene_debug_views` hook user-define, since an app hook cannot read
/// flutter_scene's own.
Future<void> buildEngineAssets({
  required BuildInput buildInput,
  required BuildOutputBuilder buildOutput,
  bool? debugViews,
}) => _build(
  buildInput: buildInput,
  buildOutput: buildOutput,
  options: HookOptions(
    debugViews: debugViews ?? HookOptions.of(buildInput).debugViews,
    compiledOutLightingFeatures: HookOptions.of(
      buildInput,
    ).compiledOutLightingFeatures,
  ),
);

Future<void> _build({
  required BuildInput buildInput,
  required BuildOutputBuilder buildOutput,
  required HookOptions options,
}) async {
  final debugViews = options.debugViews;
  final lightingOff = options.compiledOutLightingFeatures;
  // flutter_scene's own root, the parent of its shader include directory.
  final root = (await engineShaderIncludeDirectory(buildInput)).resolve('../');
  await _buildBaseShaderBundle(
    buildInput: buildInput,
    buildOutput: buildOutput,
    sourceRoot: root,
    debugViews: debugViews,
    lightingOff: lightingOff,
  );
  await buildBundledPhysicalMaterials(
    buildInput: buildInput,
    buildOutput: buildOutput,
    sourceRoot: root,
    owner: _engineOwner,
    assetMode: MaterialAssetMode.generatedTree,
    // Engine-compiled like the base bundle, so its name separates engines too.
    fileVariant: await engineIdentity(),
    debugViews: debugViews,
    compiledOutLightingFeatures: lightingOff,
  );
}

Future<void> _buildBaseShaderBundle({
  required BuildInput buildInput,
  required BuildOutputBuilder buildOutput,
  required Uri sourceRoot,
  required bool debugViews,
  required Set<LightingFeature> lightingOff,
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
    await shaderBundleStamp(
      buildInput,
      // Names the views' layout, so a bundle with them compiled into every
      // entry is rebuilt with twins.
      'engine bundle=base debug_views=${debugViews ? 'twins' : false} '
      'lighting_off=${describeCompiledOutLightingFeatures(lightingOff)}',
    ),
  );
  for (final file in sources) {
    stampBuffer.write(
      ' ${file.uri.pathSegments.last}='
      '${sourceFingerprint(file, strict: options.strictHashing)}',
    );
  }
  final stamp = stampBuffer.toString();

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
  final variant =
      '${await engineIdentity()}'
      '${debugViews ? debugViewsVariantSuffix : ''}'
      '${lightingFeaturesVariantSuffix(lightingOff)}';
  final outputUri = tree.fileUri(
    GeneratedAssetFamily.shaderBundle,
    nameId: 'base',
    extension: '.shaderbundle',
    variant: variant,
    target: target,
  );
  final wgslUri = wgslSidecarsForBuild(buildInput)
      ? Uri.file(wgslSidecarPathFor(outputUri.toFilePath()))
      : null;
  if (tree.isFresh(GeneratedAssetFamily.shaderBundle, 'base', stamp, [
    outputUri,
    ?wgslUri,
  ], target: target)) {
    tree.recordFile(
      family: GeneratedAssetFamily.shaderBundle,
      id: 'base',
      uri: outputUri,
      stamp: stamp,
      owner: _engineOwner,
      target: target,
    );
    // Recorded again too, or the sweep in save() deletes it; dropped when the
    // switch is off, or a recorded sidecar outlives it.
    if (wgslUri == null) {
      tree.drop(GeneratedAssetFamily.wgsl, 'base', target: target);
    } else if (File.fromUri(wgslUri).existsSync()) {
      tree.recordFile(
        family: GeneratedAssetFamily.wgsl,
        id: 'base',
        uri: wgslUri,
        stamp: stamp,
        owner: _engineOwner,
        target: target,
      );
    }
    tree.save();
    return;
  }

  // The compiler resolves a manifest entry's `file` against its working
  // directory, which it only reads: flutter_scene's own root, or the directory
  // of the debug-view wrappers.
  var manifest = (jsonDecode(manifestFile.readAsStringSync()) as Map)
      .cast<String, Object?>();
  var entryRoot = sourceRoot;
  if (debugViews || lightingOff.isNotEmpty) {
    entryRoot = hookIntermediateDirectory(buildInput, 'engine_entries');
    manifest = wrapEngineManifest(
      manifest,
      entryRoot,
      shaders,
      debugViews: debugViews,
      lightingOff: lightingOff,
    );
  }
  buildOutput.dependencies.add(manifestFile.uri);

  stdout.writeln('flutter_scene: compiling the engine shader bundle');
  await buildTargetShaderBundle(
    buildInput: buildInput,
    buildOutput: buildOutput,
    bundleName: 'base',
    manifest: manifest,
    entryRoot: entryRoot,
    manifestDirectory: shaders,
    includeDirectories: [shaders],
    glesLanguageVersion: engineGlesLanguageVersion,
    assetMode: TargetShaderBundleAssetMode.generatedTree,
    owner: _engineOwner,
    stamp: stamp,
    fileVariant: variant,
  );
}

/// Points every entry of [manifest] at a wrapper written into [directory],
/// which entries then resolve against.
///
/// With [debugViews], adds a twin of each fragment entry that draws the
/// surface debug views, named with [debugViewsEntrySuffix] and defining
/// `FLUTTER_SCENE_DEBUG_VIEWS`. A material draws with the twin only while a
/// view is active, so the views cost nothing to compile until then.
///
/// Every wrapper defines each feature in [lightingOff] out, and each one gets
/// a marker entry ([LightingFeature.markerEntryName]) the runtime reads back.
///
/// Every wrapper includes its original by name, found through [shaders] on the
/// include path, since the compiler takes no defines per bundle. A wrapper
/// keeps a different name from its original, or the include would find the
/// wrapper itself.
Map<String, Object?> wrapEngineManifest(
  Map<String, Object?> manifest,
  Uri directory,
  Uri shaders, {
  bool debugViews = false,
  Set<LightingFeature> lightingOff = const {},
}) {
  final prefix = [
    for (final f in LightingFeature.values)
      if (lightingOff.contains(f)) '#define ${f.define}\n',
  ].join();
  final wrapped = <String, Object?>{};
  for (final MapEntry(:key, :value) in manifest.entries) {
    final entry = (value as Map).cast<String, Object?>();
    final original = (entry['file'] as String).split('/').last;
    final dot = original.lastIndexOf('.');
    String wrap(String suffix, String defines) {
      final name =
          '${original.substring(0, dot)}$suffix${original.substring(dot)}';
      File.fromUri(
        directory.resolve(name),
      ).writeAsStringSync('$prefix$defines#include <$original>\n');
      return name;
    }

    wrapped[key] = {...entry, 'file': wrap('_entry', '')};
    if (debugViews &&
        entry['type'] == 'fragment' &&
        _includesDebugViews(File.fromUri(shaders.resolve(original)), shaders)) {
      wrapped['$key$debugViewsEntrySuffix'] = {
        ...entry,
        'file': wrap('_debug_views', '#define FLUTTER_SCENE_DEBUG_VIEWS\n'),
      };
    }
  }
  for (final feature in lightingOff) {
    final name = '${feature.markerEntryName}.frag';
    File.fromUri(directory.resolve(name)).writeAsStringSync(
      '// Records that ${feature.key} was compiled out. Never drawn.\n'
      'precision mediump float;\n'
      'out vec4 frag_color;\n'
      'void main() {\n  frag_color = vec4(0.0);\n}\n',
    );
    wrapped[feature.markerEntryName] = {'type': 'fragment', 'file': name};
  }
  return wrapped;
}

final RegExp _include = RegExp(
  r'^\s*#\s*include\s*[<"]([^>"]+)[>"]',
  multiLine: true,
);

// Whether [file] includes the surface debug hook, directly or through its
// includes, each resolved beside its includer and then in [shaders].
bool _includesDebugViews(File file, Uri shaders, [Set<String>? seen]) {
  seen ??= {};
  if (!seen.add(file.absolute.path) || !file.existsSync()) return false;
  for (final match in _include.allMatches(file.readAsStringSync())) {
    final name = match.group(1)!;
    if (name.split('/').last == 'material_debug.glsl') return true;
    final beside = File.fromUri(file.uri.resolve(name));
    final included = beside.existsSync()
        ? beside
        : File.fromUri(shaders.resolve(name));
    if (_includesDebugViews(included, shaders, seen)) return true;
  }
  return false;
}
