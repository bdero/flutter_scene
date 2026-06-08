import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_scene/src/material/preprocessed_material.dart';
import 'package:flutter_scene/src/node.dart';
import 'package:flutter_scene/src/scene_encoder.dart';

/// Called after a hot-reloaded model has been swapped into a live [Node] in
/// place (see `loadModel`), so the app can re-apply per-instance customizations
/// the swap discarded: re-apply a custom material to the new primitives, or
/// re-grab inner nodes by name. The [Node] is the same root instance the app
/// holds; its subtree is the freshly reloaded content.
typedef ModelReloadCallback = void Function(Node root);

/// Coordinates in-place asset hot reload (debug only).
///
/// `loadFmatMaterial` registers the live [PreprocessedMaterial]s it hands out;
/// a `SceneView` calls [onReassemble] on hot reload, and this:
///
///  * reinitializes any changed `.shaderbundle` in place (so an edit to a
///    `.fmat`'s GLSL body reloads the shader), and
///  * re-reads any changed `.fmat` sidecar and refreshes the affected materials'
///    render state and parameters,
///
/// so a `.fmat` edit shows up without a restart and without app-side wiring.
///
/// The shader reload calls `ShaderLibrary.reinitialize`, the same engine entry
/// point the `ext.ui.gpu.reinitializeShaderLibrary` service extension drives;
/// calling it here means flutter_scene does not depend on flutter_tools
/// dispatching that extension.
///
/// Registration uses [WeakReference]s, so tracking never keeps a material (or
/// its scene) alive. Everything here is gated on [kDebugMode] and tree-shaken
/// from release builds.
class HotReloadCoordinator {
  HotReloadCoordinator._();

  /// The process-wide coordinator.
  static final HotReloadCoordinator instance = HotReloadCoordinator._();

  final List<_MaterialRegistration> _materials = <_MaterialRegistration>[];
  final List<_ModelRegistration> _models = <_ModelRegistration>[];
  final List<_SceneRegistration> _scenes = <_SceneRegistration>[];

  /// Content hash of each sidecar / shader bundle / model / scene asset last
  /// seen, to skip unchanged assets.
  final Map<String, int> _sidecarHashes = <String, int>{};
  final Map<String, int> _shaderBundleHashes = <String, int>{};
  final Map<String, int> _modelHashes = <String, int>{};
  final Map<String, int> _sceneHashes = <String, int>{};

  bool _refreshing = false;

  /// Registers a [PreprocessedMaterial] built from the `.fmat` whose shader
  /// bundle is at [shaderBundleAssetKey] and whose per-material metadata lives
  /// under [entryName] in the sidecar at [sidecarAssetKey]. No-op outside debug.
  void registerMaterial(
    PreprocessedMaterial material, {
    required String sidecarAssetKey,
    required String shaderBundleAssetKey,
    required String entryName,
  }) {
    if (!kDebugMode) return;
    _materials.add(
      _MaterialRegistration(
        WeakReference<PreprocessedMaterial>(material),
        sidecarAssetKey,
        shaderBundleAssetKey,
        entryName,
      ),
    );
  }

  /// Registers a model [node] loaded from [assetKey] (the `.model` asset key).
  /// On hot reload, when that asset changes, the node's contents are swapped in
  /// place and [onReload] is invoked so the app can re-apply customizations.
  /// No-op outside debug.
  void registerModel(
    Node node, {
    required String assetKey,
    ModelReloadCallback? onReload,
  }) {
    if (!kDebugMode) return;
    _models.add(
      _ModelRegistration(WeakReference<Node>(node), assetKey, onReload),
    );
  }

