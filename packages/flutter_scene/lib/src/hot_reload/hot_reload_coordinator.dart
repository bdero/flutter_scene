import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_scene/src/hot_reload/hot_reloadable_fmat.dart';
import 'package:flutter_scene/src/node.dart';
import 'package:flutter_scene/src/scene_encoder.dart';

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
  final List<_SceneRegistration> _scenes = <_SceneRegistration>[];

  /// Content hash of each sidecar / shader bundle / scene asset last
  /// seen, to skip unchanged assets.
  final Map<String, int> _sidecarHashes = <String, int>{};
  final Map<String, int> _shaderBundleHashes = <String, int>{};
  final Map<String, int> _sceneHashes = <String, int>{};

  bool _refreshing = false;

  /// Registers an `.fmat`-backed [material] (a surface material or a sky)
  /// whose shader bundle is at [shaderBundleAssetKey] and whose per-entry
  /// metadata lives under [entryName] in the sidecar at [sidecarAssetKey].
  /// No-op outside debug.
  void registerFmat(
    HotReloadableFmat material, {
    required String sidecarAssetKey,
    required String shaderBundleAssetKey,
    required String entryName,
  }) {
    if (!kDebugMode) return;
    _materials.add(
      _MaterialRegistration(
        WeakReference<HotReloadableFmat>(material),
        sidecarAssetKey,
        shaderBundleAssetKey,
        entryName,
      ),
    );
    _seedBytesHash(shaderBundleAssetKey, rootBundle, _shaderBundleHashes);
    _seedSidecarHash(sidecarAssetKey);
  }

  /// Registers a scene [root] loaded from the `.fsceneb` asset [assetKey]. On
  /// hot reload, when the content of any asset the scene depends on changes,
  /// [onReload] is invoked to re-read the document and patch the live graph in
  /// place (see `loadScene`). The closure owns the re-read / re-compose /
  /// diff / patch; the coordinator only detects the content change and drops
  /// the registration once [root] is collected. No-op outside debug.
  ///
  /// [dependencies] is the live set of asset keys the scene is composed from
  /// ([assetKey] plus any referenced prefab `.fsceneb`s); the caller may
  /// mutate it in place as references change across reloads. Defaults to just
  /// [assetKey]. [bundle] is the bundle the keys load from (default
  /// [rootBundle]).
  void registerScene(
    Node root, {
    required String assetKey,
    Set<String>? dependencies,
    AssetBundle? bundle,
    required Future<void> Function() onReload,
  }) {
    if (!kDebugMode) return;
    final keys = dependencies ?? {assetKey};
    _scenes.add(
      _SceneRegistration(
        WeakReference<Node>(root),
        assetKey,
        keys,
        bundle ?? rootBundle,
        onReload,
      ),
    );
    for (final key in Set<String>.of(keys)) {
      _seedBytesHash(key, bundle ?? rootBundle, _sceneHashes);
    }
  }

  /// Seeds [store] with the hash of [key]'s content as of registration, so
  /// the first reassemble only reloads assets that actually changed since
  /// they were loaded (instead of treating every never-hashed asset as
  /// changed and re-reading every registered scene and bundle).
  final Set<String> _seeding = <String>{};

  void _seedBytesHash(String key, AssetBundle bundle, Map<String, int> store) {
    if (store.containsKey(key) || !_seeding.add(key)) return;
    bundle
        .load(key)
        .then((data) {
          store.putIfAbsent(
            key,
            () => _fnv1aBytes(
              data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
            ),
          );
        })
        .catchError((_) {
          // Not loadable right now; the first reassemble hashes it instead.
        });
  }

  void _seedSidecarHash(String key) {
    if (_sidecarHashes.containsKey(key) || !_seeding.add(key)) return;
    rootBundle
        .loadString(key)
        .then((contents) {
          _sidecarHashes.putIfAbsent(key, () => _fnv1a(contents));
        })
        .catchError((_) {});
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
    _scenes.removeWhere((r) => r.root.target == null);
    if (_materials.isEmpty && _scenes.isEmpty) return;

    await _reinitializeChangedShaderBundles();
    await _refreshChangedSidecars();
    await _refreshChangedScenes();
  }

  /// Re-reads any changed `.fsceneb` scene asset and patches the live graph in
  /// place via each registration's reload closure. Hashes every asset a scene
  /// depends on (the host `.fsceneb` plus the prefab `.fsceneb`s it is
  /// composed from), so an edit to a referenced prefab also reloads the
  /// scenes built from it.
  Future<void> _refreshChangedScenes() async {
    if (_scenes.isEmpty) return;
    final bundles = <String, AssetBundle>{
      for (final r in _scenes)
        for (final key in r.dependencies) key: r.bundle,
    };
    final changedKeys = <String>{};
    for (final entry in bundles.entries) {
      final key = entry.key;
      entry.value.evict(key);
      List<int> bytes;
      try {
        final data = await entry.value.load(key);
        bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      } catch (_) {
        continue; // not available this reload; try again next time
      }
      final hash = _fnv1aBytes(bytes);
      if (_sceneHashes[key] == hash) continue; // unchanged
      _sceneHashes[key] = hash;
      changedKeys.add(key);
    }
    if (changedKeys.isEmpty) return;

    for (final r in _scenes) {
      if (r.root.target == null) continue;
      if (!r.dependencies.any(changedKeys.contains)) continue;
      try {
        await r.onReload();
        debugPrint('flutter_scene: hot-reloaded scene "${r.assetKey}"');
      } catch (e) {
        debugPrint(
          'flutter_scene: scene reload failed for "${r.assetKey}": $e',
        );
      }
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
        // Re-fetches the bundle and recompiles its shaders in place (through
        // the engine on native, the WebGL2 shim on web), so the next pipeline
        // build uses the new code. The material's existing Shader objects
        // keep their identity; awaiting orders the pipeline eviction below
        // after the web recompile completes.
        await gpu.reinitializeShaderLibraryAsync(key);
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
      } catch (e) {
        // The running engine may predate in-place shader reload, or the
        // reloaded source failed to compile; the sidecar refresh below still
        // runs either way.
        debugPrint('flutter_scene: shader bundle reload failed for "$key": $e');
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
      // The build hook leaves this marker when a .fmat failed to compile and
      // the last good shaders were kept; surface it in the console so the
      // silent "nothing changed" reload is explained.
      final compileError = sidecar['#compile_error'];
      if (compileError is String) {
        debugPrint(
          'flutter_scene: a .fmat shader failed to compile; the last good '
          'shaders are still active:\n$compileError',
        );
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

  final WeakReference<HotReloadableFmat> material;
  final String sidecarAssetKey;
  final String shaderBundleAssetKey;
  final String entryName;
}

class _SceneRegistration {
  _SceneRegistration(
    this.root,
    this.assetKey,
    this.dependencies,
    this.bundle,
    this.onReload,
  );

  final WeakReference<Node> root;
  final String assetKey;

  /// The asset keys the scene is composed from (the host plus referenced
  /// prefabs). Shared with the registering loader, which updates it in place
  /// when a reload changes the reference set.
  final Set<String> dependencies;
  final AssetBundle bundle;
  final Future<void> Function() onReload;
}
