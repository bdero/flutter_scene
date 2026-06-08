import 'package:flutter/services.dart';

import '../fscene/realize/component_codec.dart';
import '../fscene/realize/loader.dart';
import '../node.dart';
import 'model_cache.dart';

const String _sceneAssetMarker = 'flutter_scene/scene/';
const String _sceneAssetSuffix = '.fsceneb';

/// Resolves and loads `.fsceneb` scene packages registered through DataAssets
/// by the [buildScenes] build hook.
///
/// Scenes are keyed by their source path relative to the owning package's root
/// (for example `assets/levels/forest.glb`), so two scenes that share a file
/// name in different directories do not collide. This is the `.fscene`
/// counterpart of `ModelEntry`.
final class SceneEntry {
  SceneEntry({
    required this.assetKey,
    required this.package,
    required this.sceneId,
  });

  /// The full Flutter asset-bundle key, e.g.
  /// `packages/<package>/flutter_scene/scene/assets/forest.fsceneb`.
  final String assetKey;

  /// The owning package.
  final String package;

  /// The source path relative to [package]'s root, without extension.
  final String sceneId;

  static SceneEntry? tryParse(String assetKey) {
    if (!SceneRegistry.isSceneAssetKey(assetKey)) return null;
    final rest = assetKey.substring('packages/'.length);
    final slash = rest.indexOf('/');
    if (slash < 0) return null;
    final package = rest.substring(0, slash);
    final afterPackage = rest.substring(slash + 1);
    if (!afterPackage.startsWith(_sceneAssetMarker)) return null;
    final relativeScenePath = afterPackage.substring(_sceneAssetMarker.length);
    final sceneId = relativeScenePath.substring(
      0,
      relativeScenePath.length - _sceneAssetSuffix.length,
    );
    return SceneEntry(assetKey: assetKey, package: package, sceneId: sceneId);
  }
}

/// Resolves DataAssets-backed `.fsceneb` files by source path, the `.fscene`
/// counterpart of `ModelRegistry`.
final class SceneRegistry {
  SceneRegistry._(this._entries);

  final List<SceneEntry> _entries;

  // A node-template cache (the same one [ModelRegistry] uses for `.model`):
  // the first load of a key realizes the scene and caches the template; every
  // load returns a fresh [Node.clone] sharing the GPU resources.
  static final ModelImportCache _cache = ModelImportCache();

  /// Loads the registry by scanning the asset manifest for `.fsceneb`
  /// DataAssets.
  static Future<SceneRegistry> load({
    AssetBundle? bundle,
    Iterable<String>? assetKeys,
  }) async {
    final assetBundle = bundle ?? rootBundle;
    final keys = assetKeys ?? await _loadAssetManifestKeys(assetBundle);
    final entries =
        keys.map(SceneEntry.tryParse).whereType<SceneEntry>().toList()
          ..sort((a, b) => a.assetKey.compareTo(b.assetKey));
    return SceneRegistry._(entries);
  }

  /// Returns true when [assetKey] is a generated `.fsceneb` DataAsset.
  static bool isSceneAssetKey(String assetKey) =>
      assetKey.startsWith('packages/') &&
      assetKey.contains('/$_sceneAssetMarker') &&
      assetKey.endsWith(_sceneAssetSuffix);

  /// Resolves [sourcePath] (relative to the owning package's root, with or
  /// without the `.glb`/`.fsceneb` extension) to exactly one scene asset key.
  String resolveKey(String sourcePath, {String? package}) {
    final id = _sceneId(sourcePath);
    final matches = _entries
        .where(
          (entry) =>
              entry.sceneId == id &&
              (package == null || entry.package == package),
        )
        .toList();
    if (matches.isEmpty) {
      throw StateError(
        'No DataAssets-backed .fsceneb for source "$sourcePath" was found. '
        'Make sure the build hook calls buildScenes in a DataAssets mode, that '
        'Dart data assets are enabled (flutter config '
        '--enable-dart-data-assets), and that the app has been rebuilt.',
      );
    }
    if (matches.length > 1) {
      final choices = matches.map((match) => match.package).join(', ');
      throw StateError(
        'Multiple DataAssets-backed .fsceneb files for source "$sourcePath" '
        'were found in packages: $choices. Pass package to disambiguate.',
      );
    }
    return matches.single.assetKey;
  }

  /// Loads the scene whose source is [sourcePath] as a [Node].
  ///
  /// Pass a custom [registry] to realize app-defined component types; it only
  /// applies on the first (cache-filling) load of a given scene.
  Future<Node> loadScene(
    String sourcePath, {
    String? package,
    AssetBundle? bundle,
    FsceneComponentRegistry? registry,
  }) {
    final key = resolveKey(sourcePath, package: package);
    final assetBundle = bundle ?? rootBundle;
    // TODO(fscene): register for content hot reload (re-import on source
    // change) once scene hot reload lands, mirroring loadModel.
    return _cache.load(key, () async {
      final data = await assetBundle.load(key);
      return loadFscenebBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        registry: registry,
      );
    });
  }

  static Future<List<String>> _loadAssetManifestKeys(AssetBundle bundle) async {
    final manifest = await AssetManifest.loadFromAssetBundle(bundle);
    return manifest.listAssets();
  }
}

String _sceneId(String sourcePath) {
  if (sourcePath.endsWith('.glb')) {
    return sourcePath.substring(0, sourcePath.length - '.glb'.length);
  }
  if (sourcePath.endsWith(_sceneAssetSuffix)) {
    return sourcePath.substring(
      0,
      sourcePath.length - _sceneAssetSuffix.length,
    );
  }
  return sourcePath;
}

/// Loads a DataAssets-backed `.fsceneb` scene by its source path relative to
/// the owning package's root (for example `assets/levels/forest.glb`).
///
/// The `.fscene` counterpart of `loadModel`. Pass [package] to disambiguate
/// when the same source path is provided by more than one package, and a custom
/// [registry] to realize app-defined component types.
Future<Node> loadScene(
  String sourcePath, {
  String? package,
  AssetBundle? bundle,
  FsceneComponentRegistry? registry,
}) async {
  final sceneRegistry = await SceneRegistry.load(bundle: bundle);
  return sceneRegistry.loadScene(
    sourcePath,
    package: package,
    bundle: bundle,
    registry: registry,
  );
}
