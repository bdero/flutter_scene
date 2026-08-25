import 'package:flutter/foundation.dart' show internal;
import 'package:flutter/services.dart';

import 'package:scene/scene.dart';

import '../fscene/realize/component_codec.dart';
import '../generated_assets/generated_asset_lookup.dart';
import '../generated_assets/generated_assets.dart';
import '../fscene/realize/realize.dart';
import '../fscene/realize/resource_realizer.dart';
import '../fscene/realize/stage.dart';
import '../fscene/reload/reload.dart';
import '../fscene/source/source_scene_loader.dart';
import '../fscene/stream/stream.dart' as stream;
import '../hot_reload/hot_reload_coordinator.dart';
import '../node.dart';
import '../scene.dart';

const String _sceneAssetMarker = 'flutter_scene/scene/';
const String _sceneAssetSuffix = '.fsceneb';
const String _sceneSourceSuffix = '.fscene';

/// Called after a hot-reloaded scene has been patched in place (see
/// [loadScene]), so the app can re-apply per-instance customizations the
/// patch may have discarded: re-apply a custom material, or re-grab inner
/// nodes by name. [root] is the same root instance the app holds.
/// {@category Assets and loading}
typedef SceneReloadCallback = void Function(Node root);

/// Shared per-asset scene templates: the composed document plus its
/// preloaded resource realizer. Every instance realized from one template
/// shares GPU resources (geometry, materials, textures); each [loadScene]
/// call realizes its own node graph from it. An entry is dropped when the
/// scene's assets hot reload, so the next load re-reads them.
final Map<String, Future<_SceneTemplate>> _sceneTemplates = {};

/// Outstanding [loadScene] claims per template key, so releasing one caller's
/// claim cannot drop a template another caller is still loading instances
/// from.
final Map<String, int> _sceneTemplateHolders = {};

/// One manifest-backed registry per asset bundle for the top-level helpers.
/// Bundle identity is the cache boundary, and [Expando] lets a discarded
/// test or application bundle release its registry with it.
Expando<Future<SceneRegistry>> _sceneRegistries = Expando(
  'flutter_scene scene registries',
);

/// Evicts every cached manifest-backed scene registry so a subsequent load
/// re-reads the bundle manifest.
@internal
void clearSceneRegistryCache() {
  _sceneRegistries = Expando('flutter_scene scene registries');
}

/// Tracked dependency sets of streamed lazy subtrees, keyed by placeholder
/// node, so repeated loads refresh the registration instead of duplicating it.
final Expando<Set<String>> _streamedDependencies = Expando(
  'fscene streamed subtree dependencies',
);

/// App reload callbacks, keyed by the loaded root so the callback (often a
/// bound method of a State that transitively owns the root) lives exactly as
/// long as the root itself. Holding it in the registration's closure instead
/// would keep discarded instances alive through the callback's captures.
final Expando<SceneReloadCallback> _reloadCallbacks = Expando(
  'fscene reload callbacks',
);

class _SceneTemplate {
  _SceneTemplate(this.document, this.resources, this.dependencies);

  final SceneDocument document;
  final ResourceRealizer resources;

  /// The asset keys the document was composed from (host + prefabs).
  final Set<String> dependencies;
}

/// Resolves and loads the `.fsceneb` scene packages the [buildScenes] build hook
/// produced.
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

/// Resolves generated `.fsceneb` files by source path, the `.fscene` counterpart
/// of `ModelRegistry`.
/// {@category Assets and loading}
final class SceneRegistry {
  SceneRegistry._(this._entries);

  final List<SceneEntry> _entries;

  /// Loads the registry by scanning the asset manifest for `.fsceneb` data
  /// assets, then the generated tree's manifest for everything else.
  static Future<SceneRegistry> load({
    AssetBundle? bundle,
    Iterable<String>? assetKeys,
  }) async {
    final assetBundle = bundle ?? rootBundle;
    final keys = assetKeys ?? await _loadAssetManifestKeys(assetBundle);
    final entries = keys
        .map(SceneEntry.tryParse)
        .whereType<SceneEntry>()
        .toList();
    if (assetKeys == null) {
      final generated = await loadGeneratedAssetIndex(bundle);
      for (final match in generated.entriesOf(GeneratedAssetFamily.scene)) {
        // A data asset wins over a tree entry for the same scene, so a project
        // switching modes without a clean asset bundle still resolves once.
        if (entries.any(
          (entry) =>
              entry.sceneId == match.entry.id &&
              entry.package == match.entry.owner,
        )) {
          continue;
        }
        entries.add(
          SceneEntry(
            assetKey: match.key,
            package: match.entry.owner,
            sceneId: match.entry.id,
          ),
        );
      }
    }
    entries.sort((a, b) => a.assetKey.compareTo(b.assetKey));
    return SceneRegistry._(entries);
  }

