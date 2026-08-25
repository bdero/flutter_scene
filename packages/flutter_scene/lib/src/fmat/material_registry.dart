import 'dart:convert';

import 'package:flutter/foundation.dart' show internal, kDebugMode;
import 'package:flutter/services.dart';
import 'package:flutter_scene/src/fmat/fmat_emitter.dart'
    show
        kFrameworkVaryingSchemaVersion,
        radianceCubeEntryName,
        sidecarSamplesEnvironment;
import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_scene/src/hot_reload/hot_reload_coordinator.dart';
import 'package:flutter_scene/src/generated_assets/generated_asset_lookup.dart';
import 'package:flutter_scene/src/generated_assets/generated_assets.dart';
import 'package:flutter_scene/src/material/preprocessed_material.dart';
import 'package:flutter_scene/src/material/preprocessed_sky.dart';

const String _indexAssetSuffix = '.index.json';
const String _indexAssetPrefix = '/flutter_scene/fmat/';

/// Constructs a typed material from one generated `.fmat` entry.
/// {@category Materials}
typedef FmatMaterialFactory =
    PreprocessedMaterial Function({
      required gpu.Shader fragmentShader,
      required Map<String, Object?> metadata,
      Map<String, gpu.Shader>? vertexShaders,
    });

/// A generated index describing one compiled `.fmat` bundle.
final class FmatMaterialBundleIndex {
  FmatMaterialBundleIndex({
    required this.package,
    required this.bundleName,
    required this.shaderBundleAssetKey,
    required this.sidecarAssetKey,
    required this.materials,
  });

  final String package;
  final String bundleName;
  final String shaderBundleAssetKey;
  final String sidecarAssetKey;
  final Map<String, FmatMaterialIndexEntry> materials;

  /// Parses the index at [assetKey]. The bundle and its sidecar always sit in
  /// the same bundle directory as the index, so their keys come from the
  /// index's own key plus the file names it records.
  factory FmatMaterialBundleIndex.fromJson(
    Map<String, Object?> json, {
    required String assetKey,
  }) {
    final schema = json['schema'];
    if (schema != 2) {
      throw FormatException('Unsupported flutter_scene fmat schema: $schema');
    }
    final materialsJson = (json['materials'] as Map).cast<String, Object?>();
    final directory = assetKey.substring(0, assetKey.lastIndexOf('/') + 1);
    return FmatMaterialBundleIndex(
      package: json['package'] as String,
      bundleName: json['bundleName'] as String,
      shaderBundleAssetKey:
          '$directory${json['shaderBundleFileName'] as String}',
      sidecarAssetKey: '$directory${json['sidecarFileName'] as String}',
      materials: {
        for (final MapEntry(:key, :value) in materialsJson.entries)
          key: FmatMaterialIndexEntry.fromJson(
            (value as Map).cast<String, Object?>(),
          ),
      },
    );
  }
}

/// One material entry in a generated `.fmat` DataAssets index.
final class FmatMaterialIndexEntry {
  FmatMaterialIndexEntry({required this.entryName, required this.source});

  final String entryName;
  final String? source;

  factory FmatMaterialIndexEntry.fromJson(Map<String, Object?> json) =>
      FmatMaterialIndexEntry(
        entryName: json['entryName'] as String,
        source: json['source'] as String?,
      );
}

/// Resolves and loads the `.fmat` materials the `buildMaterials` build hook
/// compiled.
///
/// Materials are keyed by their `.fmat` source path relative to the owning
/// package's root, so two materials that share a name in different directories
/// do not collide.
/// {@category Materials}
final class FmatMaterialRegistry {
  FmatMaterialRegistry._(this._bundle, this._indexes);

  final AssetBundle _bundle;
  final List<FmatMaterialBundleIndex> _indexes;
  final Map<String, gpu.ShaderLibrary> _shaderLibraries = {};
  final Map<String, Map<String, Object?>> _sidecars = {};

