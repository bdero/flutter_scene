import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart'
    show AssetBundle, AssetManifest, rootBundle;
import 'package:flutter_scene/src/generated_assets/generated_asset_lookup.dart';
import 'package:flutter_scene/src/generated_assets/generated_assets.dart';
import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;

/// The bundle's key when a package listed it as a plain pubspec asset. Kept as a
/// last resort so an app with no asset manifest still resolves something.
const String _kBaseShaderBundlePath =
    'packages/flutter_scene/build/shaderbundles/base.shaderbundle';

/// The key `buildEngineAssets` registers when the app opted into Dart data
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

/// Resolves the asset key the base shader bundle shipped under: a data-asset
/// registration when the app opted into one, then the app's generated tree.
@visibleForTesting
Future<String> resolveBaseShaderBundleKey({AssetBundle? bundle}) async {
  try {
    final manifest = await AssetManifest.loadFromAssetBundle(
      bundle ?? rootBundle,
    );
    if (manifest.listAssets().contains(_kBaseShaderBundleDataAssetPath)) {
      return _kBaseShaderBundleDataAssetPath;
    }
  } catch (_) {
    // Fall through to the generated tree, then to the pubspec-asset key.
  }
  final generated = (await loadGeneratedAssetIndex(bundle)).resolveKey(
    GeneratedAssetFamily.shaderBundle,
    'base',
    package: 'flutter_scene',
  );
  return generated ?? _kBaseShaderBundlePath;
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
  final lib = await gpu.loadShaderLibraryAsync(key);
  if (lib == null) {
    throw Exception(baseShaderBundleLoadFailureMessage(key));
  }
  _baseShaderLibrary = lib;
}

@visibleForTesting
String baseShaderBundleLoadFailureMessage(String key) =>
    'Failed to load the engine shader bundle ($key). The app\'s '
    'hook/build.dart must call buildEngineAssets, which compiles it into '
    '$generatedAssetsEntry. Run `dart run flutter_scene:init` in the app to '
    'install the hook and list that directory, then rebuild.';
