import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'package:flutter_scene/src/material/preprocessed_material.dart';

/// Coordinates in-place asset hot reload (debug only).
///
/// `loadFmatMaterial` registers the live [PreprocessedMaterial]s it hands out;
/// a `SceneView` calls [onReassemble] on hot reload, and this re-reads any
/// changed `.fmat` sidecar and refreshes the affected materials in place, so a
/// `.fmat` edit (culling, blending, shading model, parameter defaults) shows up
/// without a restart and without app-side wiring.
///
/// Registration uses [WeakReference]s, so tracking never keeps a material (or
/// its scene) alive. Everything here is gated on [kDebugMode] and tree-shaken
/// from release builds.
class HotReloadCoordinator {
  HotReloadCoordinator._();

  /// The process-wide coordinator.
  static final HotReloadCoordinator instance = HotReloadCoordinator._();

  final List<_MaterialRegistration> _materials = <_MaterialRegistration>[];

  /// Content hash of each sidecar asset last seen, to skip unchanged sidecars.
  final Map<String, int> _sidecarHashes = <String, int>{};

  bool _refreshing = false;

  /// Registers a [PreprocessedMaterial] whose per-material metadata lives under
  /// [entryName] in the `.fmat` sidecar at [sidecarAssetKey]. No-op outside
  /// debug.
  void registerMaterial(
    PreprocessedMaterial material, {
    required String sidecarAssetKey,
    required String entryName,
  }) {
    if (!kDebugMode) return;
    _materials.add(
      _MaterialRegistration(
        WeakReference<PreprocessedMaterial>(material),
        sidecarAssetKey,
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
        // Reuse the material's existing shader handle: a sidecar-only edit
        // (culling, blending, defaults) leaves the shader unchanged, and a
        // GLSL edit reloads the shader in place (preserving identity) via the
        // engine, so reflection offsets stay correct either way.
        material.updateFromMetadata(material.fragmentShader, meta);
      }
    }
  }

  static int _fnv1a(String s) {
    var hash = 0x811c9dc5;
    for (final unit in s.codeUnits) {
      hash = (hash ^ unit) & 0xffffffff;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash;
  }
}

class _MaterialRegistration {
  _MaterialRegistration(this.material, this.sidecarAssetKey, this.entryName);

  final WeakReference<PreprocessedMaterial> material;
  final String sidecarAssetKey;
  final String entryName;
}