  /// Loads every generated flutter_scene `.fmat` bundle index the app ships,
  /// whether it arrived as a data asset or through the generated tree.
  static Future<FmatMaterialRegistry> load({
    AssetBundle? bundle,
    Iterable<String>? assetKeys,
  }) async {
    final assetBundle = bundle ?? rootBundle;
    final keys = assetKeys ?? await _loadAssetManifestKeys(assetBundle);
    final indexKeys = keys.where(isFmatIndexAssetKey).toList()..sort();
    if (assetKeys == null) {
      // A bundle index recorded in the generated tree, keyed by the bundle name
      // rather than by a data-asset path.
      final generated = await loadGeneratedAssetIndex(bundle);
      for (final match in generated.entriesOf(GeneratedAssetFamily.material)) {
        if (match.entry.id.contains('#')) continue;
        indexKeys.add(match.key);
      }
    }
    final indexes = <FmatMaterialBundleIndex>[];
    for (final key in indexKeys) {
      // Evict so a hot reload re-reads a regenerated index.
      if (kDebugMode) assetBundle.evict(key);
      final json = jsonDecode(await assetBundle.loadString(key));
      final index = FmatMaterialBundleIndex.fromJson(
        (json as Map).cast<String, Object?>(),
        assetKey: key,
      );
      // The app's own tree comes first, so its copy of a bundle a dependency
      // also ships (flutter_scene's physical materials) wins.
      if (indexes.any(
        (other) =>
            other.package == index.package &&
            other.bundleName == index.bundleName,
      )) {
        continue;
      }
      indexes.add(index);
    }
    return FmatMaterialRegistry._(assetBundle, indexes);
  }

  /// Returns true when [assetKey] is a generated `.fmat` data-asset index.
  static bool isFmatIndexAssetKey(String assetKey) =>
      assetKey.startsWith('packages/') &&
      assetKey.contains(_indexAssetPrefix) &&
      assetKey.endsWith(_indexAssetSuffix);

  /// Resolves [sourcePath] (the `.fmat` source path relative to the owning
  /// package's root, with or without the `.fmat` extension) to exactly one
  /// generated bundle/index entry.
  ///
  /// Keying by source path (rather than material name) means two materials that
  /// share a name in different directories do not collide.
  FmatMaterialResolution resolve(
    String sourcePath, {
    String? package,
    String? bundleName,
  }) {
    final id = _materialId(sourcePath);
    final matches = <FmatMaterialResolution>[];
    for (final index in _indexes) {
      if (package != null && index.package != package) {
        continue;
      }
      if (bundleName != null && index.bundleName != bundleName) {
        continue;
      }
      for (final entry in index.materials.values) {
        final source = entry.source;
        if (source != null && _materialId(source) == id) {
          matches.add(FmatMaterialResolution(index: index, entry: entry));
        }
      }
    }
    if (matches.isEmpty) {
      throw StateError(
        'No generated .fmat material for source "$sourcePath" was found. '
        '${generatedAssetFixHint('.fmat materials')}',
      );
    }
    if (matches.length > 1) {
      final choices = matches
          .map((match) => '${match.index.package}/${match.index.bundleName}')
          .join(', ');
      throw StateError(
        'Multiple generated .fmat materials for source "$sourcePath" were '
        'found: $choices. Pass package and/or bundleName to disambiguate.',
      );
    }
    return matches.single;
  }

  /// Loads the material whose source is [sourcePath] as a [PreprocessedMaterial].
  Future<PreprocessedMaterial> loadMaterial(
    String sourcePath, {
    String? package,
    String? bundleName,
    FmatMaterialFactory? factory,
  }) async {
    final resolution = resolve(
      sourcePath,
      package: package,
      bundleName: bundleName,
    );
    final index = resolution.index;
    final shaderLibrary = _shaderLibraries[index.shaderBundleAssetKey] ??=
        await _loadShaderLibrary(index.shaderBundleAssetKey);
    final shader = shaderLibrary[resolution.entry.entryName];
    if (shader == null) {
      throw StateError(
        'Shader entry "${resolution.entry.entryName}" was missing from '
        '${index.shaderBundleAssetKey}.',
      );
    }
    final metadataByMaterial = _sidecars[index.sidecarAssetKey] ??=
        await _loadSidecar(index.sidecarAssetKey);
    final metadata = (metadataByMaterial[resolution.entry.entryName] as Map)
        .cast<String, Object?>();
    final varyingSchema = metadata['framework_varying_schema'];
    if (varyingSchema != null &&
        varyingSchema != kFrameworkVaryingSchemaVersion) {
      throw StateError(
        'Material "$sourcePath" was compiled with an incompatible framework '
        'varying schema ($varyingSchema, expected $kFrameworkVaryingSchemaVersion). '
        'Rebuild the material with "flutter clean" or re-run buildMaterials.',
      );
    }
    if (metadata['domain'] == 'sky') {
      throw StateError(
        '"$sourcePath" is a sky .fmat; load it with loadFmatSky instead.',
      );
    }
    // Resolve the generated vertex-stage variants (a `vertex { }` material)
    // from the sidecar's variant -> entry-name map against the same bundle.
    final vertexShaders = _resolveVertexShaders(
      metadata['vertex'],
      shaderLibrary,
      index.shaderBundleAssetKey,
    );
    final material =
        factory?.call(
          fragmentShader: shader,
          metadata: metadata,
          vertexShaders: vertexShaders,
        ) ??
        PreprocessedMaterial(
          fragmentShader: shader,
          metadata: metadata,
          vertexShaders: vertexShaders,
        );
    _applyRadianceCubeShader(
      material,
      metadata,
      resolution.entry.entryName,
      shaderLibrary,
      index.shaderBundleAssetKey,
    );
    _fmatSourcePaths[material] = sourcePath;
    // Track for in-place hot reload: a `.fmat` edit refreshes this material
    // from its regenerated sidecar without rebuilding the scene. Debug-only.
    HotReloadCoordinator.instance.registerFmat(
      material,
      sidecarAssetKey: index.sidecarAssetKey,
      shaderBundleAssetKey: index.shaderBundleAssetKey,
      entryName: resolution.entry.entryName,
    );
    return material;
  }