  /// Returns true when [assetKey] is a generated `.fsceneb` data asset.
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
        'No generated .fsceneb for source "$sourcePath" was found. '
        '${generatedAssetFixHint('scenes')}',
      );
    }
    if (matches.length > 1) {
      final choices = matches.map((match) => match.package).join(', ');
      throw StateError(
        'Multiple generated .fsceneb files for source "$sourcePath" were found '
        'in packages: $choices. Pass package to disambiguate.',
      );
    }
    return matches.single.assetKey;
  }

  /// Resolves a prefab [refKey] referenced by the scene at [hostSourcePath] to
  /// a scene asset key. Prefab references are relative to the referencing
  /// document (how the editor authors them), so this tries the reference joined
  /// onto the host scene's directory first, then the reference as a
  /// package-root-relative path (also accepted), throwing only when neither
  /// resolves.
  String resolveRefKey(String hostSourcePath, String refKey, String? package) {
    final dir = _dirOf(_sceneId(hostSourcePath));
    if (dir.isNotEmpty) {
      try {
        return resolveKey(_joinScenePath(dir, refKey), package: package);
      } on StateError {
        // Not found relative to the host; fall back to the raw reference.
      }
    }
    return resolveKey(refKey, package: package);
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
  /// {@category Assets and loading}
  Future<Node> loadScene(
    String sourcePath, {
    String? package,
    AssetBundle? bundle,
    FsceneComponentRegistry? registry,
    SceneReloadCallback? onReload,
    Scene? applyStageTo,
  }) async {
    // Debug source-direct mode: when the app was launched with a scene
    // source root and this scene's source exists there, read it (and its
    // prefabs) straight from the project so saves are visible without a
    // rebuild. Anything without a source file falls back to its DataAsset.
    final source = bundle == null ? activeSceneSourceLoader() : null;
    final sourceKey = source?.resolveScene(sourcePath);
    if (source != null && sourceKey != null) {
      try {
        return await _loadRealized(
          key: sourceKey,
          bundle: source.bundle,
          readComposed: (seen) => _readComposedSource(source, sourceKey, seen),
          registry: registry,
          onReload: onReload,
          applyStageTo: applyStageTo,
        );
      } catch (e) {
        // An unreadable source (sandboxed app) turns source loading off and
        // falls through to the bundled DataAsset below.
        if (!source.deactivateOnAccessError(e, sourceKey)) rethrow;
        if (activeSceneSourceLoader() == null) {
          // Deactivated. Templates cached under source keys are unreachable
          // by releaseScene now (it resolves DataAsset keys); drop them so
          // their claims cannot strand.
          for (final key
              in _sceneTemplates.keys.where(source.isSourceKey).toList()) {
            _sceneTemplates.remove(key);
            _sceneTemplateHolders.remove(key);
          }
        }
      }
    }

    final key = resolveKey(sourcePath, package: package);
    final assetBundle = bundle ?? rootBundle;

    // Reads the host document and expands any prefab instances, resolving
    // each referenced prefab by source path against this same registry,
    // collecting the asset keys touched into [seen]. (Lazily streamed
    // subtrees register their own assets when loaded; see [loadSubtree].)
    Future<SceneDocument> readComposed(Set<String> seen) async {
      final document = _resolveRefs(await _readDocument(key, assetBundle), key);
      return document.nodes.values.any((n) => n.instance != null)
          ? await composeSceneAsync(
              document,
              load: (ref) {
                final refKey = ref.key;
                seen.add(refKey);
                return _readDocument(
                  refKey,
                  assetBundle,
                ).then((document) => _resolveRefs(document, refKey));
              },
            )
          : document;
    }

    return _loadRealized(
      key: key,
      bundle: assetBundle,
      readComposed: readComposed,
      registry: registry,
      onReload: onReload,
      applyStageTo: applyStageTo,
    );
  }

  /// Reads and composes the scene at project-relative [sourceKey] from
  /// source files, recording every file and asset consumed into [seen].
  Future<SceneDocument> _readComposedSource(
    SceneSourceLoader source,
    String sourceKey,
    Set<String> seen,
  ) async {
    final document = await source.readDocument(sourceKey, seen);
    if (!document.nodes.values.any((n) => n.instance != null)) {
      return document;
    }
    return composeSceneAsync(
      document,
      load: (ref) {
        final refKey = ref.key;
        if (source.isSourceKey(refKey)) {
          return source.readDocument(refKey, seen);
        }
        // No source file (a .glb import, or a prefab from another package):
        // fall back to the built asset. A relative reference resolves
        // against the host scene's directory; nested source prefabs already
        // rebased their references, so the host approximation only matters
        // for references that are missing from the project anyway.
        final assetKey = isSceneAssetKey(refKey)
            ? refKey
            : resolveRefKey(sourceKey, refKey, null);
        seen.add(assetKey);
        return _readDocument(
          assetKey,
          source.bundle,
        ).then((document) => _resolveRefs(document, assetKey));
      },
    );
  }

  /// The shared template-cache + realize + hot-reload-registration tail of
  /// [loadScene], over any document composition path.
  Future<Node> _loadRealized({
    required String key,
    required AssetBundle bundle,
    required Future<SceneDocument> Function(Set<String> seen) readComposed,
    FsceneComponentRegistry? registry,
    SceneReloadCallback? onReload,
    Scene? applyStageTo,
  }) async {
    final assetBundle = bundle;

    Future<_SceneTemplate> loadTemplate() async {
      final seen = <String>{key};
      final document = await readComposed(seen);
      final resources = ResourceRealizer(document, bundle: assetBundle);
      await resources.preload();
      return _SceneTemplate(document, resources, seen);
    }

    final pending = _sceneTemplates[key] ??= loadTemplate();
    // Claimed before the await so a concurrent release cannot evict the
    // shared pending template while this caller is still realizing.
    _sceneTemplateHolders.update(key, (n) => n + 1, ifAbsent: () => 1);

    final _SceneTemplate template;
    try {
      template = await pending;
    } catch (_) {
      // Don't leave a failed load cached; the next call retries. A later
      // load may already have replaced it, so only drop this one.
      if (identical(_sceneTemplates[key], pending)) _sceneTemplates.remove(key);
      _releaseSceneTemplateClaim(key);
      rethrow;
    }

    try {
      final root = await realizeSceneAsync(
        template.document,
        registry: registry,
        bundle: assetBundle,
        resources: template.resources,
      );
      if (applyStageTo != null) {
        await realizeStage(
          template.document,
          applyStageTo,
          bundle: assetBundle,
        );
      }

      // Patch the live graph in place when the scene's `.fsceneb` (or one of
      // the prefab `.fsceneb`s it is composed from) changes (debug only; a
      // no-op registration in release). The dependency set is shared with the
      // coordinator and refreshed on each reload. The closure must hold the
      // root (and the stage scene) weakly: the registration owns the closure,
      // so a strong capture would keep every discarded instance alive forever,
      // accumulating registrations that re-patch dead graphs on each reload.
      var current = template.document;
      var currentResources = template.resources;
      final dependencies = {...template.dependencies};
      final weakRoot = WeakReference(root);
      final weakStageScene = applyStageTo == null
          ? null
          : WeakReference(applyStageTo);
      if (onReload != null) _reloadCallbacks[root] = onReload;
      HotReloadCoordinator.instance.registerScene(
        root,
        assetKey: key,
        dependencies: dependencies,
        bundle: assetBundle,
        onReload: () async {
          final liveRoot = weakRoot.target;
          if (liveRoot == null) return;
          // The cached template no longer matches the edited assets; drop it
          // so future loads re-read them.
          _sceneTemplates.remove(key);
          final seen = <String>{key};
          final next = await readComposed(seen);
          dependencies
            ..clear()
            ..addAll(seen);
          // Seed the new realizer from the live one so only changed
          // resources rebuild (a full re-realize costs seconds at scale),
          // and cache the result as the template for future instance loads.
          final nextResources = ResourceRealizer(next, bundle: assetBundle)
            ..adoptUnchanged(currentResources);
          final diff = await reloadScene(
            liveRoot,
            current,
            next,
            registry: registry,
            bundle: assetBundle,
            resources: nextResources,
          );
          current = next;
          currentResources = nextResources;
          // Re-cache only while a claim exists; a template released
          // mid-reload would otherwise be re-inserted with no holder left
          // to ever evict it.
          if (_sceneTemplateHolders.containsKey(key)) {
            _sceneTemplates[key] = Future.value(
              _SceneTemplate(next, nextResources, {...seen}),
            );
          }
          final stageScene = weakStageScene?.target;
          if (diff.stageChanged && stageScene != null) {
            await realizeStage(next, stageScene, bundle: assetBundle);
          }
          _reloadCallbacks[liveRoot]?.call(liveRoot);
        },
      );
      return root;
    } catch (_) {
      // The caller has no Node to pair with releaseScene after a failed
      // realization, stage application, or registration.
      _releaseSceneTemplateClaim(key);
      rethrow;
    }
  }

  /// Streams a lazy placeholder [node]'s prefab content under it, resolving
  /// the referenced prefab (and its eager references) by source path against
  /// this registry.
  ///
  /// The registry-aware counterpart of `loadSubtree`: the streamed content is
  /// also registered for hot reload, so an edit to any of the prefab assets
  /// re-streams the subtree in place while loaded. References the app holds
  /// into the streamed content go stale after such a reload; re-resolve them
  /// from [node].
  Future<void> loadSubtree(
    Node node, {
    String? package,
    AssetBundle? bundle,
    FsceneComponentRegistry? registry,
  }) async {
    // Debug source-direct mode: stream subtree content from project sources
    // the way loadScene reads whole scenes from them.
    final source = bundle == null ? activeSceneSourceLoader() : null;
    final assetBundle = source?.bundle ?? bundle ?? rootBundle;

    Future<Set<String>> streamIn(Node target) async {
      final seen = <String>{};
      await stream.loadSubtree(
        target,
        registry: registry,
        bundle: assetBundle,
        load: (ref) {
          if (source != null && source.isSourceKey(ref.key)) {
            return source.readDocument(ref.key, seen);
          }
          final key = isSceneAssetKey(ref.key)
              ? ref.key
              : resolveKey(ref.key, package: package);
          seen.add(key);
          return _readDocument(
            key,
            assetBundle,
          ).then((document) => _resolveRefs(document, key));
        },
      );
      return seen;
    }

    final seen = await streamIn(node);
    if (seen.isEmpty) return;

    // Register once per placeholder; later loads just refresh the tracked
    // dependency set (debug only; a no-op registration in release).
    final existing = _streamedDependencies[node];
    if (existing != null) {
      existing
        ..clear()
        ..addAll(seen);
      return;
    }
    final dependencies = {...seen};
    _streamedDependencies[node] = dependencies;
    final weakNode = WeakReference(node);
    HotReloadCoordinator.instance.registerScene(
      node,
      assetKey: seen.first,
      dependencies: dependencies,
      bundle: assetBundle,
      onReload: () async {
        // Re-stream in place only while loaded; an unloaded placeholder
        // streams the fresh content on its next load. Held weakly so a
        // discarded placeholder's registration can be pruned.
        final placeholder = weakNode.target;
        if (placeholder == null || !stream.isSubtreeLoaded(placeholder)) {
          return;
        }
        stream.unloadSubtree(placeholder);
        final refreshed = await streamIn(placeholder);
        dependencies
          ..clear()
          ..addAll(refreshed);
      },
    );
  }

  Future<SceneDocument> _readDocument(String key, AssetBundle bundle) async {
    // Evict so a hot reload re-reads the changed asset.
    bundle.evict(key);
    final data = await bundle.load(key);
    return readFsceneb(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    );
  }

  SceneDocument _resolveRefs(SceneDocument document, String hostKey) {
    SceneEntry? host;
    for (final entry in _entries) {
      if (entry.assetKey == hostKey) {
        host = entry;
        break;
      }
    }
    if (host == null) {
      throw StateError(
        'Scene asset "$hostKey" is not registered. Rebuild the app so every '
        'referenced scene is generated.',
      );
    }
    for (final node in document.nodes.values) {
      final instance = node.instance;
      if (instance == null) continue;
      final source = resolveRefKey(
        host.sceneId,
        instance.source.key,
        host.package,
      );
      node.instance = instance.copyWith(source: AssetRef(source));
    }
    return document;
  }

  static Future<List<String>> _loadAssetManifestKeys(AssetBundle bundle) async {
    final manifest = await AssetManifest.loadFromAssetBundle(bundle);
    return manifest.listAssets();
  }
}

