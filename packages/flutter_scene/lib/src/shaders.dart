import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart'
    show AssetBundle, AssetManifest, rootBundle;
import 'package:flutter_scene/src/generated_assets/generated_asset_lookup.dart';
import 'package:flutter_scene/src/generated_assets/generated_assets.dart';
import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;

/// The key flutter_scene's own hook registers when the toolchain has Dart data
/// assets. Follows `flutter_gpu_shaders`' data-asset naming; a test guards the
/// two against drifting apart.
const String _kBaseShaderBundleDataAssetPath =
    'packages/flutter_scene/flutter_gpu_shaders/shaderbundles/base.shaderbundle';

gpu.ShaderLibrary? _baseShaderLibrary;

/// The shader bundle shipped with `flutter_scene`.
///
/// Contains the vertex and fragment shaders used by the built-in
/// geometries (`UnskinnedVertex`, `SkinnedVertex`) and materials
/// (`StandardFragment`, `UnlitFragment`). Custom [Geometry] or [Material]
/// subclasses can pull additional shaders from this library.
///
/// Reading a shader bundle from an asset is asynchronous on every backend,
/// so the bundle must be loaded ahead of time by awaiting
/// [Scene.initializeStaticResources] (which calls [loadBaseShaderLibrary]);
/// accessing this getter before that completes throws.
/// {@category Assets and loading}
gpu.ShaderLibrary get baseShaderLibrary {
  final cached = _baseShaderLibrary;
  if (cached == null) {
    throw Exception(
      'The base shader bundle has not been loaded yet. Await '
      'Scene.initializeStaticResources() before constructing geometry or '
      'materials that touch the base shader library.',
    );
  }
  return cached;
}

/// Resolves the asset key the base shader bundle shipped under: the data asset
/// when the toolchain registered one, then the app's own generated tree, then
/// flutter_scene's, which its own hook always fills.
@visibleForTesting
Future<String?> resolveBaseShaderBundleKey({AssetBundle? bundle}) async {
  try {
    final manifest = await AssetManifest.loadFromAssetBundle(
      bundle ?? rootBundle,
    );
    if (manifest.listAssets().contains(_kBaseShaderBundleDataAssetPath)) {
      return _kBaseShaderBundleDataAssetPath;
    }
  } catch (_) {
    // Nothing to scan; the generated trees below are the only source.
  }
  return (await loadGeneratedAssetIndex(bundle)).resolveFirstKey(
    GeneratedAssetFamily.shaderBundle,
    'base',
    package: 'flutter_scene',
  );
}

/// Asynchronously loads and caches the base shader bundle. Idempotent.
/// Called by [Scene.initializeStaticResources] so the synchronous
/// [baseShaderLibrary] getter has a cached library to return (shader assets
/// can't be read synchronously on any backend).
/// {@category Assets and loading}
Future<void> loadBaseShaderLibrary() async {
  if (_baseShaderLibrary != null) {
    return;
  }
  final key = await resolveBaseShaderBundleKey();
  if (key == null) {
    final built = (await loadGeneratedAssetIndex()).targetsOf(
      GeneratedAssetFamily.shaderBundle,
      'base',
      package: 'flutter_scene',
    );
    throw Exception(
      built.isEmpty
          ? baseShaderBundleMissingMessage
          : baseShaderBundleWrongTargetMessage(built),
    );
  }
  final lib = await gpu.loadShaderLibraryAsync(key);
  if (lib == null) {
    throw Exception(baseShaderBundleLoadFailureMessage(key));
  }
  // A bundle the engine cannot unpack still loads; every lookup in it just
  // returns null, which without this check leaves the scene "ready" and drawing
  // nothing. Probe one shader that is always present.
  if (lib[baseShaderBundleProbeName] == null) {
    throw Exception(baseShaderBundleUnusableMessage(key));
  }
  _baseShaderLibrary = lib;
}

/// A base-bundle entry every build contains, used to tell a bundle this engine
/// can read from one it cannot.
@visibleForTesting
const String baseShaderBundleProbeName = 'UnskinnedVertex';

/// Nothing built the bundle at all, which means flutter_scene's own build hook
/// did not run.
@visibleForTesting
const String baseShaderBundleMissingMessage =
    'The engine shader bundle is missing. flutter_scene\'s build hook compiles '
    'it during the build, so this is a build that ran without hooks. Rebuild '
    'with a Flutter version that runs package build hooks, and clean the build '
    'directory if the app was built before.';

/// The bundle was built, but only for other platforms. A tree shared by builds
/// for several platforms (the pub cache is shared by every project on the
/// machine) holds one bundle per target, and none of them is this one.
@visibleForTesting
String baseShaderBundleWrongTargetMessage(List<String> built) =>
    'The engine shader bundle was trimmed for ${built.join(', ')}, but this '
    'app runs on $currentShaderTarget, and a bundle trimmed to one set of '
    'backends cannot be read by another. The build that should have produced it '
    'did not run or did not finish. Rebuild the app, and delete '
    '$generatedAssetsEntry first if it was written by an older flutter_scene.';

/// The bundle loaded, but this engine cannot unpack anything in it, which the
/// engine also reports per lookup as `Failed to unpack shader "..." from
/// bundle`.
@visibleForTesting
String baseShaderBundleUnusableMessage(String key) =>
    'The engine shader bundle ($key) loaded but holds no shader this build can '
    'read, so every draw would silently produce nothing. Two things cause '
    'that. The build trims every bundle to the backends its target needs, and '
    'this one was trimmed for a different target than the one running (this '
    'app needs $currentShaderTarget), which happens when one '
    '$generatedAssetsEntry tree is shared by builds for different platforms. '
    'Or it was compiled by a different Flutter engine, which the bundle format '
    'is tied to. Both are fixed by rebuilding, so run `flutter clean`, delete '
    '$generatedAssetsEntry, and build again.';

@visibleForTesting
String baseShaderBundleLoadFailureMessage(String key) =>
    'Failed to load the engine shader bundle ($key). It is compiled for the '
    'engine that built the app, so rebuild after changing Flutter versions. '
    'A clean build ($generatedAssetsEntry and the app bundle) resolves a stale '
    'copy.';