  /// Resolves the generated vertex variants for a `vertex { }` material from
  /// the sidecar's `vertex` map (variant key -> bundle entry name) against
  /// [shaderLibrary]. Returns null when the material has no vertex stage.
  Map<String, gpu.Shader>? _resolveVertexShaders(
    Object? vertexMeta,
    gpu.ShaderLibrary shaderLibrary,
    String shaderBundleAssetKey,
  ) {
    if (vertexMeta is! Map) return null;
    final result = <String, gpu.Shader>{};
    vertexMeta.forEach((variant, entryName) {
      final shader = shaderLibrary[entryName as String];
      if (shader == null) {
        throw StateError(
          'Vertex shader entry "$entryName" (variant "$variant") was missing '
          'from $shaderBundleAssetKey.',
        );
      }
      result[variant as String] = shader;
    });
    return result.isEmpty ? null : result;
  }

  /// Loads the sky whose source is [sourcePath] as a [PreprocessedSky].
  Future<PreprocessedSky> loadSky(
    String sourcePath, {
    String? package,
    String? bundleName,
  }) async {
    final resolution = resolve(
      sourcePath,
      package: package,
      bundleName: bundleName,
    );
    final index = resolution.index;
    final shaderLibrary = _shaderLibraries[index.shaderBundleAssetKey] ??=
        await _loadShaderLibrary(index.shaderBundleAssetKey);
    final shader = shaderLibrary[resolution.entry.entryName];
    if (shader == null) {
      throw StateError(
        'Shader entry "${resolution.entry.entryName}" was missing from '
        '${index.shaderBundleAssetKey}.',
      );
    }
    final metadataByMaterial = _sidecars[index.sidecarAssetKey] ??=
        await _loadSidecar(index.sidecarAssetKey);
    final metadata = (metadataByMaterial[resolution.entry.entryName] as Map)
        .cast<String, Object?>();
    final varyingSchema = metadata['framework_varying_schema'];
    if (varyingSchema != null &&
        varyingSchema != kFrameworkVaryingSchemaVersion) {
      throw StateError(
        'Sky material "$sourcePath" was compiled with an incompatible framework '
        'varying schema ($varyingSchema, expected $kFrameworkVaryingSchemaVersion). '
        'Rebuild the material with "flutter clean" or re-run buildMaterials.',
      );
    }
    if (metadata['domain'] != 'sky') {
      throw StateError(
        '"$sourcePath" is not a sky .fmat (it has no `sky { }` block); load '
        'it with loadFmatMaterial instead.',
      );
    }
    final sky = PreprocessedSky(fragmentShader: shader, metadata: metadata);
    if (sidecarSamplesEnvironment(metadata)) {
      final cubeEntry = radianceCubeEntryName(resolution.entry.entryName);
      final cubeShader = shaderLibrary[cubeEntry];
      if (cubeShader == null) {
        throw StateError(
          'Radiance cube shader entry "$cubeEntry" was missing from '
          '${index.shaderBundleAssetKey}. Rebuild the material bundle.',
        );
      }
      sky.radianceCubeFragmentShader = cubeShader;
    }
    _fmatSourcePaths[sky] = sourcePath;
    HotReloadCoordinator.instance.registerFmat(
      sky,
      sidecarAssetKey: index.sidecarAssetKey,
      shaderBundleAssetKey: index.shaderBundleAssetKey,
      entryName: resolution.entry.entryName,
    );
    return sky;
  }

  static Future<List<String>> _loadAssetManifestKeys(AssetBundle bundle) async {
    final manifest = await AssetManifest.loadFromAssetBundle(bundle);
    return manifest.listAssets();
  }

