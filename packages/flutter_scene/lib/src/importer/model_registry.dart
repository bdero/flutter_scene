import 'package:flutter/services.dart';

import '../hot_reload/hot_reload_coordinator.dart';
import '../node.dart';

const String _modelAssetMarker = 'flutter_scene/model/';
const String _modelAssetSuffix = '.model';

/// Resolves and loads `.model` assets registered through DataAssets by the
/// [buildModels] build hook.
///
/// Models are keyed by their source path relative to the owning package's root
/// (for example `assets/vehicles/car.glb`), so two models that share a file
/// name in different directories do not collide.
final class ModelEntry {
  ModelEntry({
    required this.assetKey,
    required this.package,
    required this.modelId,
  });

  /// The full Flutter asset-bundle key, e.g.
  /// `packages/<package>/flutter_scene/model/assets/vehicles/car.model`.
  final String assetKey;

  /// The owning package.
  final String package;

  /// The source path relative to [package]'s root, without extension, e.g.
  /// `assets/vehicles/car`.
  final String modelId;

  static ModelEntry? tryParse(String assetKey) {
    if (!ModelRegistry.isModelAssetKey(assetKey)) {
      return null;
    }
    final rest = assetKey.substring('packages/'.length);
    final slash = rest.indexOf('/');
    if (slash < 0) {
      return null;
    }
    final package = rest.substring(0, slash);
    final afterPackage = rest.substring(slash + 1);
    if (!afterPackage.startsWith(_modelAssetMarker)) {
      return null;
    }
    final relativeModelPath = afterPackage.substring(_modelAssetMarker.length);
    final modelId = relativeModelPath.substring(
      0,
      relativeModelPath.length - _modelAssetSuffix.length,
    );
    return ModelEntry(assetKey: assetKey, package: package, modelId: modelId);
  }
}

/// Resolves DataAssets-backed `.model` files by source path.
final class ModelRegistry {
  ModelRegistry._(this._entries);

  final List<ModelEntry> _entries;

  /// Loads the registry by scanning the asset manifest for `.model` DataAssets.
  static Future<ModelRegistry> load({
    AssetBundle? bundle,
    Iterable<String>? assetKeys,
  }) async {
    final assetBundle = bundle ?? rootBundle;
    final keys = assetKeys ?? await _loadAssetManifestKeys(assetBundle);
    final entries =
        keys.map(ModelEntry.tryParse).whereType<ModelEntry>().toList()
          ..sort((a, b) => a.assetKey.compareTo(b.assetKey));
    return ModelRegistry._(entries);
  }

  /// Returns true when [assetKey] is a generated `.model` DataAsset.
  static bool isModelAssetKey(String assetKey) =>
      assetKey.startsWith('packages/') &&
      assetKey.contains('/$_modelAssetMarker') &&
      assetKey.endsWith(_modelAssetSuffix);

  /// Resolves [sourcePath] (the source path relative to the owning package's
  /// root, with or without the `.glb`/`.model` extension) to exactly one model
  /// asset key.
  String resolveKey(String sourcePath, {String? package}) {
    final id = _modelId(sourcePath);
    final matches = _entries
        .where(
          (entry) =>
              entry.modelId == id &&
              (package == null || entry.package == package),
        )
        .toList();
    if (matches.isEmpty) {
      throw StateError(
        'No DataAssets-backed .model for source "$sourcePath" was found. '
        'Make sure the build hook calls buildModels in a DataAssets mode, that '
        'Dart data assets are enabled (flutter config '
        '--enable-dart-data-assets), and that the app has been rebuilt.',
      );
    }
    if (matches.length > 1) {
      final choices = matches.map((match) => match.package).join(', ');
      throw StateError(
        'Multiple DataAssets-backed .model files for source "$sourcePath" were '
        'found in packages: $choices. Pass package to disambiguate.',
      );
    }
    return matches.single.assetKey;
  }

  /// Loads the model whose source is [sourcePath] as a [Node].
  ///
  /// Pass [onReload] to be notified after a hot reload swaps this model's
  /// content in place (to re-apply materials or re-grab inner nodes); see
  /// [ModelReloadCallback].
  Future<Node> loadModel(
    String sourcePath, {
    String? package,
    ModelReloadCallback? onReload,
  }) async {
    final key = resolveKey(sourcePath, package: package);
    final node = await Node.fromAsset(key);
    // Track for in-place hot reload: a re-exported model swaps into this node
    // without rebuilding the scene. Debug-only.
    HotReloadCoordinator.instance.registerModel(
      node,
      assetKey: key,
      onReload: onReload,
    );
    return node;
  }

  static Future<List<String>> _loadAssetManifestKeys(AssetBundle bundle) async {
    final manifest = await AssetManifest.loadFromAssetBundle(bundle);
    return manifest.listAssets();
  }
}

String _modelId(String sourcePath) {
  if (sourcePath.endsWith('.glb')) {
    return sourcePath.substring(0, sourcePath.length - '.glb'.length);
  }
  if (sourcePath.endsWith(_modelAssetSuffix)) {
    return sourcePath.substring(
      0,
      sourcePath.length - _modelAssetSuffix.length,
    );
  }
  return sourcePath;
}

/// Loads a DataAssets-backed `.model` by its source path relative to the owning
/// package's root (for example `assets/vehicles/car.glb`).
///
/// Pass [package] to disambiguate when the same source path is provided by more
/// than one package.
/// Pass [onReload] to be notified after a hot reload swaps this model's content
/// in place; see [ModelReloadCallback].
Future<Node> loadModel(
  String sourcePath, {
  String? package,
  AssetBundle? bundle,
  ModelReloadCallback? onReload,
}) async {
  final registry = await ModelRegistry.load(bundle: bundle);
  return registry.loadModel(sourcePath, package: package, onReload: onReload);
}
