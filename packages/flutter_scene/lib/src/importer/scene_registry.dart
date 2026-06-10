import 'package:flutter/services.dart';

import '../fscene/binary/fsceneb.dart';
import '../fscene/compose/compose.dart';
import '../fscene/realize/component_codec.dart';
import '../fscene/realize/realize.dart';
import '../fscene/realize/resource_realizer.dart';
import '../fscene/realize/stage.dart';
import '../fscene/reload/reload.dart';
import '../fscene/scene_document.dart';
import '../hot_reload/hot_reload_coordinator.dart';
import '../node.dart';
import '../scene.dart';

const String _sceneAssetMarker = 'flutter_scene/scene/';
const String _sceneAssetSuffix = '.fsceneb';

/// Called after a hot-reloaded scene has been patched in place (see
/// [loadScene]), so the app can re-apply per-instance customizations the
/// patch may have discarded: re-apply a custom material, or re-grab inner
/// nodes by name. [root] is the same root instance the app holds.
typedef SceneReloadCallback = void Function(Node root);

/// Shared per-asset scene templates: the composed document plus its
/// preloaded resource realizer. Every instance realized from one template
/// shares GPU resources (geometry, materials, textures); each [loadScene]
/// call realizes its own node graph from it. An entry is dropped when the
/// scene's assets hot reload, so the next load re-reads them.
final Map<String, Future<_SceneTemplate>> _sceneTemplates = {};

class _SceneTemplate {
  _SceneTemplate(this.document, this.resources, this.dependencies);

  final SceneDocument document;
  final ResourceRealizer resources;

  /// The asset keys the document was composed from (host + prefabs).
  final Set<String> dependencies;
}

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
  /// The composed document and its realized GPU resources (geometry,
  /// materials, textures) are cached per scene, so loading the same scene
  /// again instantiates a fresh node graph cheaply, sharing those resources.
  ///
  /// Pass [applyStageTo] to also apply the document's stage render settings
  /// (environment, exposure, tone mapping, skybox, and sky lighting) to that
  /// scene, kept fresh across hot reloads. Pass a custom [registry] to
  /// realize app-defined component types, and [onReload] to re-apply
  /// per-instance customizations after a hot reload patches this instance in
  /// place.
  Future<Node> loadScene(
    String sourcePath, {
    String? package,
    AssetBundle? bundle,
    FsceneComponentRegistry? registry,
    SceneReloadCallback? onReload,
    Scene? applyStageTo,
  }) async {
    final key = resolveKey(sourcePath, package: package);
    final assetBundle = bundle ?? rootBundle;

    // Reads the host document and expands any prefab instances, resolving
    // each referenced prefab by source path against this same registry,
    // collecting the asset keys touched into [seen].
    // TODO(fscene): lazily streamed prefab subtrees (LoadPolicy.lazy) load
    // outside the compose, so their assets are not tracked and an edit to
    // one does not hot-reload the host scene.
    Future<SceneDocument> readComposed(Set<String> seen) async {
      final document = await _readDocument(key, assetBundle);
      return document.nodes.values.any((n) => n.instance != null)
          ? await composeSceneAsync(
              document,
              load: (ref) {
                final refKey = resolveKey(ref.key, package: package);
                seen.add(refKey);
                return _readDocument(refKey, assetBundle);
              },
            )
          : document;
    }

    Future<_SceneTemplate> loadTemplate() async {
      final seen = <String>{key};
      final document = await readComposed(seen);
      final resources = ResourceRealizer(document, bundle: assetBundle);
      await resources.preload();
      return _SceneTemplate(document, resources, seen);
    }

    final pending = _sceneTemplates[key] ??= loadTemplate();
    _SceneTemplate template;
    try {
      template = await pending;
    } catch (_) {
      // Don't cache a failed load; the next call retries.
      _sceneTemplates.remove(key);
      rethrow;
    }

    final root = await realizeSceneAsync(
      template.document,
      registry: registry,
      bundle: assetBundle,
      resources: template.resources,
    );
    if (applyStageTo != null) {
      await realizeStage(template.document, applyStageTo, bundle: assetBundle);
    }

    // Patch the live graph in place when the scene's `.fsceneb` (or one of
    // the prefab `.fsceneb`s it is composed from) changes (debug only; a
    // no-op registration in release). The dependency set is shared with the
    // coordinator and refreshed on each reload.
    var current = template.document;
    final dependencies = {...template.dependencies};
    HotReloadCoordinator.instance.registerScene(
      root,
      assetKey: key,
      dependencies: dependencies,
      bundle: assetBundle,
      onReload: () async {
        // The cached template no longer matches the edited assets; drop it
        // so future loads re-read them.
        _sceneTemplates.remove(key);
        final seen = <String>{key};
        final next = await readComposed(seen);
        dependencies
          ..clear()
          ..addAll(seen);
        final diff = await reloadScene(
          root,
          current,
          next,
          registry: registry,
          bundle: assetBundle,
        );
        current = next;
        if (diff.stageChanged && applyStageTo != null) {
          await realizeStage(next, applyStageTo, bundle: assetBundle);
        }
        onReload?.call(root);
      },
    );
    return root;
  }

  Future<SceneDocument> _readDocument(String key, AssetBundle bundle) async {
    // Evict so a hot reload re-reads the changed asset.
    bundle.evict(key);
    final data = await bundle.load(key);
    return readFsceneb(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    );
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
/// Loading the same scene again instantiates a fresh node graph that shares
/// the first load's GPU resources, so per-instance loads are cheap.
///
/// Pass [applyStageTo] to also apply the document's stage render settings
/// (environment, exposure, tone mapping, skybox, and sky lighting) to that
/// scene, kept fresh across hot reloads. Pass [package] to disambiguate when
/// the same source path is provided by more than one package, a custom
/// [registry] to realize app-defined component types, and [onReload] to
/// re-apply per-instance customizations after a hot reload patches the
/// returned scene in place.
Future<Node> loadScene(
  String sourcePath, {
  String? package,
  AssetBundle? bundle,
  FsceneComponentRegistry? registry,
  SceneReloadCallback? onReload,
  Scene? applyStageTo,
}) async {
  final sceneRegistry = await SceneRegistry.load(bundle: bundle);
  return sceneRegistry.loadScene(
    sourcePath,
    package: package,
    bundle: bundle,
    registry: registry,
    onReload: onReload,
    applyStageTo: applyStageTo,
  );
}
