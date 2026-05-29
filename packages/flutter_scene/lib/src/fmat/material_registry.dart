import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_scene/src/material/preprocessed_material.dart';

const String _indexAssetSuffix = '.index.json';
const String _indexAssetPrefix = '/flutter_scene/fmat/';

/// A generated index describing one DataAssets-backed `.fmat` bundle.
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

  factory FmatMaterialBundleIndex.fromJson(Map<String, Object?> json) {
    final schema = json['schema'];
    if (schema != 1) {
      throw FormatException('Unsupported flutter_scene fmat schema: $schema');
    }
    final materialsJson = (json['materials'] as Map).cast<String, Object?>();
    return FmatMaterialBundleIndex(
      package: json['package'] as String,
      bundleName: json['bundleName'] as String,
      shaderBundleAssetKey: json['shaderBundleAssetKey'] as String,
      sidecarAssetKey: json['sidecarAssetKey'] as String,
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

/// Resolves and loads `.fmat` materials registered through DataAssets.
final class FmatMaterialRegistry {
  FmatMaterialRegistry._(this._bundle, this._indexes);

  final AssetBundle _bundle;
  final List<FmatMaterialBundleIndex> _indexes;
  final Map<String, gpu.ShaderLibrary> _shaderLibraries = {};
  final Map<String, Map<String, Object?>> _sidecars = {};

  /// Loads all generated flutter_scene `.fmat` DataAssets indexes.
  static Future<FmatMaterialRegistry> load({
    AssetBundle? bundle,
    Iterable<String>? assetKeys,
  }) async {
    final assetBundle = bundle ?? rootBundle;
    final keys = assetKeys ?? await _loadAssetManifestKeys(assetBundle);
    final indexKeys = keys.where(isFmatIndexAssetKey).toList()..sort();
    final indexes = <FmatMaterialBundleIndex>[];
    for (final key in indexKeys) {
      final json = jsonDecode(await assetBundle.loadString(key));
      indexes.add(
        FmatMaterialBundleIndex.fromJson((json as Map).cast<String, Object?>()),
      );
    }
    return FmatMaterialRegistry._(assetBundle, indexes);
  }

  /// Returns true when [assetKey] is a generated `.fmat` DataAssets index.
  static bool isFmatIndexAssetKey(String assetKey) =>
      assetKey.startsWith('packages/') &&
      assetKey.contains(_indexAssetPrefix) &&
      assetKey.endsWith(_indexAssetSuffix);

  /// Resolves [materialName] to exactly one generated bundle/index entry.
  FmatMaterialResolution resolve(
    String materialName, {
    String? package,
    String? bundleName,
  }) {
    final matches = <FmatMaterialResolution>[];
    for (final index in _indexes) {
      if (package != null && index.package != package) {
        continue;
      }
      if (bundleName != null && index.bundleName != bundleName) {
        continue;
      }
      final entry = index.materials[materialName];
      if (entry != null) {
        matches.add(FmatMaterialResolution(index: index, entry: entry));
      }
    }
    if (matches.isEmpty) {
      throw StateError(
        'No DataAssets-backed .fmat material named "$materialName" was found. '
        'Run `dart run flutter_scene:init`, enable Dart data assets on a '
        'supported Flutter master build, and rebuild the app.',
      );
    }
    if (matches.length > 1) {
      final choices = matches
          .map((match) => '${match.index.package}/${match.index.bundleName}')
          .join(', ');
      throw StateError(
        'Multiple DataAssets-backed .fmat materials named "$materialName" were '
        'found: $choices. Pass package and/or bundleName to disambiguate.',
      );
    }
    return matches.single;
  }

  /// Loads [materialName] as a [PreprocessedMaterial].
  Future<PreprocessedMaterial> loadMaterial(
    String materialName, {
    String? package,
    String? bundleName,
  }) async {
    final resolution = resolve(
      materialName,
      package: package,
      bundleName: bundleName,
    );
    final index = resolution.index;
    final shaderLibrary =
        _shaderLibraries[index.shaderBundleAssetKey] ??=
            await _loadShaderLibrary(index.shaderBundleAssetKey);
    final shader = shaderLibrary[resolution.entry.entryName];
    if (shader == null) {
      throw StateError(
        'Shader entry "${resolution.entry.entryName}" was missing from '
        '${index.shaderBundleAssetKey}.',
      );
    }
    final metadataByMaterial =
        _sidecars[index.sidecarAssetKey] ??= await _loadSidecar(
          index.sidecarAssetKey,
        );
    final metadata =
        (metadataByMaterial[resolution.entry.entryName] as Map)
            .cast<String, Object?>();
    return PreprocessedMaterial(fragmentShader: shader, metadata: metadata);
  }

  static Future<List<String>> _loadAssetManifestKeys(AssetBundle bundle) async {
    final manifest = await AssetManifest.loadFromAssetBundle(bundle);
    return manifest.listAssets();
  }

  static Future<gpu.ShaderLibrary> _loadShaderLibrary(String assetKey) async {
    final library = await gpu.loadShaderLibraryAsync(assetKey);
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

/// Loads a DataAssets-backed `.fmat` material by material name.
Future<PreprocessedMaterial> loadFmatMaterial(
  String materialName, {
  String? package,
  String? bundleName,
  AssetBundle? bundle,
}) async {
  final registry = await FmatMaterialRegistry.load(bundle: bundle);
  return registry.loadMaterial(
    materialName,
    package: package,
    bundleName: bundleName,
  );
}

/// The resolved bundle/index entry for one material name.
final class FmatMaterialResolution {
  FmatMaterialResolution({required this.index, required this.entry});

  final FmatMaterialBundleIndex index;
  final FmatMaterialIndexEntry entry;
}
