/// Live `.fmat` materials and skies built from runtime-compiled shader-bundle
/// bytes, entirely outside the asset bundle.
///
/// Pairs with `FmatRuntimeCompiler` (the editor compiles a `.fmat` source on
/// disk, then loads the bytes here). [FmatBytesLibrary.refresh] swaps in a
/// recompiled bundle in place, so every live instance updates without a scene
/// rebuild, mirroring what the `HotReloadCoordinator` does for asset-backed
/// bundles.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_scene/src/fmat/fmat_emitter.dart'
    show radianceCubeEntryName, sidecarSamplesEnvironment;
import 'package:flutter_scene/src/fmat/material_registry.dart';
import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_scene/src/hot_reload/hot_reloadable_fmat.dart';
import 'package:flutter_scene/src/material/preprocessed_material.dart';
import 'package:flutter_scene/src/material/preprocessed_sky.dart';
import 'package:flutter_scene/src/scene_encoder.dart';

/// A compiled `.fmat` shader bundle loaded from bytes, from which live
/// [PreprocessedMaterial]s and [PreprocessedSky]s are built and refreshed.
final class FmatBytesLibrary {
  FmatBytesLibrary._(this._library, this._metadata);

  final gpu.ShaderLibrary _library;
  Map<String, Object?> _metadata;

  // Live instances, tracked weakly so a discarded material never pins GPU
  // resources through this registry (same policy as the hot-reload
  // coordinator).
  final List<({String entryName, WeakReference<HotReloadableFmat> instance})>
  _instances = [];

  /// Loads compiled [shaderBundle] bytes with the per-entry [sidecar]
  /// metadata (`{entryName: metadata}`, an `FmatCompileResult.sidecar`).
  static Future<FmatBytesLibrary> load(
    ByteData shaderBundle,
    Map<String, Object?> sidecar,
  ) async {
    final library = await gpu.loadShaderLibraryFromBytesAsync(shaderBundle);
    if (library == null) {
      throw StateError('The shader bundle bytes could not be parsed.');
    }
    return FmatBytesLibrary._(library, sidecar);
  }

  Map<String, Object?> _metadataFor(String entryName) {
    final metadata = _metadata[entryName];
    if (metadata is! Map) {
      throw StateError('No sidecar metadata for shader entry "$entryName".');
    }
    return metadata.cast<String, Object?>();
  }

  gpu.Shader _shaderFor(String entryName) {
    final shader = _library[entryName];
    if (shader == null) {
      throw StateError('Shader entry "$entryName" is missing from the bundle.');
    }
    return shader;
  }

  // Resolves the sidecar's variant -> entry-name map against the bundle.
  Map<String, gpu.Shader>? _vertexShaders(Map<String, Object?> metadata) {
    final vertexMeta = metadata['vertex'];
    if (vertexMeta is! Map) return null;
    final result = <String, gpu.Shader>{};
    vertexMeta.forEach((variant, entryName) {
      result[variant as String] = _shaderFor(entryName as String);
    });
    return result.isEmpty ? null : result;
  }

  /// Builds a surface material from bundle entry [entryName]. [sourcePath]
  /// stamps `.fmat` provenance so the scene serializer round-trips it.
  PreprocessedMaterial createMaterial(String entryName, {String? sourcePath}) {
    final metadata = _metadataFor(entryName);
    if (metadata['domain'] == 'sky') {
      throw StateError('"$entryName" is a sky .fmat; use createSky.');
    }
    final material = PreprocessedMaterial(
      fragmentShader: _shaderFor(entryName),
      metadata: metadata,
      vertexShaders: _vertexShaders(metadata),
    );
    if (sidecarSamplesEnvironment(metadata)) {
      material.setRadianceCubeFragmentShaders(
        _shaderFor(radianceCubeEntryName(entryName)),
      );
    }
    if (sourcePath != null) setFmatSourcePath(material, sourcePath);
    _instances.add((entryName: entryName, instance: WeakReference(material)));
    return material;
  }

  /// Builds a sky source from bundle entry [entryName], which must declare a
  /// `sky { }` block. [sourcePath] stamps provenance like [createMaterial].
  PreprocessedSky createSky(String entryName, {String? sourcePath}) {
    final metadata = _metadataFor(entryName);
    if (metadata['domain'] != 'sky') {
      throw StateError('"$entryName" is not a sky .fmat; use createMaterial.');
    }
    final sky = PreprocessedSky(
      fragmentShader: _shaderFor(entryName),
      metadata: metadata,
    );
    if (sidecarSamplesEnvironment(metadata)) {
      sky.radianceCubeFragmentShader = _shaderFor(
        radianceCubeEntryName(entryName),
      );
    }
    if (sourcePath != null) setFmatSourcePath(sky, sourcePath);
    _instances.add((entryName: entryName, instance: WeakReference(sky)));
    return sky;
  }

  /// Swaps in a recompiled bundle in place. Shader identities are preserved,
  /// every live instance re-reads its render state and parameters (explicitly
  /// set parameter values survive), and the affected cached pipelines are
  /// evicted. Returns an error description (the last good shaders stay
  /// active), or null on success.
  ///
  /// A renamed material changes its bundle entry name, which this cannot
  /// follow; callers detect that (the new compile result's `entryName`
  /// differs) and rebuild instead.
  Future<String?> refresh(
    ByteData shaderBundle,
    Map<String, Object?> sidecar,
  ) async {
    final error = await gpu.reinitializeShaderLibraryFromBytesAsync(
      _library,
      shaderBundle,
    );
    if (error != null) return error;
    _metadata = sidecar;
    final affected = <gpu.Shader>{};
    _instances.removeWhere((record) => record.instance.target == null);
    for (final record in _instances) {
      final instance = record.instance.target;
      if (instance == null) continue;
      final metadata = _metadata[record.entryName];
      final shader = _library[record.entryName];
      if (metadata is! Map || shader == null) {
        debugPrint(
          'flutter_scene: shader entry "${record.entryName}" disappeared on '
          'refresh; its instances keep their last good state',
        );
        continue;
      }
      final cast = metadata.cast<String, Object?>();
      final vertexShaders = _vertexShaders(cast);
      instance.updateFromMetadata(shader, cast);
      if (instance is PreprocessedMaterial) {
        instance.updateVertexShaders(vertexShaders);
      }
      affected.add(shader);
      if (vertexShaders != null) affected.addAll(vertexShaders.values);
    }
    if (affected.isNotEmpty) evictPipelinesForShaders(affected);
    return null;
  }
}