// The directory part of a scene id (everything before the last `/`), or empty.
String _dirOf(String sceneId) {
  final slash = sceneId.lastIndexOf('/');
  return slash < 0 ? '' : sceneId.substring(0, slash);
}

// Joins [rel] onto [dir] (both `/`-separated, package-root-relative) and
// normalizes `.`/`..` segments.
String _joinScenePath(String dir, String rel) {
  final out = <String>[];
  for (final segment in [...dir.split('/'), ...rel.split('/')]) {
    if (segment.isEmpty || segment == '.') continue;
    if (segment == '..') {
      if (out.isNotEmpty) out.removeLast();
      continue;
    }
    out.add(segment);
  }
  return out.join('/');
}

String _sceneId(String sourcePath) {
  if (sourcePath.endsWith('.glb')) {
    return sourcePath.substring(0, sourcePath.length - '.glb'.length);
  }
  if (sourcePath.endsWith(_sceneSourceSuffix)) {
    return sourcePath.substring(
      0,
      sourcePath.length - _sceneSourceSuffix.length,
    );
  }
  if (sourcePath.endsWith(_sceneAssetSuffix)) {
    return sourcePath.substring(
      0,
      sourcePath.length - _sceneAssetSuffix.length,
    );
  }
  return sourcePath;
}