  Future<gpu.ShaderLibrary> _loadShaderLibrary(String assetKey) async {
    // TODO(fmat-hot-reload): retain the owning AssetBundle for byte-backed
    // libraries and reinitialize their live shaders after a bundle edit.
    final library = identical(_bundle, rootBundle)
        ? await gpu.loadShaderLibraryAsync(assetKey)
        : await gpu.loadShaderLibraryFromBytesAsync(
            await _bundle.load(assetKey),
          );
    if (library == null) {
      throw StateError('Could not load shader bundle asset "$assetKey".');
    }
    return library;
  }

  Future<Map<String, Object?>> _loadSidecar(String assetKey) async {
    final json = jsonDecode(await _bundle.loadString(assetKey));
    return (json as Map).cast<String, Object?>();
  }
}

/// Loads a generated `.fmat` material by its source path relative to the owning
/// package's root (for example `materials/toon.fmat`).
///
/// Pass [package] and/or [bundleName] to disambiguate when the same source path
/// is provided by more than one bundle.
/// `.fmat` source paths recorded for registry-loaded materials and skies, so
/// provenance-aware tooling (the scene serializer) can recover where a live
/// instance came from.
final Expando<String> _fmatSourcePaths = Expando('fmat source path');

/// The `.fmat` source path [materialOrSky] was loaded from through the
/// registry (`loadFmatMaterial` / `loadFmatSky`), or null for hand-built
/// instances.
String? fmatSourcePathOf(Object materialOrSky) =>
    _fmatSourcePaths[materialOrSky];

/// Stamps [materialOrSky] with the `.fmat` source path it was built from, so
/// a runtime-compiled instance (`FmatBytesLibrary`) serializes the same way a
/// registry load does.
@internal
void setFmatSourcePath(Object materialOrSky, String sourcePath) {
  _fmatSourcePaths[materialOrSky] = sourcePath;
}

/// {@category Materials}
Future<PreprocessedMaterial> loadFmatMaterial(
  String sourcePath, {
  String? package,
  String? bundleName,
  AssetBundle? bundle,
  FmatMaterialFactory? factory,
}) async {
  final registry = await _registryFor(bundle ?? rootBundle);
  return registry.loadMaterial(
    sourcePath,
    package: package,
    bundleName: bundleName,
    factory: factory,
  );
}

/// Loads a generated `.fmat` sky by its source path relative to the owning
/// package's root (for example `assets/gradient_sky.fmat`).
///
/// The `.fmat` must declare a `sky { vec3 Sky(vec3 direction) }` block. Assign
/// the result to `Scene.skybox` via a `Skybox`. Pass [package] and/or
/// [bundleName] to disambiguate when the same source path is provided by more
/// than one bundle.
/// {@category Materials}
Future<PreprocessedSky> loadFmatSky(
  String sourcePath, {
  String? package,
  String? bundleName,
  AssetBundle? bundle,
}) async {
  final registry = await _registryFor(bundle ?? rootBundle);
  return registry.loadSky(sourcePath, package: package, bundleName: bundleName);
}

final Expando<Future<FmatMaterialRegistry>> _registryCache =
    Expando<Future<FmatMaterialRegistry>>('fmat material registries');

Future<FmatMaterialRegistry> _registryFor(AssetBundle bundle) =>
    _registryCache[bundle] ??= FmatMaterialRegistry.load(bundle: bundle);

/// Normalizes a `.fmat` source path for keying (drops a trailing `.fmat`).
String _materialId(String sourcePath) => sourcePath.endsWith('.fmat')
    ? sourcePath.substring(0, sourcePath.length - '.fmat'.length)
    : sourcePath;

/// The resolved bundle/index entry for one material name.
final class FmatMaterialResolution {
  FmatMaterialResolution({required this.index, required this.entry});

  final FmatMaterialBundleIndex index;
  final FmatMaterialIndexEntry entry;
}

/// Resolves the cubemap-radiance twin of [entryName] and attaches it, so a
/// draw against a cube environment picks a shader declaring the matching
/// sampler type. Materials that do not sample the environment have none.
void _applyRadianceCubeShader(
  PreprocessedMaterial material,
  Map<String, Object?> metadata,
  String entryName,
  gpu.ShaderLibrary shaderLibrary,
  String shaderBundleAssetKey,
) {
  if (!sidecarSamplesEnvironment(metadata)) return;
  final cubeEntry = radianceCubeEntryName(entryName);
  final shader = shaderLibrary[cubeEntry];
  if (shader == null) {
    throw StateError(
      'Radiance cube shader entry "$cubeEntry" was missing from '
      '$shaderBundleAssetKey. Rebuild the material bundle.',
    );
  }
  material.setRadianceCubeFragmentShaders(shader);
}