  /// Registers a scene [root] loaded from the `.fsceneb` asset [assetKey]. On
  /// hot reload, when that asset's content changes, [onReload] is invoked to
  /// re-read the document and patch the live graph in place (see `loadScene`).
  /// The closure owns the re-read / re-compose / diff / patch; the coordinator
  /// only detects the content change and drops the registration once [root] is
  /// collected. No-op outside debug.
  void registerScene(
    Node root, {
    required String assetKey,
    required Future<void> Function() onReload,
  }) {
    if (!kDebugMode) return;
    _scenes.add(
      _SceneRegistration(WeakReference<Node>(root), assetKey, onReload),
    );
  }

  /// Called by every mounted `SceneView` on hot reload. Refreshes changed
  /// assets once per reload (callers while a refresh is already in flight are
  /// ignored). No-op outside debug.
  void onReassemble() {
    if (!kDebugMode) return;
    if (_refreshing) return;
    _refreshing = true;
    _refresh().whenComplete(() => _refreshing = false);
  }

  Future<void> _refresh() async {
    _materials.removeWhere((r) => r.material.target == null);
    _models.removeWhere((r) => r.node.target == null);
    _scenes.removeWhere((r) => r.root.target == null);
    if (_materials.isEmpty && _models.isEmpty && _scenes.isEmpty) return;

    await _reinitializeChangedShaderBundles();
    await _refreshChangedSidecars();
    await _refreshChangedModels();
    await _refreshChangedScenes();
  }

  /// Re-reads any changed `.fsceneb` scene asset and patches the live graph in
  /// place via each registration's reload closure.
  Future<void> _refreshChangedScenes() async {
    if (_scenes.isEmpty) return;
    final keys = <String>{for (final r in _scenes) r.assetKey};
    for (final key in keys) {
      rootBundle.evict(key);
      List<int> bytes;
      try {
        final data = await rootBundle.load(key);
        bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      } catch (_) {
        continue; // not available this reload; try again next time
      }
      final hash = _fnv1aBytes(bytes);
      if (_sceneHashes[key] == hash) continue; // unchanged
      _sceneHashes[key] = hash;

      for (final r in _scenes) {
        if (r.assetKey != key) continue;
        if (r.root.target == null) continue;
        try {
          await r.onReload();
        } catch (e) {
          debugPrint('flutter_scene: scene reload failed for "$key": $e');
        }
      }
      debugPrint('flutter_scene: hot-reloaded scene "$key"');
    }
  }

  /// Reloads the GLSL of any changed `.shaderbundle` in place. Done before the
  /// sidecar refresh so a parameter-block change is reflected in the shader's
  /// reflection (which the parameter refresh reads for offsets).
  Future<void> _reinitializeChangedShaderBundles() async {
    final keys = <String>{for (final r in _materials) r.shaderBundleAssetKey};
    for (final key in keys) {
      // Drop the cached bytes so the hot-reloaded bundle is re-read.
      rootBundle.evict(key);
      List<int> bytes;
      try {
        final data = await rootBundle.load(key);
        bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      } catch (_) {
        continue; // not available this reload; try again next time
      }
      final hash = _fnv1aBytes(bytes);
      if (_shaderBundleHashes[key] == hash) continue; // unchanged
      _shaderBundleHashes[key] = hash;
      try {
        // Re-fetches the bundle through the engine and marks its shaders dirty
        // so the next pipeline build uses the new code. The material's existing
        // Shader objects keep their identity.
        gpu.ShaderLibrary.reinitialize(key);
        // The Shader objects kept their identity, so the pipeline cache (keyed
        // by the shader pair) still points at pipelines built from the old
        // code. Evict the affected ones so the next draw rebuilds them.
        final affected = <gpu.Shader>{};
        for (final r in _materials) {
          if (r.shaderBundleAssetKey != key) continue;
          final m = r.material.target;
          if (m != null) affected.add(m.fragmentShader);
        }
        evictPipelinesForShaders(affected);
        debugPrint('flutter_scene: hot-reloaded shader bundle "$key"');
      } catch (_) {
        // The running engine may predate in-place shader reload, or the bytes
        // were briefly unavailable; the sidecar refresh below still runs.
      }
    }
  }