/// Loads a generated `.fsceneb` scene by its source path relative to the owning
/// package's root (for example `assets/levels/forest.glb`).
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
  final sceneRegistry = await _sharedSceneRegistry(bundle);
  return sceneRegistry.loadScene(
    sourcePath,
    package: package,
    bundle: bundle,
    registry: registry,
    onReload: onReload,
    applyStageTo: applyStageTo,
  );
}

/// Streams a lazy placeholder [node]'s prefab content under it, resolving
/// the referenced prefab by its source path (the registry-aware counterpart
/// of `loadSubtree` for scenes loaded with [loadScene]).
///
/// The streamed content hot-reloads: editing any of the prefab's assets
/// re-streams the subtree in place while it is loaded.
/// {@category Assets and loading}
Future<void> loadSceneSubtree(
  Node node, {
  String? package,
  AssetBundle? bundle,
  FsceneComponentRegistry? registry,
}) async {
  final sceneRegistry = await _sharedSceneRegistry(bundle);
  return sceneRegistry.loadSubtree(
    node,
    package: package,
    bundle: bundle,
    registry: registry,
  );
}

// Releases one claim, dropping the cached template only when it was the last.
bool _releaseSceneTemplateClaim(String key) {
  final holders = _sceneTemplateHolders[key];
  if (holders == null) return false;
  if (holders > 1) {
    _sceneTemplateHolders[key] = holders - 1;
    return false;
  }
  _sceneTemplateHolders.remove(key);
  return _sceneTemplates.remove(key) != null;
}

