import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_scene/src/material/preprocessed_material.dart';

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

  /// Content hash of each sidecar / shader bundle asset last seen, to skip
  /// unchanged assets.
  final Map<String, int> _sidecarHashes = <String, int>{};
  final Map<String, int> _shaderBundleHashes = <String, int>{};

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

  /// Called by every mounted `SceneView` on hot reload. Refreshes changed
  /// materials once per reload (callers while a refresh is already in flight are
  /// ignored). No-op outside debug.
  void onReassemble() {
    if (!kDebugMode) return;
    if (_refreshing) return;
    _refreshing = true;
    _refreshMaterials().whenComplete(() => _refreshing = false);
  }

  Future<void> _refreshMaterials() async {
    _materials.removeWhere((r) => r.material.target == null);
    if (_materials.isEmpty) return;

    await _reinitializeChangedShaderBundles();
    await _refreshChangedSidecars();
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