  Future<void> _refreshChangedSidecars() async {
    final bySidecar = <String, List<_MaterialRegistration>>{};
    for (final r in _materials) {
      bySidecar.putIfAbsent(r.sidecarAssetKey, () => []).add(r);
    }

    for (final entry in bySidecar.entries) {
      final key = entry.key;
      // Drop the cached bytes so the hot-reloaded sidecar is re-read.
      rootBundle.evict(key);
      String contents;
      try {
        contents = await rootBundle.loadString(key);
      } catch (_) {
        continue; // not available this reload; try again next time
      }
      final hash = _fnv1a(contents);
      if (_sidecarHashes[key] == hash) continue; // unchanged
      _sidecarHashes[key] = hash;

      final Map<String, Object?> sidecar;
      try {
        sidecar = (jsonDecode(contents) as Map).cast<String, Object?>();
      } catch (_) {
        continue;
      }
      for (final r in entry.value) {
        final material = r.material.target;
        if (material == null) continue;
        final meta = (sidecar[r.entryName] as Map?)?.cast<String, Object?>();
        if (meta == null) continue;
        // Reuse the material's existing shader handle: it keeps its identity
        // across a shader reinitialize, so reflection offsets are current.
        try {
          material.updateFromMetadata(material.fragmentShader, meta);
          debugPrint(
            'flutter_scene: hot-reloaded .fmat material "${r.entryName}" '
            '(culling: ${meta['culling']}, blending: ${meta['blending']})',
          );
        } catch (_) {
          // A transient bundle/metadata mismatch mid-reload; the next reload
          // (with consistent assets) refreshes it.
        }
      }
    }
  }

  /// Re-imports any changed `.model` asset and swaps it into the live nodes in
  /// place, then invokes each node's reload callback.
  Future<void> _refreshChangedModels() async {
    if (_models.isEmpty) return;
    final keys = <String>{for (final r in _models) r.assetKey};
    for (final key in keys) {
      rootBundle.evict(key);
      List<int> bytes;
      try {
        final data = await rootBundle.load(key);
        bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      } catch (_) {
        continue; // not available this reload; try again next time
      }
      final hash = _fnv1aBytes(bytes);
      if (_modelHashes[key] == hash) continue; // unchanged
      _modelHashes[key] = hash;

      // Drop the cached template and re-import. fromAsset returns a clone of
      // the fresh template, which reloadFromTemplate clones again per instance.
      Node.evictModelCache(key);
      Node template;
      try {
        template = await Node.fromAsset(key);
      } catch (_) {
        continue;
      }
      for (final r in _models) {
        if (r.assetKey != key) continue;
        final node = r.node.target;
        if (node == null) continue;
        try {
          node.reloadFromTemplate(template);
          r.onReload?.call(node);
        } catch (_) {
          // Skip a node that failed to reload; others still refresh.
        }
      }
      debugPrint('flutter_scene: hot-reloaded model "$key"');
    }
  }

  static int _fnv1a(String s) => _fnv1aBytes(s.codeUnits);

  static int _fnv1aBytes(List<int> units) {
    var hash = 0x811c9dc5;
    for (final unit in units) {
      hash = (hash ^ unit) & 0xffffffff;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash;
  }
}

class _MaterialRegistration {
  _MaterialRegistration(
    this.material,
    this.sidecarAssetKey,
    this.shaderBundleAssetKey,
    this.entryName,
  );

  final WeakReference<PreprocessedMaterial> material;
  final String sidecarAssetKey;
  final String shaderBundleAssetKey;
  final String entryName;
}

class _ModelRegistration {
  _ModelRegistration(this.node, this.assetKey, this.onReload);

  final WeakReference<Node> node;
  final String assetKey;
  final ModelReloadCallback? onReload;
}

class _SceneRegistration {
  _SceneRegistration(this.root, this.assetKey, this.onReload);

  final WeakReference<Node> root;
  final String assetKey;
  final Future<void> Function() onReload;
}
