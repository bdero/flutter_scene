import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'package:flutter_scene/src/importer/model_registry.dart';
import 'package:flutter_scene/src/node.dart';

/// Detects changes to model assets across hot reloads by remembering a content
/// hash per asset key.
class ModelReloadTracker {
  final Map<String, int> _hashes = <String, int>{};

  /// Records the current content of [assetKey] as the baseline, without
  /// reporting a change.
  Future<void> prime(String assetKey, {AssetBundle? bundle}) async {
    _hashes[assetKey] = await _hashAsset(assetKey, bundle ?? rootBundle);
  }

  /// Returns whether [assetKey]'s content changed since the last [prime] or
  /// [hasChanged], updating the stored baseline.
  ///
  /// When the content changed, evicts [assetKey] from the model cache so the
  /// next [Node.fromAsset] re-imports it. Returns false the first time a key is
  /// seen (it records a baseline without reporting a change).
  Future<bool> hasChanged(String assetKey, {AssetBundle? bundle}) async {
    final assetBundle = bundle ?? rootBundle;
    // Drop any cached copy so the fresh (hot-reloaded) bytes are read.
    assetBundle.evict(assetKey);
    final hash = await _hashAsset(assetKey, assetBundle);
    final previous = _hashes[assetKey];
    _hashes[assetKey] = hash;
    final changed = previous != null && previous != hash;
    if (changed) {
      Node.evictModelCache(assetKey);
    }
    return changed;
  }

  static Future<int> _hashAsset(String assetKey, AssetBundle bundle) async {
    final data = await bundle.load(assetKey);
    final bytes = data.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );
    // FNV-1a (32-bit).
    var hash = 0x811c9dc5;
    for (final byte in bytes) {
      hash = (hash ^ byte) & 0xffffffff;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash;
  }
}

/// Rebuilds a flutter_scene scene when its model assets change during hot
/// reload (debug only).
///
/// Mix into the [State] that owns the scene, implement [buildScene] to build
/// (and rebuild) it from its models, and list the model source paths in
/// [reloadableModelSources]. [buildScene] runs once on init and again whenever
/// a listed model changes on hot reload, so it must clear and rebuild the scene
/// (be idempotent).
///
/// ```dart
/// class _MyState extends State<MyWidget> with SceneModelReloadMixin<MyWidget> {
///   final Scene scene = Scene();
///
///   @override
///   List<String> get reloadableModelSources => ['assets/dash.glb'];
///
///   @override
///   Future<void> buildScene() async {
///     scene.removeAll();
///     scene.add(await loadModel('assets/dash.glb'));
///     if (mounted) setState(() {});
///   }
/// }
/// ```
mixin SceneModelReloadMixin<T extends StatefulWidget> on State<T> {
  final ModelReloadTracker _modelReloadTracker = ModelReloadTracker();

  /// Model source paths (as passed to [loadModel]) this scene depends on.
  List<String> get reloadableModelSources => const <String>[];

  /// Builds the scene from its models. Called once on init and again when a
  /// model in [reloadableModelSources] changes on hot reload; must be
  /// idempotent (clear and rebuild).
  Future<void> buildScene();

  @override
  void initState() {
    super.initState();
    _initialBuild();
  }

  Future<void> _initialBuild() async {
    await _primeTrackers();
    if (!mounted) {
      return;
    }
    await buildScene();
  }

  @override
  void reassemble() {
    super.reassemble();
    _reloadChangedModels();
  }

  Future<void> _reloadChangedModels() async {
    var anyChanged = false;
    for (final key in await _resolveKeys()) {
      if (await _modelReloadTracker.hasChanged(key)) {
        anyChanged = true;
      }
    }
    if (anyChanged && mounted) {
      await buildScene();
    }
  }

  Future<void> _primeTrackers() async {
    for (final key in await _resolveKeys()) {
      await _modelReloadTracker.prime(key);
    }
  }

  Future<List<String>> _resolveKeys() async {
    if (reloadableModelSources.isEmpty) {
      return const <String>[];
    }
    final registry = await ModelRegistry.load();
    final keys = <String>[];
    for (final source in reloadableModelSources) {
      try {
        keys.add(registry.resolveKey(source));
      } catch (_) {
        // Not resolvable yet; skip until it appears on a later check.
      }
    }
    return keys;
  }
}
