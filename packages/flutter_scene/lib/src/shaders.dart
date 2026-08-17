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
    throw Exception(baseShaderBundleMissingMessage);
  }
  final lib = await gpu.loadShaderLibraryAsync(key);
  if (lib == null) {
    throw Exception(baseShaderBundleLoadFailureMessage(key));
  }
  _baseShaderLibrary = lib;
}

/// Nothing built the bundle at all, which means flutter_scene's own build hook
/// did not run.
@visibleForTesting
const String baseShaderBundleMissingMessage =
    'The engine shader bundle is missing. flutter_scene\'s build hook compiles '
    'it during the build, so this is a build that ran without hooks. Rebuild '
    'with a Flutter version that runs package build hooks, and clean the build '
    'directory if the app was built before.';

@visibleForTesting
String baseShaderBundleLoadFailureMessage(String key) =>
    'Failed to load the engine shader bundle ($key). It is compiled for the '
    'engine that built the app, so rebuild after changing Flutter versions. '
    'A clean build ($generatedAssetsEntry and the app bundle) resolves a stale '
    'copy.';