/// Releases one claim on the template [loadScene] built for [sourcePath],
/// dropping it from the shared cache when no claims remain.
///
/// Returns whether the template was dropped. A template holds the scene's
/// realized geometry, materials, and textures, shared by every instance loaded
/// from it, so this is the lever for unloading a level.
///
/// Dropping the template releases the engine's reference, not the memory.
/// Nodes already realized from it keep their own references and stay resident
/// until they are removed from the scene and collected. See
/// `Scene.memoryReport` for what is actually resident.
/// {@category Assets and loading}
Future<bool> releaseScene(
  String sourcePath, {
  String? package,
  AssetBundle? bundle,
}) async {
  // Source-direct templates cache under their project-relative source key.
  final sourceKey = bundle == null
      ? activeSceneSourceLoader()?.resolveScene(sourcePath)
      : null;
  if (sourceKey != null) return _releaseSceneTemplateClaim(sourceKey);
  final registry = await _sharedSceneRegistry(bundle);
  final key = registry.resolveKey(sourcePath, package: package);
  return _releaseSceneTemplateClaim(key);
}

Future<SceneRegistry> _sharedSceneRegistry(AssetBundle? bundle) {
  final assetBundle = bundle ?? rootBundle;
  return _sceneRegistries[assetBundle] ??=
      SceneRegistry.load(bundle: assetBundle).onError((
        Object error,
        StackTrace stackTrace,
      ) {
        _sceneRegistries[assetBundle] = null;
        Error.throwWithStackTrace(error, stackTrace);
      });
}

/// Drops every cached scene template, whatever their outstanding claims.
///
/// Prefer [releaseScene] where the caller knows what it loaded. Nodes already
/// realized keep their own references and stay resident until collected.
/// {@category Assets and loading}
void clearSceneTemplateCache() {
  _sceneTemplates.clear();
  _sceneTemplateHolders.clear();
  clearSceneRegistryCache();
}

/// The number of scene templates the shared cache is holding.
@internal
int sceneTemplateCacheCount() => _sceneTemplates.length;
